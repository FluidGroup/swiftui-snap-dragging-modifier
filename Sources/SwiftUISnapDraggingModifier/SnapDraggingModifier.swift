import SwiftUIGestureVelocity
import SwiftUI
import SwiftUISupport

@available(*, deprecated, renamed: "SnapDraggingModifier")
public typealias VelocityDraggingModifier = SnapDraggingModifier

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

    public var onStartDragging: () -> Void

    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging: @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero }
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
    }
  }

  public enum GestureMode {
    case normal
    case highPriority
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
  @State private var currentOffset: CGSize = .zero
  @State private var targetOffset: CGSize = .zero

  /// pt/s
  @GestureVelocity private var velocity: CGVector
  @GestureState private var isTracking = false

  @State private var isActive = false
  @State private var contentSize: CGSize = .zero

  @Environment(\.layoutDirection) var layoutDirection

  public let axis: Axis.Set
  public let springParameter: SpringParameter
  public let gestureMode: GestureMode
  public let activation: Activation

  private let horizontalBoundary: Boundary
  private let verticalBoundary: Boundary
  private let handler: Handler

  public init(
    activation: Activation = .init(),
    axis: Axis.Set = [.horizontal, .vertical],
    horizontalBoundary: Boundary = .infinity,
    verticalBoundary: Boundary = .infinity,
    springParameter: SpringParameter = .hard,
    gestureMode: GestureMode = .normal,
    handler: Handler = .init()
  ) {
    self.axis = axis
    self.springParameter = springParameter
    self.horizontalBoundary = horizontalBoundary
    self.verticalBoundary = verticalBoundary
    self.gestureMode = gestureMode
    self.handler = handler
    self.activation = activation
  }

  public func body(content: Content) -> some View {

    let base = content
      .measureSize($contentSize)
      .animatableOffset(x: currentOffset.width, y: currentOffset.height)
      .onChange(of: isTracking) { newValue in
        if isTracking == false, currentOffset != targetOffset {
          // For recovery of gesture unexpectedly canceled by the other gesture.
          // `onEnded` never get called in the case.
          self.onEnded(velocity: .zero)
        }
      }

    Group {
      switch gestureMode {
      case .normal:
        base.gesture(gesture, including: .all)
      case .highPriority:
        base.highPriorityGesture(gesture, including: .all)
      }
    }
    .onChange(of: isTracking) { newValue in
      if newValue {
        handler.onStartDragging()
      }
    }

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
          if CGRect(origin: .zero, size: .init(width: space, height: contentSize.height)).contains(startLocation) {
            return true
          }
        case .rightToLeft:
          if CGRect(origin: .init(x: contentSize.width - space, y: 0), size: .init(width: space, height: contentSize.height)).contains(startLocation) {
            return true
          }
        @unknown default:
          break
        }
      }

      if edge.contains(.trailing) {
        switch layoutDirection {
        case .leftToRight:
          if CGRect(origin: .init(x: contentSize.width - space, y: 0), size: .init(width: space, height: contentSize.height)).contains(startLocation) {
            return true
          }
        case .rightToLeft:
          if CGRect(origin: .zero, size: .init(width: 20, height: CGFloat.greatestFiniteMagnitude)).contains(startLocation) {
            return true
          }
        @unknown default:
          return false
        }
      }

      if edge.contains(.top) {
        if CGRect(origin: .zero, size: .init(width: contentSize.width, height: space)).contains(startLocation) {
          return true
        }
      }

      if edge.contains(.bottom) {
        if CGRect(origin: .init(x: 0, y: contentSize.height - space), size: .init(width: contentSize.width, height: space)).contains(startLocation) {
          return true
        }
      }

      return false
    }

  }

  private var gesture: some Gesture {
    DragGesture(
      minimumDistance: activation.minimumDistance,
      coordinateSpace: .local
    )
    .updating($isTracking, body: { _, state, _ in
      state = true
    })
    .onChanged({ value in

      if self.isActive || isInActivation(startLocation: value.startLocation) {

        self.isActive = true

        // TODO: including minimumDistance
        let resolvedTranslation = value.translation

      // TODO: stop the current animation when dragging restarted.
        withAnimation(.interactiveSpring()) {
          if axis.contains(.horizontal) {
            currentOffset.width = RubberBandingModifier.rubberBand(
              value: resolvedTranslation.width,
              min: horizontalBoundary.min,
              max: horizontalBoundary.max,
              bandLength: horizontalBoundary.bandLength
            )
          }
          if axis.contains(.vertical) {
            currentOffset.height = RubberBandingModifier.rubberBand(
              value: resolvedTranslation.height,
              min: verticalBoundary.min,
              max: verticalBoundary.max,
              bandLength: verticalBoundary.bandLength
            )
          }
        }
      }
    })
    .onEnded({ _ in

      if isActive {
        self.onEnded(velocity: velocity)
      } else {
        assert(currentOffset == targetOffset)
      }

      self.isActive = false
    })
    .updatingVelocity($velocity)
  }

  private func onEnded(velocity: CGVector) {
    var usingVelocity = velocity

    let targetOffset: CGSize = handler.onEndDragging(
      &usingVelocity,
      self.currentOffset,
      self.contentSize
    )

    self.targetOffset = targetOffset

    let velocity = usingVelocity

    let distance = CGSize(
      width: targetOffset.width - currentOffset.width,
      height: targetOffset.height - currentOffset.height
    )

    let mappedVelocity = CGVector(
      dx: velocity.dx / distance.width,
      dy: velocity.dy / distance.height
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

#if DEBUG
struct VelocityDraggingModifier_Previews: PreviewProvider {
  static var previews: some View {

    BookRubberBanding()

    Group {

      RoundedRectangle(cornerRadius: 16, style: .circular)
        .frame(width: 120, height: 50)
        .modifier(
          SnapDraggingModifier(
            axis: [.vertical],
            verticalBoundary: .init(min: -10, max: 10, bandLength: 50)
          )
        )

    }
  }

  struct BookRubberBanding: View {

    @State var isSliding: Bool = false

    var body: some View {

      ZStack {

        // make notification bar
        RoundedRectangle(cornerRadius: 16, style: .circular)
          .fill(isSliding ? .red : .blue)
          .modifier(AmbientShadowModifier(blurRadius: 18))
          .frame(width: 120, height: 50)
          .scaleEffect(x: isSliding ? 1 : 1.2, y: isSliding ? 1 : 1.2)
          .modifier(
            RubberBandingModifier(onSliding: { isSliding in
              print(isSliding)
              withAnimation(.spring()) {
                self.isSliding = isSliding
              }
            })
          )
      }
    }
  }
}
#endif
