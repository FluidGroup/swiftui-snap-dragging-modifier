import UIKit

final class ScrollController {
  
  struct LockingDirection: OptionSet {
    let rawValue: Int
    
    static let vertical = LockingDirection(rawValue: 1 << 0)
    static let horizontal = LockingDirection(rawValue: 1 << 1)
  }
  
  private var scrollObserver: NSKeyValueObservation!
  private(set) var lockingDirection: LockingDirection = []
  private var previousValue: CGPoint?
  let scrollView: UIScrollView
  
  init(scrollView: UIScrollView) {
    self.scrollView = scrollView
    scrollObserver = scrollView.observe(\.contentOffset, options: .old) {
      [weak self, weak _scrollView = scrollView] scrollView, change in
      
      guard let scrollView = _scrollView else { return }
      guard let self = self else { return }
      self.handleScrollViewEvent(scrollView: scrollView, change: change)
    }
  }
  
  deinit {
    endTracking()
  }
  
  func lockScrolling(direction: LockingDirection) {
    lockingDirection.insert(direction)
  }
  
  func unlockScrolling(direction: LockingDirection) {
    lockingDirection.remove(direction)
  }
  
  func setShowsVerticalScrollIndicator(_ flag: Bool) {
    scrollView.showsVerticalScrollIndicator = flag
  }
  
  func endTracking() {
    unlockScrolling(direction: [.vertical, .horizontal])
    scrollObserver.invalidate()
  }
  
  func resetContentOffsetY() {
    let contentInset = scrollView.adjustedContentInset
    if scrollView.contentOffset.y < -contentInset.top {
      setContentOffset(scrollView.contentOffsetToResetY)
    }
  }
  
  func setContentOffset(_ offset: CGPoint) {
    let previous = lockingDirection
    lockingDirection = []
    defer {
      lockingDirection = previous
    }
    scrollView.contentOffset = offset
  }
  
  private func handleScrollViewEvent(
    scrollView: UIScrollView,
    change: NSKeyValueObservedChange<CGPoint>
  ) {
    
    // For debugging
    
    guard let oldValue = change.oldValue else { return }
    
    guard lockingDirection.isEmpty == false else {
      return
    }
    
    //    guard scrollView.contentOffset != oldValue else { return }
    
    guard oldValue != previousValue else { return }
    
    previousValue = scrollView.contentOffset
    
    var fixedOffset = scrollView.contentOffset
    
    if lockingDirection.contains(.vertical) {
      fixedOffset.y = oldValue.y
    }
    
    if lockingDirection.contains(.horizontal) {
      fixedOffset.x = oldValue.x
    }
    
    scrollView.setContentOffset(fixedOffset, animated: false)
  }
  
}
