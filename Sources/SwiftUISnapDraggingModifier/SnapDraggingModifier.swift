import RubberBanding
import SwiftUI
import SwiftUIScrollViewInteroperableDragGesture
import SwiftUISupportGeometryEffect
import SwiftUISupportSizing
import UIKit

public protocol GestureMode {

}

public struct GestureModeNormal: GestureMode {}

public struct GestureModeHighPriority: GestureMode {}

/// A gesture mode that lets the drag gesture recognize alongside controls
/// inside the modified view.
public struct GestureModeSimultaneous: GestureMode {}

/// A UIKit-backed gesture mode that begins only when the dominant movement
/// direction is compatible with ``SnapDraggingModifier/axis``.
///
/// UIKit decides when its pan recognizer begins. The modifier's
/// ``SnapDraggingModifier/Activation/minimumDistance`` delays offset and
/// callback delivery after that recognition boundary; it does not replace
/// UIKit's intrinsic pan threshold.
@available(iOS 18, *)
public struct GestureModeDirectional: GestureMode {

  /// The movement and recognizer considered before a directional pan begins.
  ///
  /// The original touch location uses the modified view's local space. The
  /// default SwiftUI installation also uses local translation and velocity;
  /// an explicit UIKit attachment uses window movement so moving the host does
  /// not alter the gesture delta. Velocity is measured in points per second.
  public struct Admission {
    /// The movement accumulated before recognition, in local points.
    public let translation: CGPoint
    /// The original touch location, before applying the translation.
    public let startLocation: CGPoint
    /// The current physical movement rate, in local points per second.
    public let velocity: CGVector
    /// The package-owned recognizer whose delegate remains under package control.
    public let gestureRecognizer: UIPanGestureRecognizer
  }

  let isEnabled: Bool
  let attachmentView: (@MainActor () -> UIView?)?
  let shouldBegin: @MainActor (Admission) -> Bool
  let onRecognizer: @MainActor (UIPanGestureRecognizer) -> Void

  /// Creates a directional gesture with optional caller-owned admission rules.
  /// - Parameters:
  ///   - isEnabled: Whether the recognizer may process a touch sequence.
  ///   - attachmentView: An optional component-owned UIKit host. Supplying this
  ///     eagerly installs the package recognizer before the first touch, rather
  ///     than allowing SwiftUI to create it lazily. Do not return an ancestor
  ///     scroll view or navigation view shared with other components.
  ///   - shouldBegin: An additional check after axis and activation admission.
  ///   - onRecognizer: Called on creation and update. Configure public failure
  ///     relationships here while preserving the package's recognizer delegate.
  public init(
    isEnabled: Bool = true,
    attachmentView: (@MainActor () -> UIView?)? = nil,
    shouldBegin: @escaping @MainActor (Admission) -> Bool = { _ in true },
    onRecognizer: @escaping @MainActor (UIPanGestureRecognizer) -> Void = { _ in }
  ) {
    self.isEnabled = isEnabled
    self.attachmentView = attachmentView
    self.shouldBegin = shouldBegin
    self.onRecognizer = onRecognizer
  }
}

@available(iOS 18, *)
public struct GestureModeScrollViewInteroperable: GestureMode {

  let configuration: ScrollViewInteroperableDragGesture.Configuration

  public init(configuration: ScrollViewInteroperableDragGesture.Configuration) {
    self.configuration = configuration
  }
}

extension GestureMode where Self == GestureModeNormal {

  public static var normal: Self {
    .init()
  }
}

extension GestureMode where Self == GestureModeHighPriority {

  public static var highPriority: Self {
    .init()
  }
}

extension GestureMode where Self == GestureModeSimultaneous {

  public static var simultaneous: Self {
    .init()
  }
}

@available(iOS 18, *)
extension GestureMode where Self == GestureModeDirectional {

  /// Uses the modifier's existing `axis` for both gesture admission and offset
  /// updates, keeping axis configuration in one place.
  public static var directional: Self {
    .init()
  }

  /// Adds admission and recognizer-configuration hooks to directional mode.
  public static func directional(
    isEnabled: Bool = true,
    attachmentView: (@MainActor () -> UIView?)? = nil,
    shouldBegin: @escaping @MainActor (GestureModeDirectional.Admission) -> Bool = { _ in true },
    onRecognizer: @escaping @MainActor (UIPanGestureRecognizer) -> Void = { _ in }
  ) -> Self {
    .init(
      isEnabled: isEnabled, attachmentView: attachmentView,
      shouldBegin: shouldBegin, onRecognizer: onRecognizer
    )
  }
}

