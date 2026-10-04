import RubberBanding
import SwiftUI
import SwiftUIScrollViewInteroperableDragGesture

/// Makes content draggable with per-axis rubber-band boundaries and a spring snap.
///
/// UIKit recognizers own admission and gesture lifetime. The offset binding owns
/// the requested displacement; presentation is tracked to allow a new drag to
/// interrupt an in-flight snap without jumping to its destination.
@MainActor
public struct SnapDraggingModifier: ViewModifier {

  /// Chooses how the UIKit pan cooperates with surrounding gestures.
  public enum GestureMode {
    /// Admits a single-axis drag only when that axis dominates the movement.
    case directional
    /// Transfers movement from a scroll view at its configured edges.
    case scrollViewInteroperable(ScrollViewInteroperableDragGesture.Configuration)

    /// Identifies the recognizer owner independently of live configuration.
    enum Kind {
      case directional
      case scrollViewInteroperable
    }

    var kind: Kind {
      switch self {
      case .directional: return .directional
      case .scrollViewInteroperable: return .scrollViewInteroperable
      }
    }
  }

  /// Controls where a drag may start and when its changes become observable.
  public struct Activation: Equatable {

    /// Describes the permitted touch-down region in the modified content.
    public enum Region: Equatable {
      /// Allows a drag to start anywhere in the content.
      case screen
      /// Allows a drag within 20 points of the selected semantic edges.
      case edge(Edge.Set)
    }

    /// The movement in points required before delivering offsets and callbacks.
    ///
    /// UIKit still owns its pan-recognition threshold. Once this distance is
    /// reached, returning closer to the starting point does not deactivate a drag.
    public let minimumDistance: Double
    /// The touch-down region admitted before UIKit recognizes the pan.
    public let regionToActivate: Region

    public init(minimumDistance: Double = 0, regionToActivate: Region = .screen) {
      self.minimumDistance = minimumDistance
      self.regionToActivate = regionToActivate
    }
  }

  /// Supplies the snap destination and observes the accepted drag's lifetime.
  public struct Handler {

    /// Returns the destination in points and may adjust velocity in points/second.
    ///
    /// The destination may change either axis, including an axis whose Boundary
    /// is nil. Directional cancellation restores the previous target without
    /// calling this handler. Scroll-view cancellation retains its end behavior.
    public var onEndDragging:
      @MainActor (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize) -> CGSize
    /// Called once, immediately before the first delivered offset update.
    public var onStartDragging: @MainActor () -> Void
    /// Called after both axes of an uninterrupted snap finish animating.
    fileprivate var onCompleteAnimation: @MainActor () -> Void

    public init(
      onStartDragging: @escaping @MainActor () -> Void = {},
      onEndDragging:
        @escaping @MainActor (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero },
      onCompleteAnimation: @escaping @MainActor () -> Void = {}
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
      self.onCompleteAnimation = onCompleteAnimation
    }
  }

  /// Describes the physical spring used to settle content at its snap target.
  public enum SpringParameter {
    case interpolation(mass: Double, stiffness: Double, damping: Double)

    /// The default spring used by interactive snap dragging.
    public static var hard: Self {
      .interpolation(mass: 1.0, stiffness: 200, damping: 20)
    }
  }

  /// Describes an axis's direct-drag limits and rubber-band extent in points.
  ///
  /// A nil Boundary disables direct manipulation of that axis. These limits
  /// do not constrain the destination returned by the end handler.
  public struct Boundary {
    /// The lower limit of direct displacement, in points.
    public let min: Double
    /// The upper limit of direct displacement, in points.
    public let max: Double
    /// Controls resistance outside the interval; nonpositive values prevent overshoot.
    public let bandLength: Double

    public init(min: Double, max: Double, bandLength: Double) {
      self.min = min
      self.max = max
      self.bandLength = bandLength
    }

    /// Enables an axis without restricting its displacement.
    public static var infinity: Self {
      .init(min: -Double.greatestFiniteMagnitude, max: Double.greatestFiniteMagnitude, bandLength: 0)
    }

    /// Applies this interval's resistance to a proposed displacement.
    func applying(to offset: CGFloat) -> CGFloat {
      if bandLength <= 0 {
        // RubberBanding 1.0 returns min for either out-of-range direction when
        // bandLength is zero. Preserve the nearest endpoint instead of jumping
        // from an overshoot above max to the opposite boundary.
        return CGFloat(Swift.min(Swift.max(Double(offset), min), max))
      }
      return CGFloat(rubberBand(value: Double(offset), min: min, max: max, bandLength: bandLength))
    }
  }

