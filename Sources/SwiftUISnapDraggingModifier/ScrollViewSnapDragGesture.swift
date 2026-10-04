import SwiftUI
import SwiftUIScrollViewInteroperableDragGesture
import UIKit

/// Adapts the native scroll-view handoff recognizer to a snap-drag session.
///
/// The native recognizer owns scrolling, edge sticking, and pan consumption.
/// This adapter owns activation admission and delivery of one observable
/// change/end/cancel sequence to the modifier.
@available(iOS 18.0, *)
struct ScrollViewSnapDragGesture: UIGestureRecognizerRepresentable {

  typealias Value = SnapDraggingModifier.GestureValue
  typealias Recognizer = UIScrollViewInteroperableDragGestureRecognizer

  /// Keeps callbacks current without replacing an active native recognizer.
  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {

    private var gesture: ScrollViewSnapDragGesture
    private var converter: CoordinateSpaceConverter
    private var session = SnapDraggingModifier.GestureSession()
    private var latestValue = Value(translation: .zero, velocity: .zero)
    private var isCancelling = false
    private var pendingCancellation: (@MainActor () -> Void)?
    private var touchBeganInsideScrollableView = false

    // UIKit keeps the delegate weak. Retaining both the native delegate and
    // recognizer also keeps their cleanup path alive when SwiftUI releases us.
    private var recognizer: Recognizer?
    private var nativeDelegate: (any UIGestureRecognizerDelegate)?

    init(gesture: ScrollViewSnapDragGesture, converter: CoordinateSpaceConverter) {
      self.gesture = gesture
      self.converter = converter
    }

    deinit {
      guard let recognizer else { return }

      // UIGestureRecognizerRepresentable has no public dismantle hook. Pass
      // ownership to the main actor so native cancellation can restore hidden
      // scroll indicators and release its ScrollController before deallocation.
      // The modifier handles its own disappearing-view session separately.
      Task { @MainActor in
        recognizer.isEnabled = false
      }
    }

    func install(_ recognizer: Recognizer) {
      self.recognizer = recognizer
      nativeDelegate = recognizer.delegate
      recognizer.delegate = self

      recognizer.onChange = { [weak self] value in
        self?.receiveChange(value)
      }
      recognizer.onEnd = { [weak self] value in
        self?.receiveTerminal(value)
      }
    }

    func update(
      with gesture: ScrollViewSnapDragGesture,
      recognizer: Recognizer,
      converter: CoordinateSpaceConverter
    ) {
      let requiresCancellation = self.gesture.axis != gesture.axis
        || self.gesture.activation != gesture.activation
        || self.gesture.layoutDirection != gesture.layoutDirection
        || !ScrollViewSnapDragGesture.configurationsMatch(
          self.gesture.resolvedConfiguration,
          gesture.resolvedConfiguration
        )

      // Client closures, size, and layout direction belong to the latest view
      // update, including the callback used to finish an invalidated session.
      self.gesture = gesture
      self.converter = converter

      if requiresCancellation {
        cancel(recognizer)
      }

      recognizer.configuration = gesture.resolvedConfiguration
      recognizer.isEnabled = !gesture.axis.isEmpty
    }

    /// Resumes a retained owner without relying on a new representable update.
    func resumeGesture(enabled: Bool) {
      recognizer?.isEnabled = enabled
    }

    /// Cancels native scrolling ownership even if SwiftUI defers gesture updates.
    func cancelActiveGesture(reenable: Bool) {
      deliverPendingCancellation()
      guard let recognizer,
        session.hasDeliveredChange || recognizer.state == .began || recognizer.state == .changed
      else { return }

      let action = session.consumeTerminalAction(for: .cancelled)
      let value = latestValue
      isCancelling = true
      recognizer.isEnabled = false
      isCancelling = false
      if action == .cancel {
        gesture.onCancel(value)
      }
      recognizer.isEnabled = reenable
    }

    func updateConverter(_ converter: CoordinateSpaceConverter) {
      self.converter = converter
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let recognizer = gestureRecognizer as? Recognizer, !gesture.axis.isEmpty else {
        return false
      }

      if gesture.configuration.ignoresScrollView {
        // Ignoring scroll views is direct manipulation. Reject movement on a
        // disabled axis before it can block that scroll view's native pan.
        guard SnapDraggingModifier.GestureAdmission.shouldBegin(
          axis: gesture.axis,
          translation: convertGlobalVector(recognizer.translation(in: nil), to: .local),
          velocity: convertGlobalVector(recognizer.velocity(in: nil), to: .local)
        ) else { return false }
      }

      // Empty target edges request no handoff from a scroll view. Dependency
      // 0.5.0 cannot discover one with empty edges and otherwise treats its pan
      // as an outside drag, so reject it here while retaining outside dragging.
      if gesture.resolvedConfiguration.targetEdges.isEmpty,
        !gesture.configuration.ignoresScrollView,
        touchBeganInsideScrollableView
      {
        return false
      }

      // The native handler resets pan translation when consuming each frame.
      // Capture the touch-down point from raw UIKit values before its first
      // target/action invocation, rather than subtracting handoff translation.
      let location = recognizer.location(in: nil)
      let translation = recognizer.translation(in: nil)
      let startLocation = converter.convert(
        globalPoint: CGPoint(
          x: location.x - translation.x,
          y: location.y - translation.y
        ),
        to: .local
      )

      guard
        SnapDraggingModifier.GestureAdmission.shouldBegin(
          at: startLocation,
          contentSize: gesture.contentSize,
          region: gesture.activation.regionToActivate,
          layoutDirection: gesture.layoutDirection
        )
      else {
        return false
      }

      // ScrollView handoff may begin along either direction. Its native edge
      // policy, rather than dominant-axis admission, decides ownership.
      return nativeDelegate?.gestureRecognizerShouldBegin?(recognizer) ?? true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldReceive touch: UITouch
    ) -> Bool {
      let shouldReceive = nativeDelegate?.gestureRecognizer?(
        gestureRecognizer,
        shouldReceive: touch
      ) ?? true
      guard shouldReceive else { return false }

      // Use the touched responder chain, as native scroll-view discovery does,
      // so descendants and nested scroll views retain their touch-down context.
      touchBeganInsideScrollableView = ScrollViewSnapDragGesture.hasScrollableAncestor(
        from: touch.view
      )
      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      let nativeAllowsSimultaneousRecognition = nativeDelegate?.gestureRecognizer?(
        gestureRecognizer,
        shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
      ) ?? false

      if nativeAllowsSimultaneousRecognition {
        return true
      }

      guard
        !gesture.configuration.ignoresScrollView,
        let scrollView = otherGestureRecognizer.view as? UIScrollView,
        otherGestureRecognizer === scrollView.panGestureRecognizer
      else {
        return false
      }

      // Filtering native targetEdges also filters its scroll-view discovery.
      // A scroll view that moves only on a disabled axis therefore needs this
      // independent pan allowance; it can never receive a lock on that axis.
      return ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(
        axis: gesture.axis,
        scrollView: scrollView
      )
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
        return true
      }

      return nativeDelegate?.gestureRecognizer?(
        gestureRecognizer,
        shouldRequireFailureOf: otherGestureRecognizer
      ) ?? false
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if gesture.configuration.ignoresScrollView,
        let scrollView = otherGestureRecognizer.view as? UIScrollView,
        otherGestureRecognizer === scrollView.panGestureRecognizer
      {
        // The ignored scroll pan must wait for our admission result. Otherwise
        // UIKit's descendant scroll view wins before an outer pan can begin.
        return true
      }
      return nativeDelegate?.gestureRecognizer?(
        gestureRecognizer,
        shouldBeRequiredToFailBy: otherGestureRecognizer
      ) ?? false
    }