@available(iOS 18, *)
extension GestureMode where Self == GestureModeScrollViewInteroperable {

  public static func scrollViewInteroperable(
    _ configuration: ScrollViewInteroperableDragGesture.Configuration
  ) -> Self {
    .init(configuration: configuration)
  }
}

public struct SnapDraggingModifier: ViewModifier {

  public struct Activation {

    public enum Region {
      /// entire view
      case screen
      ///
      case edge(Edge.Set)
    }

    public let minimumDistance: Double
    public let regionToActivate: Region

    public init(minimumDistance: Double = 0, regionToActivate: Region = .screen) {
      self.minimumDistance = minimumDistance
      self.regionToActivate = regionToActivate
    }
  }

  public struct Handler {
    /**
     A callback closure that is called when the user finishes dragging the content.
     This closure takes a CGSize as a return value, which is used as the target offset to finalize the animation.

     For example, return CGSize.zero to put it back to the original position.
     */
    public var onEndDragging:
      (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize) -> CGSize

    /// An optional end callback that also receives the current drawing offset.
    ///
    /// The model offset is the most recently requested, rubber-banded offset.
    /// The presenting offset is the latest value evaluated by the modifier's
    /// geometry effect and can differ while an interactive spring is running.
    /// This callback takes precedence over ``onEndDragging`` when supplied.
    /// Velocity uses points per second and remains mutable for spring control.
    public var onEndDraggingWithPresentation:
      ((_ velocity: inout CGVector, _ offset: CGSize, _ presentingOffset: CGSize,
        _ contentSize: CGSize) -> CGSize)?

    /// Observes the latest drawing offset evaluated by the geometry effect.
    ///
    /// Main-thread evaluation delivers synchronously during rendering;
    /// background evaluation forwards its notification onto main. Update plain
    /// rendering metadata here, rather than SwiftUI state during layout. The
    /// drawing offset is distinct from the model binding and supports external
    /// rendering references whose UIKit frames omit SwiftUI geometry effects.
    public var onPresentingOffsetChange: (CGSize) -> Void

    public var onStartDragging: () -> Void

    fileprivate var onCompleteAnimation: () -> Void

