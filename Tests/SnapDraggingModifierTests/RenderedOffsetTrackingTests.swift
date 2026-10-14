import SwiftUI
import XCTest

@testable import SwiftUISnapDraggingModifier

/// Reproduces render updates that do not call `animatableData` setters.
@MainActor
final class RenderedOffsetTrackingTests: XCTestCase {

  func testEffectEvaluationReportsDrawingOffsetBeforeReleaseWithoutAnimatableSetter() {
    let tracker = RenderedOffsetTracker()
    var notifiedOffset: CGSize?
    let effect = XTranslationEffect(
      offset: 79.01,
      presenting: .constant(0),
      renderingTracker: tracker,
      onPresentingOffsetChange: { offset in
        notifiedOffset = offset
        XCTAssertEqual(tracker.offset, offset, "Release must be able to read the evaluated position immediately.")
      }
    )

    let projection = effect.effectValue(size: .init(width: 180, height: 40))
    XCTAssertEqual(projection.m31, 79.01, accuracy: 0.0001)
    XCTAssertEqual(tracker.offset, CGSize(width: 79.01, height: 0))
    XCTAssertEqual(notifiedOffset, tracker.offset)

    var velocity = CGVector(dx: 1_871.77, dy: 0)
    let handler = SnapDraggingModifier.Handler(onEndDraggingWithPresentation: { velocity, model, drawing, _ in
      XCTAssertEqual(model, CGSize(width: 85, height: 0))
      XCTAssertEqual(drawing, CGSize(width: 79.01, height: 0))
      XCTAssertEqual(velocity.dx, 1_871.77)
      velocity = .zero
      return drawing
    })
    let target = handler.targetOffset(
      velocity: &velocity, offset: .init(width: 85, height: 0),
      presentingOffset: tracker.offset, contentSize: .init(width: 180, height: 40)
    )
    XCTAssertEqual(target, tracker.offset)
    XCTAssertEqual(velocity, .zero)
  }

  func testNonanimatedResetReplacesThePreviousDrawingOffset() {
    let tracker = RenderedOffsetTracker()
    let dragged = XTranslationEffect(offset: 79, presenting: .constant(0), renderingTracker: tracker)
    _ = dragged.effectValue(size: .init(width: 180, height: 40))
    XCTAssertEqual(tracker.offset.width, 79)

    let reset = XTranslationEffect(offset: 0, presenting: .constant(79), renderingTracker: tracker)
    _ = reset.effectValue(size: .init(width: 180, height: 40))
    XCTAssertEqual(tracker.offset, .zero)
  }

  func testBothAxisEffectsPreserveEachOthersEvaluatedValues() {
    let tracker = RenderedOffsetTracker()
    let horizontal = XTranslationEffect(offset: 35, presenting: .constant(0), renderingTracker: tracker)
    let vertical = YTranslationEffect(offset: -8, presenting: .constant(0), renderingTracker: tracker)
    _ = horizontal.effectValue(size: .init(width: 180, height: 40))
    let projection = vertical.effectValue(size: .init(width: 180, height: 40))
    XCTAssertEqual(projection.m32, -8)
    XCTAssertEqual(tracker.offset, CGSize(width: 35, height: -8))
  }
}