    private func receiveChange(_ nativeValue: Recognizer.Value) {
      guard !isCancelling else { return }
      deliverPendingCancellation()

      let value = makeValue(nativeValue)
      latestValue = value
      let admittedTranslation = CGPoint(
        x: gesture.axis.contains(.horizontal) ? value.translation.width : 0,
        y: gesture.axis.contains(.vertical) ? value.translation.height : 0
      )

      guard
        session.hasDeliveredChange
          || (admittedTranslation != .zero
            && SnapDraggingModifier.GestureAdmission.hasReachedMinimumDistance(
              translation: admittedTranslation,
              minimumDistance: gesture.activation.minimumDistance
            ))
      else {
        return
      }

      // Once delivered, returning inside the distance threshold still updates
      // the same session and allows the content to follow back to its origin.
      session.recordDeliveredChange()
      gesture.onChange(value)
    }

    private func receiveTerminal(_ nativeValue: Recognizer.Value) {
      guard let recognizer else { return }
      if !isCancelling {
        deliverPendingCancellation()
      }

      // View removal may invalidate its coordinate namespace before UIKit
      // cancels the pan. Use the cached vector for recovery instead of reading
      // removed SwiftUI geometry through the converter.
      let value = recognizer.state == .ended ? makeValue(nativeValue) : latestValue
      latestValue = value
      switch session.consumeTerminalAction(for: recognizer.state) {
      case .end:
        gesture.onEnd(value)
      case .cancel:
        gesture.onCancel(value)
      case nil:
        break
      }
    }

