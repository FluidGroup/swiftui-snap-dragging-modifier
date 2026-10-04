import SwiftUI
import UIKit

/// Admits a UIKit pan before recognition when the enabled axes match its intent.
///
/// The recognizer rejects a cross-axis pan before it can cancel descendant
/// controls. Translation and velocity use the stationary space outside the
/// animated content; touch-down admission uses the content's local space.
@MainActor
struct DirectionalDragGesture: UIGestureRecognizerRepresentable {

  /// Owns one pan's admission, observable lifetime, and current callbacks.
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var gesture: DirectionalDragGesture
    var converter: CoordinateSpaceConverter
    var recognizer: UIPanGestureRecognizer?
    private var session = SnapDraggingModifier.GestureSession()
    private var lastValue = SnapDraggingModifier.GestureValue(translation: .zero, velocity: .zero)
    private var pendingCancellation: (@MainActor () -> Void)?

    init(gesture: DirectionalDragGesture, converter: CoordinateSpaceConverter) {
      self.gesture = gesture
      self.converter = converter
    }

    deinit {
      if let recognizer {
        // SwiftUI exposes no representable teardown hook. Release UIKit's
        // active pan on its actor without requiring actor-isolated deinit.
        Task { @MainActor in recognizer.isEnabled = false }
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
      let translation = convertVector(pan.translation(in: nil), to: .local)
      let velocity = convertVector(pan.velocity(in: nil), to: .local)
      guard SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: gesture.axis, translation: translation, velocity: velocity
      ) else { return false }

      let location = pan.location(in: nil)
      let rawTranslation = pan.translation(in: nil)
      let startLocation = converter.convert(
        globalPoint: CGPoint(x: location.x - rawTranslation.x, y: location.y - rawTranslation.y),
        to: .local
      )
      return SnapDraggingModifier.GestureAdmission.shouldBegin(
        at: startLocation,
        contentSize: gesture.contentSize,
        region: gesture.activation.regionToActivate,
        layoutDirection: gesture.layoutDirection
      )
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
    }

    func update(gesture: DirectionalDragGesture, converter: CoordinateSpaceConverter) {
      let shouldCancel = self.gesture.axis != gesture.axis
        || self.gesture.activation != gesture.activation
        || self.gesture.layoutDirection != gesture.layoutDirection
      if shouldCancel {
        let action = session.consumeTerminalAction(for: .cancelled)
        let value = lastValue
        let onCancel = gesture.onCancel
        recognizer?.isEnabled = false
        if action != nil {
          // Configuration updates run inside SwiftUI's view update. Deliver
          // recovery on the next main turn instead of mutating State inline.
          pendingCancellation = { onCancel(value) }
          Task { @MainActor [weak self] in self?.deliverPendingCancellation() }
        }
      }
      self.gesture = gesture
      self.converter = converter
      recognizer?.isEnabled = !gesture.axis.isEmpty
    }

    /// Resumes a retained owner without relying on a new representable update.
    func resumeGesture(enabled: Bool) {
      recognizer?.isEnabled = enabled
    }

    /// Cancels immediately from the modifier's post-update/disappear callbacks.
    func cancelActiveGesture(reenable: Bool) {
      deliverPendingCancellation()
      guard let recognizer,
        session.hasDeliveredChange || recognizer.state == .began || recognizer.state == .changed
      else { return }

      let action = session.consumeTerminalAction(for: .cancelled)
      let value = lastValue
      recognizer.isEnabled = false
      if action == .cancel {
        gesture.onCancel(value)
      }
      recognizer.isEnabled = reenable
    }

    func handle(_ pan: UIPanGestureRecognizer, converter: CoordinateSpaceConverter) {
      // Cancellation can arrive after SwiftUI destroys this view's coordinate
      // namespace. Its last delivered value is sufficient to recover the snap;
      // never ask the invalid converter to read removed geometry.
      if pan.state == .cancelled || pan.state == .failed {
        finish(state: pan.state, value: lastValue)
        return
      }
      self.converter = converter
      if pan.state == .began || pan.state == .changed {
        // A new event can arrive before the deferred configuration callback.
        // Finish the old observable drag before admitting this new sequence.
        deliverPendingCancellation()
      }
      let translation = convertVector(
        pan.translation(in: nil), to: gesture.coordinateSpaceInDragging
      )
      let velocity = convertVector(
        pan.velocity(in: nil), to: gesture.coordinateSpaceInDragging
      )
      let value = SnapDraggingModifier.GestureValue(
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGVector(dx: velocity.x, dy: velocity.y)
      )
      lastValue = value

      switch pan.state {
      case .began, .changed:
        guard session.hasDeliveredChange
          || SnapDraggingModifier.GestureAdmission.hasReachedMinimumDistance(
            translation: translation, minimumDistance: gesture.activation.minimumDistance
          ) else { return }
        session.recordDeliveredChange()
        gesture.onChange(value)
      case .ended, .cancelled, .failed:
        finish(state: pan.state, value: value)
      case .possible:
        break
      @unknown default:
        finish(state: .cancelled, value: value)
      }
    }

    /// Converts displacement without introducing the coordinate space's origin.
    private func convertVector(_ vector: CGPoint, to space: any CoordinateSpaceProtocol) -> CGPoint {
      // On iOS 18, converter.translation/velocity can include a view-origin
      // offset. Converting two points and subtracting preserves vector semantics
      // for translated, scaled, and rotated SwiftUI coordinate spaces.
      let origin = converter.convert(globalPoint: .zero, to: space)
      let destination = converter.convert(globalPoint: vector, to: space)
      return CGPoint(x: destination.x - origin.x, y: destination.y - origin.y)
    }

    private func finish(state: UIGestureRecognizer.State, value: SnapDraggingModifier.GestureValue) {
      switch session.consumeTerminalAction(for: state) {
      case .end:
        gesture.onEnd(value)
      case .cancel:
        gesture.onCancel(value)
      case nil:
        break
      }
    }

    private func deliverPendingCancellation() {
      let callback = pendingCancellation
      pendingCancellation = nil
      callback?()
    }
  }

  let control: SnapDraggingModifier.GestureControl
  let axis: Axis.Set
  let activation: SnapDraggingModifier.Activation
  let contentSize: CGSize
  let layoutDirection: LayoutDirection
  let coordinateSpaceInDragging: any CoordinateSpaceProtocol
  let onChange: @MainActor (SnapDraggingModifier.GestureValue) -> Void
  let onEnd: @MainActor (SnapDraggingModifier.GestureValue) -> Void
  let onCancel: @MainActor (SnapDraggingModifier.GestureValue) -> Void

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

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    let recognizer = UIPanGestureRecognizer()
    recognizer.maximumNumberOfTouches = 1
    recognizer.cancelsTouchesInView = true
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = context.coordinator
    recognizer.isEnabled = !axis.isEmpty
    context.coordinator.recognizer = recognizer
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
    context.coordinator.update(gesture: self, converter: context.converter)
  }

  func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
    context.coordinator.handle(recognizer, converter: context.converter)
  }
}
