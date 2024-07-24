import RubberBanding
import SwiftUI
import SwiftUISupportSizing
import SwiftUISupportGeometryEffect

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

    fileprivate var onCompleteAnimation: () -> Void
    
    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging: @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
      -> CGSize = { _, _, _ in .zero }
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
      self.onCompleteAnimation = {}
    }

    @available(iOS 17.0, *)
    public init(
      onStartDragging: @escaping () -> Void = {},
      onEndDragging: @escaping (_ velocity: inout CGVector, _ offset: CGSize, _ contentSize: CGSize)
        -> CGSize = { _, _, _ in .zero },
      onCompleteAnimation: @escaping () -> Void
    ) {
      self.onStartDragging = onStartDragging
      self.onEndDragging = onEndDragging
      self.onCompleteAnimation = onCompleteAnimation
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
  @Binding private var currentOffset: CGSize
  
  // value for animating
  @State private var presentingOffset: CGSize = .zero
  
  @State private var targetOffset: CGSize = .zero

  @GestureState private var initialOffset: CGSize?  
  @GestureState private var isTracking = false
  @GestureState private var pointInView: CGPoint = .zero
  
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
    offset: Binding<CGSize>,
    activation: Activation = .init(),
    axis: Axis.Set = [.horizontal, .vertical],
    horizontalBoundary: Boundary = .infinity,
    verticalBoundary: Boundary = .infinity,
    springParameter: SpringParameter = .hard,
    gestureMode: GestureMode = .normal,
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
  }
  
  public func body(content: Content) -> some View {
    
    let base = content
      .coordinateSpace(name: _CoordinateSpaceTag.pointInView)
      .measureSize($contentSize)
      .onChange(of: isTracking) { newValue in
        if isTracking == false, currentOffset != targetOffset {
          // For recovery of gesture unexpectedly canceled by the other gesture.
          // `onEnded` never get called in the case.
          self.onEnded(velocity: .zero)
        }
      }
      .overlay { 
        Text("\(presentingOffset.debugDescription)")
      }
    
    let addingGesture = dragGesture.simultaneously(with: gesture)
    
    if true, #available(iOS 18, *) {
      
      Group {
        switch gestureMode {
        case .normal:
          base
            .gesture(_gesture)
            .simultaneousGesture(gesture)
//            .gesture(addingGesture, including: .all)
        case .highPriority:
          base
            .gesture(_gesture)
            .simultaneousGesture(gesture)
//            .highPriorityGesture(addingGesture, including: .all)
        }
      }
      ._animatableOffset(x: currentOffset.width, presenting: $presentingOffset.width)
      ._animatableOffset(y: currentOffset.height, presenting: $presentingOffset.height)
      
      .coordinateSpace(name: _CoordinateSpaceTag.transition)
      .onChange(of: isTracking) { newValue in
        if newValue {
          handler.onStartDragging()
        }
      }
      
    } else {
      
      Group {
        switch gestureMode {
        case .normal:
          base
            .gesture(addingGesture, including: .all)
        case .highPriority:
          base
            .highPriorityGesture(addingGesture, including: .all)
        }
      }
      ._animatableOffset(x: currentOffset.width, presenting: $presentingOffset.width)
      ._animatableOffset(y: currentOffset.height, presenting: $presentingOffset.height)
      
      .coordinateSpace(name: _CoordinateSpaceTag.transition)
      .onChange(of: isTracking) { newValue in
        if newValue {
          handler.onStartDragging()
        }
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
  private var _gesture: some UIGestureRecognizerRepresentable {
          
    let baseOffset = presentingOffset
    
    return CustomGesture(
      coordinateSpaceInDragging: .named(_CoordinateSpaceTag.transition),
      onChange: { value in 
      
//      if self.isActive || isInActivation(startLocation: value.startLocation) {
//        
//        self.isActive = true
                                        
        let proposedOffset = CGSize(
          width: baseOffset.width + value.translation.width,
          height: baseOffset.height + value.translation.height
        )  
        
        // TODO: stop the current animation when dragging restarted.
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
//      }
      }, onEnd: { value in 
        onEnded(
          velocity: .init(
            dx: value.velocity.width,
            dy: value.velocity.height
          )
        )
      })
  }
  
  private var dragGesture: some Gesture {
    
    DragGesture(
      minimumDistance: activation.minimumDistance,
      coordinateSpace: .named(_CoordinateSpaceTag.transition)
    )        
    .updating($initialOffset, body: { _, state, _ in 
      if state == nil {
        state = presentingOffset
      }
    })
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
        
        let proposedOffset = CGSize(
          width: baseOffset.width + value.translation.width,
          height: baseOffset.height + value.translation.height
        )    
        
        // TODO: stop the current animation when dragging restarted.
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
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 1, damping: 1, initialVelocity: 0)) {
          offset.width += 10
        }
      }
      
      Circle()
        .fill(Color.yellow)
        .frame(width: 100, height: 100)
        .modifier(
          SnapDraggingModifier(
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