    /// Preserves the original release initializer, including trailing-closure calls.
    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging:
        @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero }
    ) {
      self.init(
        onStartDragging: onStartDragging,
        onEndDragging: onEndDragging,
        onEndDraggingWithPresentation: nil,
        onPresentingOffsetChange: { _ in }
      )
    }

    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging:
        @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero },
      onEndDraggingWithPresentation:
        ((_ velocity: inout CGVector, _ offset: CGSize, _ presentingOffset: CGSize,
          _ contentSize: CGSize) -> CGSize)? = nil,
      onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in }
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
      self.onEndDraggingWithPresentation = onEndDraggingWithPresentation
      self.onPresentingOffsetChange = onPresentingOffsetChange
      self.onCompleteAnimation = {}
    }

    /// Preserves the original release-and-completion initializer.
    @available(iOS 17.0, *)
    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging:
        @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero },
      onCompleteAnimation: @escaping () -> Void
    ) {
      self.init(
        onStartDragging: onStartDragging,
        onEndDragging: onEndDragging,
        onEndDraggingWithPresentation: nil,
        onPresentingOffsetChange: { _ in },
        onCompleteAnimation: onCompleteAnimation
      )
    }

    @available(iOS 17.0, *)
    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging:
        @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero },
      onEndDraggingWithPresentation:
        ((_ velocity: inout CGVector, _ offset: CGSize, _ presentingOffset: CGSize,
          _ contentSize: CGSize) -> CGSize)? = nil,
      onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in },
      onCompleteAnimation: @escaping () -> Void
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
      self.onEndDraggingWithPresentation = onEndDraggingWithPresentation
      self.onPresentingOffsetChange = onPresentingOffsetChange
      self.onCompleteAnimation = onCompleteAnimation
    }

    /// Resolves one release callback while preserving mutable velocity output.
    func targetOffset(
      velocity: inout CGVector,
      offset: CGSize,
      presentingOffset: CGSize,
      contentSize: CGSize
    ) -> CGSize {
      if let onEndDraggingWithPresentation {
        return onEndDraggingWithPresentation(&velocity, offset, presentingOffset, contentSize)
      }
      return onEndDragging(&velocity, offset, contentSize)
    }
  }

  public enum SpringParameter {
    case interpolation(
      mass: Double,
      stiffness: Double,
      damping: Double
    )

    public static var hard: Self {
      .interpolation(mass: 1.0, stiffness: 200, damping: 20)
    }
  }

  public struct Boundary {
    public let min: Double
    public let max: Double
    public let bandLength: Double

    public init(min: Double, max: Double, bandLength: Double) {
      self.min = min
      self.max = max
      self.bandLength = bandLength
    }

    public static var infinity: Self {
      return .init(
        min: -Double.greatestFiniteMagnitude,
        max: Double.greatestFiniteMagnitude,
        bandLength: 0
      )
    }
  }

  /**
   ???
   Use just State instead of GestureState to trigger animation on gesture ended.
   This approach is right?

   refs:
   https://stackoverflow.com/questions/72880712/animate-gesturestate-on-reset
   */
  @Binding private var currentOffset: CGSize

  // value for animating
  @State private var presentingOffset: CGSize = .zero

  // Reference storage is deliberately not Observable: recording actual render
  // geometry must not invalidate SwiftUI while it evaluates a geometry effect.
  @State private var renderedOffsetTracker = RenderedOffsetTracker()

  @State private var targetOffset: CGSize = .zero

  @GestureState private var initialOffset: CGSize?
  @GestureState private var isTracking = false
  @GestureState private var pointInView: CGPoint = .zero

  @State private var isActive = false
  @State private var directionalInitialOffset: CGSize?
  @State private var scrollViewInteroperableInitialOffset: CGSize?
  @State private var contentSize: CGSize = .zero

  @Environment(\.layoutDirection) var layoutDirection

  public let axis: Axis.Set
  public let springParameter: SpringParameter
  public let gestureMode: any GestureMode
  public let activation: Activation

  private let horizontalBoundary: Boundary
  private let verticalBoundary: Boundary
  private let handler: Handler

  /// An explicit recovery position for a cancelled gesture.
  ///
  /// A caller can reset an accepted handoff's public offset while preserving
  /// the rendering view. Supplying its resting position prevents a later
  /// cancellation from restoring the previous handoff's private target.
  private let cancelTargetOffset: CGSize?

  /// Creates a modifier that tracks movement and springs to the handler's target.
  /// - Parameter cancelTargetOffset: An optional resting offset for cancellation
  ///   in directional mode. `nil` preserves recovery to the last handler target.
  public init(
    gestureMode: any GestureMode,
    offset: Binding<CGSize>,
    activation: Activation = .init(),
    axis: Axis.Set = [.horizontal, .vertical],
    horizontalBoundary: Boundary = .infinity,
    verticalBoundary: Boundary = .infinity,
    springParameter: SpringParameter = .hard,
    cancelTargetOffset: CGSize? = nil,
    handler: Handler = .init()
  ) {
    self._currentOffset = offset
    self.axis = axis
    self.springParameter = springParameter
    self.horizontalBoundary = horizontalBoundary
    self.verticalBoundary = verticalBoundary
    self.gestureMode = gestureMode
    self.handler = handler
    self.activation = activation
    self.cancelTargetOffset = cancelTargetOffset
  }

  public func body(content: Content) -> some View {

    let base =
      content
      .coordinateSpace(name: _CoordinateSpaceTag.pointInView)
      .measureSize($contentSize)
      .onChange(of: isTracking) { newValue in
        guard newValue == false else {
          return
        }

        if isActive, currentOffset != targetOffset {
          // For recovery of gesture unexpectedly canceled by the other gesture.
          // `onEnded` never get called in the case.
          self.onEnded(velocity: .zero)
        }
        isActive = false
      }

    if #available(iOS 18, *) {

      Group {
        switch gestureMode {
        case _ as GestureModeNormal:
          base
            .gesture(dragGesture.simultaneously(with: gesture), including: .all)
        case _ as GestureModeHighPriority:
          base
            .highPriorityGesture(dragGesture.simultaneously(with: gesture), including: .all)
        case _ as GestureModeSimultaneous:
          base
            .simultaneousGesture(dragGesture.simultaneously(with: gesture), including: .all)
        case let directional as GestureModeDirectional:
          if directional.attachmentView != nil {
            base.background(
              EagerDirectionalGestureInstallation(gesture: directionalGesture(configuration: directional))
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            )
          } else {
            base.gesture(directionalGesture(configuration: directional))
          }
        case let scrollViewInteroperable as GestureModeScrollViewInteroperable:
          base
            .gesture(_gesture(configuration: scrollViewInteroperable.configuration))
            .simultaneousGesture(gesture)
        default:
          EmptyView()
        }
      }
      ._animatableOffset(
        x: currentOffset.width, presenting: $presentingOffset.width,
        renderingTracker: renderedOffsetTracker,
        onPresentingOffsetChange: handler.onPresentingOffsetChange
      )
      ._animatableOffset(
        y: currentOffset.height, presenting: $presentingOffset.height,
        renderingTracker: renderedOffsetTracker,
        onPresentingOffsetChange: handler.onPresentingOffsetChange
      )

      .coordinateSpace(name: _CoordinateSpaceTag.transition)
      .onChange(of: isTracking) { newValue in
        if newValue {
          handler.onStartDragging()
        }
      }

    } else {

      let addingGesture = dragGesture.simultaneously(with: gesture)

      Group {
        switch gestureMode {
        case _ as GestureModeNormal:
          base
            .gesture(addingGesture, including: .all)
        case _ as GestureModeHighPriority:
          base
            .highPriorityGesture(addingGesture, including: .all)
        case _ as GestureModeSimultaneous:
          base
            .simultaneousGesture(addingGesture, including: .all)
        default:
          EmptyView()
        }
      }
      ._animatableOffset(
        x: currentOffset.width, presenting: $presentingOffset.width,
        renderingTracker: renderedOffsetTracker,
        onPresentingOffsetChange: handler.onPresentingOffsetChange
      )
      ._animatableOffset(
        y: currentOffset.height, presenting: $presentingOffset.height,
        renderingTracker: renderedOffsetTracker,
        onPresentingOffsetChange: handler.onPresentingOffsetChange
      )

      .coordinateSpace(name: _CoordinateSpaceTag.transition)
      .onChange(of: isTracking) { newValue in
        if newValue {
          handler.onStartDragging()
        }
      }

    }

  }

  @available(iOS 18.0, *)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  @available(visionOS, unavailable)
  private func directionalGesture(configuration: GestureModeDirectional) -> DirectionalDragGesture {
    DirectionalDragGesture(
      axis: axis,
      activation: activation,
      contentSize: contentSize,
      layoutDirection: layoutDirection,
      configuration: configuration,
      onChange: { value in
        if directionalInitialOffset == nil {
          directionalInitialOffset = renderedOffsetTracker.offset
          handler.onStartDragging()
        }

        let baseOffset = directionalInitialOffset ?? renderedOffsetTracker.offset
        updateOffset(
          baseOffset: baseOffset,
          translation: value.translation
        )
      },
      onEnd: { value in
        if directionalInitialOffset != nil {
          onEnded(velocity: value.velocity)
        }
        directionalInitialOffset = nil
      },
      onCancel: {
        if directionalInitialOffset != nil {
          resetToTargetOffset()
        }
        directionalInitialOffset = nil
      }
    )
  }

  private func isInActivation(startLocation: CGPoint) -> Bool {

    switch activation.regionToActivate {
    case .screen:
      return true
    case .edge(let edge):

      let space: Double = 20
      let contentSize = self.contentSize

      if edge.contains(.leading) {
        switch layoutDirection {
        case .leftToRight:
          if CGRect(origin: .zero, size: .init(width: space, height: contentSize.height)).contains(
            startLocation
          ) {
            return true
          }
        case .rightToLeft:
          if CGRect(
            origin: .init(x: contentSize.width - space, y: 0),
            size: .init(width: space, height: contentSize.height)
          ).contains(startLocation) {
            return true
          }
        @unknown default:
          break
        }
      }

      if edge.contains(.trailing) {
        switch layoutDirection {
        case .leftToRight:
          if CGRect(
            origin: .init(x: contentSize.width - space, y: 0),
            size: .init(width: space, height: contentSize.height)
          ).contains(startLocation) {
            return true
          }
        case .rightToLeft:
          if CGRect(origin: .zero, size: .init(width: 20, height: CGFloat.greatestFiniteMagnitude))
            .contains(startLocation)
          {
            return true
          }
        @unknown default:
          return false
        }
      }

      if edge.contains(.top) {
        if CGRect(origin: .zero, size: .init(width: contentSize.width, height: space)).contains(
          startLocation
        ) {
          return true
        }
      }

      if edge.contains(.bottom) {
        if CGRect(
          origin: .init(x: 0, y: contentSize.height - space),
          size: .init(width: contentSize.width, height: space)
        ).contains(startLocation) {
          return true
        }
      }

      return false
    }

  }

  private var gesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(_CoordinateSpaceTag.pointInView))
      .updating(
        $pointInView,
        body: { v, s, _ in
          s = v.startLocation
        }
      )
  }

  @available(iOS 18.0, *)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  @available(visionOS, unavailable)
  private func _gesture(configuration: ScrollViewInteroperableDragGesture.Configuration)
    -> ScrollViewInteroperableDragGesture
  {

    return ScrollViewInteroperableDragGesture(
      configuration: configuration,
      coordinateSpaceInDragging: .named(_CoordinateSpaceTag.transition),
      onChange: { value in

        //      if self.isActive || isInActivation(startLocation: value.startLocation) {
        //
        //        self.isActive = true

        if scrollViewInteroperableInitialOffset == nil {
          scrollViewInteroperableInitialOffset = presentingOffset
          handler.onStartDragging()
        }

        let baseOffset = scrollViewInteroperableInitialOffset ?? presentingOffset

        updateOffset(
          baseOffset: baseOffset,
          translation: value.translation
        )
        //      }
      },
      onEnd: { value in
        if scrollViewInteroperableInitialOffset != nil {
          onEnded(
            velocity: .init(
              dx: value.velocity.width,
              dy: value.velocity.height
            )
          )
        }
        scrollViewInteroperableInitialOffset = nil
      })
  }

  private var dragGesture: some Gesture {

    DragGesture(
      minimumDistance: activation.minimumDistance,
      coordinateSpace: .named(_CoordinateSpaceTag.transition)
    )
    .updating(
      $initialOffset,
      body: { _, state, _ in
        if state == nil {
          state = presentingOffset
        }
      }
    )
    .updating(
      $isTracking,
      body: { _, state, _ in
        state = true
      }
    )
    .onChanged({ value in

      if self.isActive || isInActivation(startLocation: value.startLocation) {

        self.isActive = true

        // TODO: including minimumDistance

        // Because of GestureState, this value is set always.
        let baseOffset = initialOffset!

        updateOffset(
          baseOffset: baseOffset,
          translation: value.translation
        )
      }
    })
    .onEnded({ value in

      if isActive {
        onEnded(
          velocity: .init(
            dx: value.velocity.width,
            dy: value.velocity.height
          )
        )
      } else {
        assert(currentOffset == targetOffset)
      }

      self.isActive = false
    })

  }

  private func updateOffset(baseOffset: CGSize, translation: CGSize) {
    let proposedOffset = CGSize(
      width: baseOffset.width + translation.width,
      height: baseOffset.height + translation.height
    )

    // Stop visually following an older target animation as soon as a new
    // interactive drag supplies its own presentation value.
    withAnimation(.interactiveSpring()) {
      if axis.contains(.horizontal) {
        currentOffset.width = rubberBand(
          value: proposedOffset.width,
          min: horizontalBoundary.min,
          max: horizontalBoundary.max,
          bandLength: horizontalBoundary.bandLength
        )
      }
      if axis.contains(.vertical) {
        currentOffset.height = rubberBand(
          value: proposedOffset.height,
          min: verticalBoundary.min,
          max: verticalBoundary.max,
          bandLength: verticalBoundary.bandLength
        )
      }
    }
  }

  private func resetToTargetOffset() {
    let targetOffset = SnapDraggingCancellation.target(
      lastTarget: self.targetOffset,
      explicitTarget: cancelTargetOffset
    )
    self.targetOffset = targetOffset

    let animation: Animation = {
      switch springParameter {
      case .interpolation(let mass, let stiffness, let damping):
        return .interpolatingSpring(
          mass: mass,
          stiffness: stiffness,
          damping: damping,
          initialVelocity: 0
        )
      }
    }()

    withAnimation(animation) {
      currentOffset = targetOffset
    }
  }

  private func onEnded(velocity: CGVector) {
    var usingVelocity = velocity

    let targetOffset = handler.targetOffset(
      velocity: &usingVelocity,
      offset: currentOffset,
      presentingOffset: renderedOffsetTracker.offset,
      contentSize: contentSize
    )

    self.targetOffset = targetOffset

    let velocity = usingVelocity

    let distance = CGSize(
      width: targetOffset.width - currentOffset.width,
      height: targetOffset.height - currentOffset.height
    )

    let mappedVelocity = CGVector(
      dx: mappedInitialVelocity(velocity: velocity.dx, distance: distance.width),
      dy: mappedInitialVelocity(velocity: velocity.dy, distance: distance.height)
    )

    var animationX: Animation {
      switch springParameter {
      case .interpolation(let mass, let stiffness, let damping):
        return .interpolatingSpring(
          mass: mass,
          stiffness: stiffness,
          damping: damping,
          initialVelocity: mappedVelocity.dx
        )
      }
    }

    var animationY: Animation {
      switch springParameter {
      case .interpolation(let mass, let stiffness, let damping):
        return .interpolatingSpring(
          mass: mass,
          stiffness: stiffness,
          damping: damping,
          initialVelocity: mappedVelocity.dy
        )
      }
    }

    if #available(iOS 17.0, *) {
      let group = DispatchGroup()
      group.enter()
      group.enter()

      group.notify(queue: .main) { [handler] in
        handler.onCompleteAnimation()
      }

      withAnimation(animationX) {
        currentOffset.width = targetOffset.width
      } completion: {
        group.leave()
      }

      withAnimation(animationY) {
        currentOffset.height = targetOffset.height
      } completion: {
        group.leave()
      }

    } else {
      withAnimation(
        animationX
      ) {
        currentOffset.width = targetOffset.width
      }

      withAnimation(
        animationY
      ) {
        currentOffset.height = targetOffset.height
      }
    }

  }

  private func mappedInitialVelocity(velocity: CGFloat, distance: CGFloat) -> CGFloat {
    guard abs(distance) >= 1 else {
      return 0
    }

    return velocity / distance
  }

}

