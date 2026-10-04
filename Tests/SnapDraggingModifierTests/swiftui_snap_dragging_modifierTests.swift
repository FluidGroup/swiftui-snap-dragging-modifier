import SwiftUI
import UIKit
import XCTest

@testable import SwiftUISnapDraggingModifier

/// Verifies drag admission, optional-axis updates, and gesture/snap lifetimes.
@MainActor
final class SwiftUISnapDraggingModifierTests: XCTestCase {

  func testDisabledAxisDoesNotBlockTheInnerScrollViewsPan() {
    let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    scrollView.contentSize = CGSize(width: 200, height: 800)

    XCTAssertTrue(ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(axis: .horizontal, scrollView: scrollView))
    XCTAssertFalse(ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(axis: .vertical, scrollView: scrollView))
    XCTAssertFalse(ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(axis: [.horizontal, .vertical], scrollView: scrollView))

    // A scroll view that can also move on the enabled axis must retain the
    // native recognizer's ownership policy instead of this limited supplement.
    scrollView.contentSize.width = 800
    XCTAssertFalse(ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(axis: .horizontal, scrollView: scrollView))

    scrollView.contentSize.width = 200
    scrollView.isScrollEnabled = false
    XCTAssertFalse(ScrollViewSnapDragGesture.allowsDisabledAxisScrolling(axis: .horizontal, scrollView: scrollView))
  }

  func testOptionalBoundariesEnableDraggingAndPreserveDisabledAxisValues() {
    let baseOffset = CGSize(width: 10, height: 20)
    let translation = CGSize(width: 100_000, height: -1_000_000)
    // A binding owner can change a disabled axis after the drag starts.
    let currentOffset = CGSize(width: 90, height: 70)
    let cases: [(
      horizontal: SnapDraggingModifier.Boundary?,
      vertical: SnapDraggingModifier.Boundary?,
      axes: Axis.Set,
      expected: CGSize
    )] = [
      (nil, nil, [], currentOffset),
      (.infinity, nil, .horizontal, .init(width: 100_010, height: 70)),
      (nil, .infinity, .vertical, .init(width: 90, height: -999_980)),
      (.infinity, .infinity, [.horizontal, .vertical], .init(width: 100_010, height: -999_980)),
    ]

    for testCase in cases {
      let modifier = SnapDraggingModifier(
        offset: .constant(currentOffset),
        horizontal: testCase.horizontal,
        vertical: testCase.vertical
      )

      XCTAssertEqual(modifier.enabledAxes, testCase.axes)
      guard case .directional = modifier.gestureMode else {
        return XCTFail("The default gesture mode must use directional recognition.")
      }
      XCTAssertEqual(
        SnapDraggingModifier.draggedOffset(
          baseOffset: baseOffset,
          translation: translation,
          currentOffset: currentOffset,
          horizontal: modifier.horizontal,
          vertical: modifier.vertical
        ),
        testCase.expected
      )
    }
  }

  func testFiniteBoundariesApplyResistanceOnlyOutsideTheirRange() {
    let boundary = SnapDraggingModifier.Boundary(min: -10, max: 10, bandLength: 50)
    let inside = SnapDraggingModifier.draggedOffset(
      baseOffset: .zero,
      translation: .init(width: 5, height: -5),
      currentOffset: .zero,
      horizontal: boundary,
      vertical: boundary
    )
    XCTAssertEqual(inside, .init(width: 5, height: -5))

    let outside = SnapDraggingModifier.draggedOffset(
      baseOffset: .zero,
      translation: .init(width: 110, height: -110),
      currentOffset: .zero,
      horizontal: boundary,
      vertical: boundary
    )
    XCTAssertGreaterThan(outside.width, 10)
    XCTAssertLessThan(outside.width, 60)
    XCTAssertLessThan(outside.height, -10)
    XCTAssertGreaterThan(outside.height, -60)

    let clamped = SnapDraggingModifier.draggedOffset(
      baseOffset: .zero,
      translation: .init(width: 110, height: -110),
      currentOffset: .zero,
      horizontal: .init(min: -10, max: 10, bandLength: 0),
      vertical: .init(min: -10, max: 10, bandLength: 0)
    )
    XCTAssertEqual(clamped, .init(width: 10, height: -10))
  }

  func testSpringVelocityMappingRetainsDirectionAndRejectsUnsafeValues() {
    let cases: [(velocity: CGFloat, distance: CGFloat, expected: CGFloat)] = [
      (100, 20, 5),
      (100, -20, -5),
      (-100, -20, 5),
      (100, 0, 0),
      (100, 0.5, 0),
      (100, -0.5, 0),
      (.infinity, 20, 0),
      (.nan, 20, 0),
      (100, .infinity, 0),
      (100, .nan, 0),
    ]

    for testCase in cases {
      XCTAssertEqual(
        SnapDraggingModifier.mappedInitialVelocity(
          velocity: testCase.velocity,
          distance: testCase.distance
        ),
        testCase.expected
      )
    }
  }

  func testSnapCompletesOnceAfterBothAxesFinish() {
    var session = SnapDraggingModifier.AnimationSession()
    let generation = session.begin()

    XCTAssertFalse(session.completeAxis(for: generation))
    XCTAssertTrue(session.completeAxis(for: generation))
    XCTAssertFalse(session.completeAxis(for: generation))
  }

