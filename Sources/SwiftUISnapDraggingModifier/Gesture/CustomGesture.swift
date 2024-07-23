import SwiftUI

@available(iOS 18, *)
struct CustomGesture: UIGestureRecognizerRepresentable {

  struct Value: Equatable {

    let beganPoint: CGPoint
    let translation: CGSize
    let location: CGPoint
    var velocity: CGSize

    consuming func fixingLocation(_ offset: CGPoint) -> Value {

      let subDistance = CGSize(width: offset.x - beganPoint.x, height: offset.y - beganPoint.y)

      return Value(
        beganPoint: beganPoint,
        translation: translation,
        location: .init(x: location.x - subDistance.width, y: location.y - subDistance.height),
        velocity: velocity
      )
    }
  }

  struct Configuration {
    var ignoresScrollView: Bool
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {

    struct Tracking {
      var isDragging: Bool = false
      var beganPoint: CGPoint = .zero
      var currentScrollController: ScrollController?
      var trackingLocation: CGPoint = .zero
    }

    var tracking: Tracking = .init()
    private let configuration: Configuration

    init(configuration: Configuration) {
      self.configuration = configuration
    }

    func purgeTrakingState() {
      tracking = .init()
    }

    @objc
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {

      guard let _gestureRecognizer = gestureRecognizer as? ScrollViewDragGestureRecognizer else {
        assertionFailure("\(gestureRecognizer)")
        return false
      }

      guard !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer) else {
        return false
      }

      if configuration.ignoresScrollView {
        if otherGestureRecognizer.view is UIScrollView {
          return false
        }
      }
      
      //      switch configuration.scrollViewOption.scrollViewDetection {
      //      case .noTracking:
      //        return false
      //      case .automatic:
      let result = _gestureRecognizer.trackingScrollView == otherGestureRecognizer.view

      return result
      //      case .specific(let scrollView):
      //        return otherGestureRecognizer.view == scrollView
      //      }

    }

  }

  private let coordinateSpaceInDragging: CoordinateSpaceProtocol
  private let _onChange: (Value) -> Void
  private let _onEnd: (Value) -> Void
  private let configuration: Configuration

  init(
    configuration: Configuration = .init(ignoresScrollView: false),
    coordinateSpaceInDragging: CoordinateSpaceProtocol,
    onChange: @escaping (Value) -> Void,
    onEnd: @escaping (Value) -> Void
  ) {
    self.configuration = configuration
    self.coordinateSpaceInDragging = coordinateSpaceInDragging
    self._onChange = onChange
    self._onEnd = onEnd
  }

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    return .init(configuration: configuration)
  }

  func makeUIGestureRecognizer(context: Context) -> ScrollViewDragGestureRecognizer {
    let gesture = ScrollViewDragGestureRecognizer()
    gesture.delegate = context.coordinator
    return gesture
  }

  func handleUIGestureRecognizerAction(
    _ recognizer: ScrollViewDragGestureRecognizer,
    context: Context
  ) {

    switch recognizer.state {
    case .possible:
      break
    case .began:

      context.coordinator.tracking.beganPoint = context.converter.location(
        in: coordinateSpaceInDragging
      )
      
      fallthrough
    case .changed:

      let value = Value(
        beganPoint: context.coordinator.tracking.beganPoint,
        translation: { .init(width: $0.x, height: $0.y) }(recognizer.translation(in: nil)),
        location: context.converter.location(in: coordinateSpaceInDragging),
        velocity: { .init(width: $0.x, height: $0.y) }(
          context.converter.velocity(in: coordinateSpaceInDragging) ?? .zero
        )
      )

      if let scrollView = recognizer.trackingScrollView {

        let scrollController = ScrollController(scrollView: scrollView)
        context.coordinator.tracking.currentScrollController = scrollController

        let scrollableEdges = scrollView.scrollableEdges

        let panDirection = recognizer.panDirection

        if panDirection.contains(.up) {

          if scrollableEdges.contains(.bottom) == false {
            scrollController.lockScrolling(direction: .vertical)
            if context.coordinator.tracking.trackingLocation == .zero {
              context.coordinator.tracking.trackingLocation = value.location
            }
            context.coordinator.tracking.isDragging = true
            _onChange(value.fixingLocation(context.coordinator.tracking.trackingLocation))
          } else {
            scrollController.unlockScrolling(direction: .vertical)
            context.coordinator.tracking.isDragging = false
          }

        }

        if panDirection.contains(.down) {
          if scrollableEdges.contains(.top) == false {
            scrollController.lockScrolling(direction: .vertical)
            if context.coordinator.tracking.trackingLocation == .zero {
              context.coordinator.tracking.trackingLocation = value.location
            }
            context.coordinator.tracking.isDragging = true
            _onChange(value.fixingLocation(context.coordinator.tracking.trackingLocation))
          } else {
            scrollController.unlockScrolling(direction: .vertical)
            context.coordinator.tracking.isDragging = false
          }
        }

        if panDirection.contains(.left) {
          
          if scrollableEdges.contains(.right) == false {
            scrollController.lockScrolling(direction: .horizontal)
            if context.coordinator.tracking.trackingLocation == .zero {
              context.coordinator.tracking.trackingLocation = value.location
            }
            context.coordinator.tracking.isDragging = true
            _onChange(value.fixingLocation(context.coordinator.tracking.trackingLocation))
          } else {
            scrollController.unlockScrolling(direction: .horizontal)
            context.coordinator.tracking.isDragging = false

          }
          
        }
        
        if panDirection.contains(.right) {
          
          if scrollableEdges.contains(.left) == false {
            scrollController.lockScrolling(direction: .horizontal)
            if context.coordinator.tracking.trackingLocation == .zero {
              context.coordinator.tracking.trackingLocation = value.location
            }
            context.coordinator.tracking.isDragging = true
            _onChange(value.fixingLocation(context.coordinator.tracking.trackingLocation))
          } else {
            scrollController.unlockScrolling(direction: .horizontal)
            context.coordinator.tracking.isDragging = false
 
          }
          
        }

      } else {
        context.coordinator.tracking.isDragging = true
        _onChange(value)
      }

    case .ended, .cancelled, .failed:

      var value = Value(
        beganPoint: context.coordinator.tracking.beganPoint,
        translation: { .init(width: $0.x, height: $0.y) }(recognizer.translation(in: nil)),
        location: context.converter.location(in: coordinateSpaceInDragging),
        velocity: { .init(width: $0.x, height: $0.y) }(
          context.converter.velocity(in: coordinateSpaceInDragging) ?? .zero
        )
      )

      if context.coordinator.tracking.isDragging == false {
        value.velocity = .zero
      }

      _onEnd(value.fixingLocation(context.coordinator.tracking.trackingLocation))

      context.coordinator.purgeTrakingState()

    @unknown default:
      break
    }

  }

}