    private func cancel(_ recognizer: Recognizer) {
      isCancelling = true
      defer { isCancelling = false }

      // Consume before scheduling client code. SwiftUI calls this path during
      // its view update, so state mutations from the callback must happen after
      // that update finishes. Native onEnd then only does cleanup.
      if session.consumeTerminalAction(for: .cancelled) == .cancel {
        let onCancel = gesture.onCancel
        let value = latestValue
        pendingCancellation = {
          onCancel(value)
        }
        Task { @MainActor [weak self] in
          self?.deliverPendingCancellation()
        }
      }

      // UIKit sends the native recognizer's cancellation action. Do not invoke
      // its target/action manually: doing so would consume the same pan twice.
      recognizer.isEnabled = false
    }

    private func deliverPendingCancellation() {
      // A new native event may arrive before the scheduled task. Close the
      // previous observable session first, and consume its callback before
      // invoking client code so later tasks and re-entry cannot deliver twice.
      let cancellation = pendingCancellation
      pendingCancellation = nil
      cancellation?()
    }

    private func makeValue(_ nativeValue: Recognizer.Value) -> Value {
      let translation = convertVector(
        CGPoint(x: nativeValue.translation.width, y: nativeValue.translation.height)
      )
      // Velocity is a vector too; the iOS 18 converter can otherwise include
      // the coordinate space origin in its velocity result.
      let velocity = convertVector(
        CGPoint(x: nativeValue.velocity.width, y: nativeValue.velocity.height)
      )

      return Value(
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGVector(dx: velocity.x, dy: velocity.y)
      )
    }

    /// Removes the origin when mapping a window-space vector for admission.
    private func convertGlobalVector(_ vector: CGPoint, to space: any CoordinateSpaceProtocol) -> CGPoint {
      let origin = converter.convert(globalPoint: .zero, to: space)
      let destination = converter.convert(globalPoint: vector, to: space)
      return CGPoint(x: destination.x - origin.x, y: destination.y - origin.y)
    }