  func testReplacingSnapDoesNotLetOldCompletionFinishItsReplacement() {
    var session = SnapDraggingModifier.AnimationSession()
    let oldGeneration = session.begin()
    XCTAssertFalse(session.completeAxis(for: oldGeneration))

    let newGeneration = session.begin()
    XCTAssertFalse(session.completeAxis(for: oldGeneration))
    XCTAssertFalse(session.completeAxis(for: newGeneration))
    XCTAssertFalse(session.completeAxis(for: oldGeneration))
    XCTAssertTrue(session.completeAxis(for: newGeneration))
  }

  func testInterruptingSnapDiscardsItsRemainingCompletion() {
    var session = SnapDraggingModifier.AnimationSession()
    let interruptedGeneration = session.begin()
    XCTAssertFalse(session.completeAxis(for: interruptedGeneration))

    session.invalidate()
    XCTAssertFalse(session.completeAxis(for: interruptedGeneration))

    let nextGeneration = session.begin()
    XCTAssertFalse(session.completeAxis(for: interruptedGeneration))
    XCTAssertFalse(session.completeAxis(for: nextGeneration))
    XCTAssertTrue(session.completeAxis(for: nextGeneration))
  }

  func testHorizontalAxisAcceptsHorizontalDominantVelocity() {
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 40)
      )
    )
  }

  func testHorizontalAxisRejectsVerticalDominantVelocity() {
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -40, y: 100)
      )
    )
  }

  func testVerticalAxisAcceptsVerticalDominantVelocity() {
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: 40, y: -100)
      )
    )
  }

  func testVerticalAxisRejectsHorizontalDominantVelocity() {
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: 100, y: -40)
      )
    )
  }

  func testSingleAxisRejectsEqualDiagonalVelocity() {
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 100)
      )
    )
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: -100, y: 100)
      )
    )
  }

  func testBothAxesAcceptMovementInEitherDirection() {
    let bothAxes: Axis.Set = [.horizontal, .vertical]

    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: bothAxes,
        translation: .zero,
        velocity: .init(x: 100, y: 0)
      )
    )
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: bothAxes,
        translation: .zero,
        velocity: .init(x: 0, y: -100)
      )
    )
  }

  func testNoAxisAndNoMovementDoNotBegin() {
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: [],
        translation: .init(x: 100, y: 0),
        velocity: .init(x: 100, y: 0)
      )
    )
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: [.horizontal, .vertical],
        translation: .zero,
        velocity: .zero
      )
    )
  }

  func testTranslationDeterminesDirectionWhenAvailable() {
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .init(x: -20, y: 5),
        velocity: .init(x: -5, y: 100)
      )
    )

    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .init(x: -20, y: 20),
        velocity: .init(x: -100, y: 5)
      )
    )
  }

  func testVelocityProvidesFallbackBeforeTranslationIsAvailable() {
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 20)
      )
    )
  }

  func testMinimumDistanceUsesTotalTranslation() {
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.hasReachedMinimumDistance(
        translation: .init(x: 3, y: 4),
        minimumDistance: 6
      )
    )
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.hasReachedMinimumDistance(
        translation: .init(x: 3, y: 4),
        minimumDistance: 5
      )
    )
  }

  func testActivationRegionUsesSemanticHorizontalEdges() {
    let size = CGSize(width: 100, height: 200)

    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        at: .init(x: 10, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .leftToRight
      )
    )
    XCTAssertFalse(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        at: .init(x: 10, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .rightToLeft
      )
    )
    XCTAssertTrue(
      SnapDraggingModifier.GestureAdmission.shouldBegin(
        at: .init(x: 90, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .rightToLeft
      )
    )
  }

  func testEndedConsumesExactlyOneEndActionAfterAChange() {
    var session = SnapDraggingModifier.GestureSession()

    XCTAssertNil(session.consumeTerminalAction(for: .ended))

    session.recordDeliveredChange()

    XCTAssertEqual(session.consumeTerminalAction(for: .ended), .end)
    XCTAssertNil(session.consumeTerminalAction(for: .ended))
  }

  func testCancellationAndFailureConsumeExactlyOneCancelAction() {
    var cancelledSession = SnapDraggingModifier.GestureSession()
    XCTAssertNil(cancelledSession.consumeTerminalAction(for: .cancelled))
    cancelledSession.recordDeliveredChange()

    XCTAssertEqual(cancelledSession.consumeTerminalAction(for: .cancelled), .cancel)
    XCTAssertNil(cancelledSession.consumeTerminalAction(for: .failed))

    var failedSession = SnapDraggingModifier.GestureSession()
    XCTAssertNil(failedSession.consumeTerminalAction(for: .failed))
    failedSession.recordDeliveredChange()

    XCTAssertEqual(failedSession.consumeTerminalAction(for: .failed), .cancel)
    XCTAssertNil(failedSession.consumeTerminalAction(for: .cancelled))
  }

  func testNonterminalStatesPreserveAnActivatedGesture() {
    var session = SnapDraggingModifier.GestureSession()
    session.recordDeliveredChange()

    XCTAssertNil(session.consumeTerminalAction(for: .began))
    XCTAssertNil(session.consumeTerminalAction(for: .changed))
    XCTAssertTrue(session.hasDeliveredChange)
    XCTAssertEqual(session.consumeTerminalAction(for: .ended), .end)
    XCTAssertFalse(session.hasDeliveredChange)
  }
}