final class ScrollViewDragGestureRecognizer: UIPanGestureRecognizer {
  
  struct PanDirection: OptionSet {
    let rawValue: Int
    
    static let up = PanDirection(rawValue: 1 << 0)
    static let down = PanDirection(rawValue: 1 << 1)
    static let left = PanDirection(rawValue: 1 << 2)
    static let right = PanDirection(rawValue: 1 << 3)
    
  }

  weak var trackingScrollView: UIScrollView?

  init() {
    super.init(target: nil, action: nil)
  }

  var panDirection: PanDirection {

    let translation = self.translation(in: view)
    var direction: PanDirection = []

    if translation.y > 0 {
      direction.insert(.down)
    } else if translation.y < 0 {
      direction.insert(.up)
    }

    if translation.x > 0 {
      direction.insert(.right)
    } else if translation.x < 0 {
      direction.insert(.left)
    }

    return direction
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    trackingScrollView = event.findVerticalScrollView()
    super.touchesBegan(touches, with: event)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {

    super.touchesMoved(touches, with: event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
  }

}

extension UIEvent {

  fileprivate func findVerticalScrollView() -> UIScrollView? {

    guard
      let firstTouch = allTouches?.first,
      let targetView = firstTouch.view
    else { return nil }

    let scrollView = Array(sequence(first: targetView, next: { $0.next }))
      .last {
        guard let scrollView = $0 as? UIScrollView else {
          return false
        }

        //        func isHorizontal(scrollView: UIScrollView) -> Bool {
        //
        //          let contentInset: UIEdgeInsets = scrollView.adjustedContentInset
        //
        //          return (scrollView.bounds.width - (contentInset.right + contentInset.left) < scrollView.contentSize.width)
        //        }

        func isScrollable(scrollView: UIScrollView) -> Bool {

          let contentInset: UIEdgeInsets = scrollView.adjustedContentInset

          return
            (scrollView.bounds.width - (contentInset.right + contentInset.left)
            <= scrollView.contentSize.width)
            || (scrollView.bounds.height - (contentInset.top + contentInset.bottom)
              <= scrollView.contentSize.height)
        }

        return isScrollable(scrollView: scrollView)  // && !isHorizontal(scrollView: scrollView)
      }

    return (scrollView as? UIScrollView)
  }

}


@available(iOS 18, *)
#Preview("Scroll") {
  @Previewable @State var offset: CGSize = .zero

  ZStack {

    VStack {

      ScrollView([.horizontal, .vertical]) {
        Grid {
          ForEach(0..<8) { _ in
            GridRow {
              ForEach(0..<8) { _ in Color.teal.frame(width: 30, height: 30) }
            }
          }
        }
        .padding()
        .background(Color.red)
      }

//      ScrollView {
//        VStack {
//          ForEach(0..<20) { index in
//            HStack {
//              Spacer()
//              Button("Button") {
//
//              }
//              .tint(.primary)
//              Spacer()
//            }
//            .padding(2)
//          }
//        }
//      }
//      .contentMargins(10)
//      .background(Color.yellow.tertiary)
//
//      ScrollView(.horizontal) {
//        HStack {
//          ForEach(0..<5) { index in
//            HStack {
//              Spacer()
//              Button("Button") {
//
//              }
//              .tint(.primary)
//              Spacer()
//            }
//            .padding(4)
//            .padding(.vertical, 10)
//          }
//        }
//      }
//      .background(Color.yellow.tertiary)
    }
    .frame(width: 200, height: 200)
    .background(Color.green.secondary)
    .padding()
    .background(Color.green.tertiary)
    .modifier(SnapDraggingModifier(offset: $offset))
    .background(Color.purple.tertiary)

  }
}