/// Resolves cancellation after an external offset reset without discarding view identity.
enum SnapDraggingCancellation {
  static func target(lastTarget: CGSize, explicitTarget: CGSize?) -> CGSize {
    explicitTarget ?? lastTarget
  }
}

private enum _CoordinateSpaceTag: Hashable {
  case pointInView
  case transition
}

#if DEBUG

  #Preview("Joystick") {
    Joystick()
  }

  #Preview("SwipeAction") {
    SwipeAction()
  }

  struct Joystick: View {

    @State var offset: CGSize = .zero

    @State var isOn: Bool = false

    var body: some View {
      stick
        .padding(10)
    }

    private var stick: some View {

      VStack {

        Button("Add offset") {
          withAnimation(.interpolatingSpring(mass: 1, stiffness: 1, damping: 1, initialVelocity: 0))
          {
            offset.width += 10
          }
        }

        Circle()
          .fill(Color.yellow)
          .frame(width: 100, height: 100)
          .modifier(
            SnapDraggingModifier(
              gestureMode: .normal,
              offset: $offset,
              activation: .init(minimumDistance: 0),
              springParameter: .interpolation(mass: 1, stiffness: 1, damping: 1)
            )
          )
        Circle()
          .fill(Color.green)
          .frame(width: 100, height: 100)

      }
      .padding(20)
      .background(Color.secondary)
      .coordinateSpace(name: "A")

    }
  }

  struct SwipeAction: View {

    @State var offset: CGSize = .zero

    var body: some View {

      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.blue)
        .frame(width: nil, height: 50)
        .modifier(
          SnapDraggingModifier(
            gestureMode: .normal,
            offset: $offset,
            axis: .horizontal,
            horizontalBoundary: .init(min: 0, max: .infinity, bandLength: 50),
            springParameter: .interpolation(mass: 1, stiffness: 100, damping: 10),
            handler: .init(onEndDragging: { velocity, offset, contentSize in

              print(velocity, offset, contentSize)

              if velocity.dx > 50 || offset.width > (contentSize.width / 2) {
                print("remove")
                return .init(width: contentSize.width, height: 0)
              } else {
                print("stay")
                return .zero
              }
            })
          )
        )
        .padding(.horizontal, 20)

    }

  }

#endif
