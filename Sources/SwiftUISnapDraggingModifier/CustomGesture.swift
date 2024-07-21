import SwiftUI

@available(iOS 18, *)
struct CustomGesture: UIGestureRecognizerRepresentable {  
  
  struct Value: Equatable {
    let location: CGPoint
    let translation: CGSize
    let velocity: CGSize    
  }
  
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    
    @objc
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      
      guard let _gestureRecognizer = gestureRecognizer as? ScrollViewDragGestureRecognizer else {
        assertionFailure("\(gestureRecognizer)")
        return false
      }
      
      guard !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer) else {
        return false
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
  private let coordinateSpaceInView: CoordinateSpaceProtocol
  private let _onChange: (Value) -> Void
  private let _onEnd: (Value) -> Void
  
  init(
    coordinateSpaceInDragging: CoordinateSpaceProtocol,
    coordinateSpaceInView: CoordinateSpaceProtocol,
    onChange: @escaping (Value) -> Void,
    onEnd: @escaping (Value) -> Void
  ) {    
    self.coordinateSpaceInDragging = coordinateSpaceInDragging
    self.coordinateSpaceInView = coordinateSpaceInView
    self._onChange = onChange
    self._onEnd = onEnd
  }
  
  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    return .init()
  }

  func makeUIGestureRecognizer(context: Context) -> ScrollViewDragGestureRecognizer {  
    let gesture = ScrollViewDragGestureRecognizer()
    gesture.delegate = context.coordinator
    return gesture
  }
  
  func handleUIGestureRecognizerAction(_ recognizer: ScrollViewDragGestureRecognizer, context: Context) {
    
    let location = context.converter.location(in: coordinateSpaceInDragging)
    let pointInView = context.converter.location(in: coordinateSpaceInView)
    
    let resolvedTranslation = CGSize(
      width: (location.x - pointInView.x),
      height: (location.y - pointInView.y)
    )
    
    print(resolvedTranslation)
    
    let value = Value(
      location: context.converter.location(in: coordinateSpaceInDragging),
      translation: resolvedTranslation,
      velocity: { .init(width: $0.x, height: $0.y) }(context.converter.velocity(in: coordinateSpaceInDragging) ?? .zero)
    )
    
    switch recognizer.state {      
    case .possible:
      break
    case .began, .changed:
      _onChange(value)
    case .ended:
      _onEnd(value)
    case .cancelled:
      _onEnd(value)
    case .failed:
      _onEnd(value)
    @unknown default:
      break
    }
      
  }
  
}

final class ScrollViewDragGestureRecognizer: UIPanGestureRecognizer {
    
  weak var trackingScrollView: UIScrollView?
  
  init() {
    super.init(target: nil, action: nil)
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
        
        func isHorizontal(scrollView: UIScrollView) -> Bool {
          
          let contentInset: UIEdgeInsets
          
          if #available(iOS 11.0, *) {
            contentInset = scrollView.adjustedContentInset
          } else {
            contentInset = scrollView.contentInset
          }
          
          return (scrollView.bounds.width - (contentInset.right + contentInset.left) < scrollView.contentSize.width)
        }
        
        func isScrollable(scrollView: UIScrollView) -> Bool {
          
          let contentInset: UIEdgeInsets
          
          if #available(iOS 11.0, *) {
            contentInset = scrollView.adjustedContentInset
          } else {
            contentInset = scrollView.contentInset
          }
          
          return (scrollView.bounds.width - (contentInset.right + contentInset.left) <= scrollView.contentSize.width) || (scrollView.bounds.height - (contentInset.top + contentInset.bottom) <= scrollView.contentSize.height)
        }
        
        return isScrollable(scrollView: scrollView) && !isHorizontal(scrollView: scrollView)
      }
    
    return (scrollView as? UIScrollView)
  }
  
}

@available(iOS 18, *)
#Preview("Scroll") {
  @Previewable @State var offset: CGSize = .zero
  
  ZStack {
        
    ScrollView {
      VStack {
        ForEach(0..<20) { index in
          HStack {
            Spacer()
            Text("Item \(index)")
            Spacer()
          }
        }
      }
    }
    .frame(width: 200, height: 200)
    .background(Color.green.secondary)
    .padding()
    .background(Color.green.tertiary)
    .modifier(SnapDraggingModifier(offset: $offset))
        
  }
}