  @Binding private var currentOffset: CGSize
  @State private var presentingOffset: CGSize
  @State private var targetOffset: CGSize
  @State private var initialOffset: CGSize?
  @State private var lastGestureValue: GestureValue?
  @State private var contentSize: CGSize = .zero
  @State private var animationSession = AnimationSession()
  @State private var gestureControl = GestureControl()
  @Environment(\.layoutDirection) private var layoutDirection

  /// Enables horizontal direct manipulation, or disables it when nil.
  public let horizontal: Boundary?
  /// Enables vertical direct manipulation, or disables it when nil.
  public let vertical: Boundary?
  /// The spring used to settle the offset at its snap destination.
  public let springParameter: SpringParameter
  /// The UIKit recognizer policy used to admit and coordinate pans.
  public let gestureMode: GestureMode
  /// The permitted touch-down region and callback-delivery threshold.
  public let activation: Activation
  private let handler: Handler

  /// Creates a drag modifier with explicit enabled and disabled axes.
  ///
  /// Creating this modifier with nil for both axes leaves the binding intact
  /// and delivers no drag callbacks. Disabling axes during an active drag
  /// cancels it using the current mode's cancellation behavior.
  public init(
    gestureMode: GestureMode = .directional,
    offset: Binding<CGSize>,
    activation: Activation = .init(),
    horizontal: Boundary?,
    vertical: Boundary?,
    springParameter: SpringParameter = .hard,
    handler: Handler = .init()
  ) {
    self._currentOffset = offset
    self._presentingOffset = State(initialValue: offset.wrappedValue)
    self._targetOffset = State(initialValue: offset.wrappedValue)
    self.horizontal = horizontal
    self.vertical = vertical
    self.springParameter = springParameter
    self.gestureMode = gestureMode
    self.handler = handler
    self.activation = activation
  }

  public func body(content: Content) -> some View {
    let base = content.onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { size in
      contentSize = size
    }

    Group {
      switch gestureMode {
      case .directional:
        base.gesture(
          DirectionalDragGesture(
            control: gestureControl,
            axis: enabledAxes,
            activation: activation,
            contentSize: contentSize,
            layoutDirection: layoutDirection,
            coordinateSpaceInDragging: .named(_CoordinateSpaceTag.transition),
            onChange: onChanged,
            onEnd: { finishDrag($0, cancelled: false) },
            onCancel: { finishDrag($0, cancelled: true) }
          )
        )
      case .scrollViewInteroperable(let configuration):
        base.gesture(
          ScrollViewSnapDragGesture(
            control: gestureControl,
            axis: enabledAxes,
            activation: activation,
            contentSize: contentSize,
            layoutDirection: layoutDirection,
            configuration: configuration,
            coordinateSpaceInDragging: .named(_CoordinateSpaceTag.transition),
            onChange: onChanged,
            onEnd: { finishDrag($0, cancelled: false) },
            onCancel: { finishDrag($0, cancelled: true) }
          )
        )
      }
    }
    ._animatableOffset(x: currentOffset.width, presenting: $presentingOffset.width)
    ._animatableOffset(y: currentOffset.height, presenting: $presentingOffset.height)
    .coordinateSpace(name: _CoordinateSpaceTag.transition)
    .onChange(of: recognitionConfiguration) { previous, _ in
      // SwiftUI can defer updateUIGestureRecognizer until an active pan ends.
      // Cancel its owner now, then recover any replaced mode's outer session.
      gestureControl.cancelActiveGestures(reenable: !enabledAxes.isEmpty)
      if let value = lastGestureValue {
        finishDrag(value, cancelled: true, cancellationMode: previous.mode)
      }
    }
    .onAppear {
      gestureControl.resumeGestures(enabled: !enabledAxes.isEmpty)
    }
    .onDisappear {
      gestureControl.cancelActiveGestures(reenable: false)
      if let value = lastGestureValue {
        finishDrag(value, cancelled: true)
      }
      animationSession.invalidate()
    }
  }

  /// Contains only settings whose changes invalidate an active native pan.
  private struct RecognitionConfiguration: Equatable {
    let mode: GestureMode.Kind
    let axes: Axis.Set
    let activation: Activation
    let layoutDirection: LayoutDirection
    var ignoresScrollView: Bool = false
    var targetEdges: ScrollViewEdge = []
    var sticksToEdges: Bool = false
    var edgeActivationMode: Int = 0
  }

  private var recognitionConfiguration: RecognitionConfiguration {
    var configuration = RecognitionConfiguration(
      mode: gestureMode.kind,
      axes: enabledAxes,
      activation: activation,
      layoutDirection: layoutDirection
    )
    if case .scrollViewInteroperable(let scroll) = gestureMode {
      configuration.ignoresScrollView = scroll.ignoresScrollView
      configuration.targetEdges = scroll.targetEdges
      configuration.sticksToEdges = scroll.sticksToEdges
      switch scroll.edgeActivationMode {
      case .anytime: configuration.edgeActivationMode = 0
      case .onlyAtGestureStart: configuration.edgeActivationMode = 1
      @unknown default: configuration.edgeActivationMode = -1
      }
    }
    return configuration
  }

