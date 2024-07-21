import UIKit

extension UIScrollView {
  
  struct ScrollableEdge: OptionSet, CustomStringConvertible {
    
    let rawValue: Int
    
    static let top = ScrollableEdge(rawValue: 1 << 0)
    static let bottom = ScrollableEdge(rawValue: 1 << 1)
    static let left = ScrollableEdge(rawValue: 1 << 2)
    static let right = ScrollableEdge(rawValue: 1 << 3)
    
    var description: String {
      var result: [String] = []
      if contains(.top) {
        result.append("top")
      }
      if contains(.bottom) {
        result.append("bottom")
      }
      if contains(.left) {
        result.append("left")
      }
      if contains(.right) {
        result.append("right")
      }
      return result.joined(separator: ", ")
    }
  }
  
  var scrollableEdges: ScrollableEdge {
    
    var edges: ScrollableEdge = []
    
    let contentInset: UIEdgeInsets = adjustedContentInset
    
    // Top
    if contentOffset.y > -contentInset.top {
      edges.insert(.top)
    }
    
    // Left
    if contentOffset.x > -contentInset.left {
      edges.insert(.left)
    }
    
    // bottom
    if contentOffset.y + bounds.height < (contentSize.height + contentInset.bottom) {
      edges.insert(.bottom)
    }
    
    // right
    
    if contentOffset.x + bounds.width < (contentSize.width + contentInset.right) {
      edges.insert(.right)
    }
    
    return edges
  }
  
  //  func isScrollingToTop(includiesRubberBanding: Bool) -> Bool {
  //    if includiesRubberBanding {
  //      return contentOffset.y <= -adjustedContentInset.top
  //    } else {
  //      return contentOffset.y == -adjustedContentInset.top
  //    }
  //  }
  
  //  func isScrollingDown() -> Bool {
  //    return contentOffset.y > -adjustedContentInset.top
  //  }
  
  var contentOffsetToResetY: CGPoint {
    let contentInset = self.adjustedContentInset
    var contentOffset = contentOffset
    contentOffset.y = -contentInset.top
    return contentOffset
  }
  
}