    private func convertVector(_ vector: CGPoint) -> CGPoint {
      guard let view = recognizer?.view else { return vector }

      // Native translation accumulates only motion handed to the outer drag.
      // Convert that vector, rather than using converter.translation after the
      // native recognizer has consumed and reset its raw pan translation.
      let origin = converter.convert(
        globalPoint: view.convert(.zero, to: nil),
        to: gesture.coordinateSpaceInDragging
      )
      let destination = converter.convert(
        globalPoint: view.convert(vector, to: nil),
        to: gesture.coordinateSpaceInDragging
      )
      return CGPoint(x: destination.x - origin.x, y: destination.y - origin.y)
    }
  }

  let control: SnapDraggingModifier.GestureControl
  let axis: Axis.Set
  let activation: SnapDraggingModifier.Activation
  let contentSize: CGSize
  let layoutDirection: LayoutDirection
  let configuration: ScrollViewInteroperableDragGesture.Configuration
  let coordinateSpaceInDragging: any CoordinateSpaceProtocol
  let onChange: @MainActor (Value) -> Void
  let onEnd: @MainActor (Value) -> Void
  let onCancel: @MainActor (Value) -> Void

  /// Narrows native scrolling ownership to the modifier's enabled axes.
  private var resolvedConfiguration: Recognizer.Configuration {
    var configuration = configuration
    if configuration.ignoresScrollView {
      // Native 0.5.0 uses this flag only for simultaneous recognition; its
      // handler still follows scroll-view edges. Empty edges prevent native
      // discovery so ignored views use the outside-drag path instead.
      configuration.targetEdges = []
      return configuration
    }
    if !axis.contains(.horizontal) {
      configuration.targetEdges.subtract(.horizontal)
    }
    if !axis.contains(.vertical) {
      configuration.targetEdges.subtract(.vertical)
    }
    return configuration
  }

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    let coordinator = Coordinator(gesture: self, converter: converter)
    control.register(
      owner: coordinator,
      cancel: { [weak coordinator] reenable in
        coordinator?.cancelActiveGesture(reenable: reenable)
      },
      resume: { [weak coordinator] enabled in
        coordinator?.resumeGesture(enabled: enabled)
      }
    )
    return coordinator
  }

  func makeUIGestureRecognizer(context: Context) -> Recognizer {
    // Both wrapper and native recognizer alias the same configuration type in
    // dependency 0.5.0, preserving edgeActivationMode without a lossy mapping.
    let recognizer = Recognizer(configuration: resolvedConfiguration)
    recognizer.maximumNumberOfTouches = 1
    recognizer.isEnabled = !axis.isEmpty
    context.coordinator.install(recognizer)
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
    context.coordinator.update(with: self, recognizer: recognizer, converter: context.converter)
  }

  func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
    // The native recognizer registered its own target/action in its initializer.
    // Its public onChange/onEnd callbacks are the sole delivery path.
    context.coordinator.updateConverter(context.converter)
  }

  /// Allows a scroll view to keep a pan whose scrollable axes are all disabled
  /// for the outer drag, without changing native handoff on any enabled axis.
  static func allowsDisabledAxisScrolling(axis: Axis.Set, scrollView: UIScrollView) -> Bool {
    guard !axis.isEmpty else { return false }

    let axes = scrollableAxes(in: scrollView)
    let scrollsOnEnabledAxis = !axes.intersection(axis).isEmpty
    let scrollsOnDisabledAxis = !axes.subtracting(axis).isEmpty
    return !scrollsOnEnabledAxis && scrollsOnDisabledAxis
  }

  /// Finds touch-down scrolling context without relying on the native
  /// recognizer's private trackingScrollView or consuming any pan movement.
  static func hasScrollableAncestor(from responder: UIResponder?) -> Bool {
    guard let responder else { return false }

    for ancestor in sequence(first: responder, next: { $0.next }) {
      if let scrollView = ancestor as? UIScrollView,
        !scrollableAxes(in: scrollView).isEmpty
      {
        return true
      }
    }
    return false
  }

  private static func scrollableAxes(in scrollView: UIScrollView) -> Axis.Set {
    guard scrollView.isScrollEnabled else { return [] }

    let inset = scrollView.adjustedContentInset
    let isHorizontallyScrollable = scrollView.contentSize.width + inset.left + inset.right
      > scrollView.bounds.width
      || (scrollView.bounces && scrollView.alwaysBounceHorizontal)
    let isVerticallyScrollable = scrollView.contentSize.height + inset.top + inset.bottom
      > scrollView.bounds.height
      || (scrollView.bounces && scrollView.alwaysBounceVertical)

    var axes: Axis.Set = []
    if isHorizontallyScrollable {
      axes.insert(.horizontal)
    }
    if isVerticallyScrollable {
      axes.insert(.vertical)
    }
    return axes
  }

  private static func configurationsMatch(
    _ lhs: Recognizer.Configuration,
    _ rhs: Recognizer.Configuration
  ) -> Bool {
    let matchesActivationMode: Bool
    switch lhs.edgeActivationMode {
    case .anytime:
      switch rhs.edgeActivationMode {
      case .anytime:
        matchesActivationMode = true
      case .onlyAtGestureStart:
        matchesActivationMode = false
      @unknown default:
        matchesActivationMode = false
      }
    case .onlyAtGestureStart:
      switch rhs.edgeActivationMode {
      case .anytime:
        matchesActivationMode = false
      case .onlyAtGestureStart:
        matchesActivationMode = true
      @unknown default:
        matchesActivationMode = false
      }
    @unknown default:
      matchesActivationMode = false
    }

    return lhs.targetEdges == rhs.targetEdges
      && lhs.ignoresScrollView == rhs.ignoresScrollView
      && lhs.sticksToEdges == rhs.sticksToEdges
      && matchesActivationMode
  }
}