  /// Derives recognition axes from the same values used for offset updates.
  var enabledAxes: Axis.Set {
    var axes: Axis.Set = []
    if horizontal != nil { axes.insert(.horizontal) }
    if vertical != nil { axes.insert(.vertical) }
    return axes
  }

  private func onChanged(_ value: GestureValue) {
    guard !enabledAxes.isEmpty else { return }
    lastGestureValue = value

    if initialOffset == nil {
      animationSession.invalidate()
      initialOffset = presentingOffset
      handler.onStartDragging()
    }

    guard let baseOffset = initialOffset else { return }
    let offset = Self.draggedOffset(
      baseOffset: baseOffset,
      translation: value.translation,
      currentOffset: currentOffset,
      horizontal: horizontal,
      vertical: vertical
    )

    // A new interactive value replaces an older snap's presentation immediately.
    withAnimation(.interactiveSpring()) {
      currentOffset = offset
    }
  }

  private func finishDrag(
    _ value: GestureValue,
    cancelled: Bool,
    cancellationMode: GestureMode.Kind? = nil
  ) {
    guard initialOffset != nil else { return }
    // Consume before client code can re-enter through a configuration change.
    initialOffset = nil
    lastGestureValue = nil

    if cancelled {
      switch cancellationMode ?? gestureMode.kind {
      case .directional:
        animationSession.invalidate()
        withAnimation(spring(initialVelocity: 0)) {
          currentOffset = targetOffset
        }
        return
      case .scrollViewInteroperable:
        break
      }
    }
    snap(velocity: value.velocity)
  }

  /// Applies direct-drag limits while retaining existing disabled-axis values.
  static func draggedOffset(
    baseOffset: CGSize,
    translation: CGSize,
    currentOffset: CGSize,
    horizontal: Boundary?,
    vertical: Boundary?
  ) -> CGSize {
    var offset = currentOffset
    if let horizontal {
      offset.width = horizontal.applying(to: baseOffset.width + translation.width)
    }
    if let vertical {
      offset.height = vertical.applying(to: baseOffset.height + translation.height)
    }
    return offset
  }

  private func snap(velocity: CGVector) {
    var velocity = velocity
    let target = handler.onEndDragging(&velocity, currentOffset, contentSize)
    targetOffset = target
    let generation = animationSession.begin()
    let distance = CGSize(
      width: target.width - currentOffset.width,
      height: target.height - currentOffset.height
    )
    let animationX = spring(initialVelocity: Self.mappedInitialVelocity(velocity: velocity.dx, distance: distance.width))
    let animationY = spring(initialVelocity: Self.mappedInitialVelocity(velocity: velocity.dy, distance: distance.height))

    withAnimation(animationX) {
      currentOffset.width = target.width
    } completion: {
      if animationSession.completeAxis(for: generation) {
        handler.onCompleteAnimation()
      }
    }
    withAnimation(animationY) {
      currentOffset.height = target.height
    } completion: {
      if animationSession.completeAxis(for: generation) {
        handler.onCompleteAnimation()
      }
    }
  }

  private func spring(initialVelocity: CGFloat) -> Animation {
    switch springParameter {
    case .interpolation(let mass, let stiffness, let damping):
      return .interpolatingSpring(
        mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity
      )
    }
  }

  /// Converts points/second to spring-relative velocity, avoiding zero division.
  static func mappedInitialVelocity(velocity: CGFloat, distance: CGFloat) -> CGFloat {
    guard velocity.isFinite, distance.isFinite, abs(distance) >= 1 else { return 0 }
    let mapped = velocity / distance
    return mapped.isFinite ? mapped : 0
  }

  /// Rejects stale or duplicate completion events after a snap is interrupted.
  struct AnimationSession {
    private var generation = 0
    private var remainingAxes = 0

    mutating func begin() -> Int {
      generation += 1
      remainingAxes = 2
      return generation
    }

    mutating func invalidate() {
      generation += 1
      remainingAxes = 0
    }

    mutating func completeAxis(for generation: Int) -> Bool {
      guard generation == self.generation, remainingAxes > 0 else { return false }
      remainingAxes -= 1
      return remainingAxes == 0
    }
  }
}

/// Names the stationary coordinate space outside the translated content.
private enum _CoordinateSpaceTag: Hashable {
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
              gestureMode: .directional,
              offset: $offset,
              activation: .init(minimumDistance: 0),
              horizontal: .infinity,
              vertical: .infinity,
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
            gestureMode: .directional,
            offset: $offset,
            horizontal: .init(min: 0, max: .infinity, bandLength: 50),
            vertical: nil,
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
