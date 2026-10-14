import Foundation

/// Records the geometry effect's evaluated drawing values without SwiftUI state writes.
///
/// SwiftUI can evaluate an effect without calling its `animatableData` setter,
/// including interactive and nonanimated changes. Reference storage lets the
/// release handler read the last evaluated drawing position synchronously.
final class RenderedOffsetTracker {
  private let lock = NSLock()
  private var recordedOffset: CGSize = .zero

  var offset: CGSize {
    lock.lock()
    defer { lock.unlock() }
    return recordedOffset
  }

  func record(horizontal value: CGFloat, onChange: @escaping (CGSize) -> Void) {
    record(width: value, height: nil, onChange: onChange)
  }

  func record(vertical value: CGFloat, onChange: @escaping (CGSize) -> Void) {
    record(width: nil, height: value, onChange: onChange)
  }

  private func record(width: CGFloat?, height: CGFloat?, onChange: @escaping (CGSize) -> Void) {
    lock.lock()
    var next = recordedOffset
    if let width { next.width = width }
    if let height { next.height = height }
    let changed = next != recordedOffset
    recordedOffset = next
    lock.unlock()

    guard changed else { return }
    // Invoke outside the lock so consumers can read the updated offset. UIKit
    // rendering metadata belongs on main; background effect evaluation is safe
    // to record immediately, with its notification forwarded onto main.
    if Thread.isMainThread {
      onChange(next)
    } else {
      DispatchQueue.main.async { onChange(next) }
    }
  }
}
