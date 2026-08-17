import SwiftUI
import XCTest

@testable import SwiftUISnapDraggingModifier

final class SwiftUISnapDraggingModifierTests: XCTestCase {

  func testHorizontalAxisAcceptsHorizontalDominantVelocity() {
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 40)
      )
    )
  }

  func testHorizontalAxisRejectsVerticalDominantVelocity() {
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -40, y: 100)
      )
    )
  }

  func testVerticalAxisAcceptsVerticalDominantVelocity() {
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: 40, y: -100)
      )
    )
  }

  func testVerticalAxisRejectsHorizontalDominantVelocity() {
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: 100, y: -40)
      )
    )
  }

  func testSingleAxisRejectsEqualDiagonalVelocity() {
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 100)
      )
    )
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .vertical,
        translation: .zero,
        velocity: .init(x: -100, y: 100)
      )
    )
  }

  func testBothAxesAcceptMovementInEitherDirection() {
    let bothAxes: Axis.Set = [.horizontal, .vertical]

    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: bothAxes,
        translation: .zero,
        velocity: .init(x: 100, y: 0)
      )
    )
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: bothAxes,
        translation: .zero,
        velocity: .init(x: 0, y: -100)
      )
    )
  }

  func testNoAxisAndNoMovementDoNotBegin() {
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: [],
        translation: .init(x: 100, y: 0),
        velocity: .init(x: 100, y: 0)
      )
    )
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: [.horizontal, .vertical],
        translation: .zero,
        velocity: .zero
      )
    )
  }

  func testTranslationDeterminesDirectionWhenAvailable() {
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .init(x: -20, y: 5),
        velocity: .init(x: -5, y: 100)
      )
    )

    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .init(x: -20, y: 20),
        velocity: .init(x: -100, y: 5)
      )
    )
  }

  func testVelocityProvidesFallbackBeforeTranslationIsAvailable() {
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        axis: .horizontal,
        translation: .zero,
        velocity: .init(x: -100, y: 20)
      )
    )
  }

  func testMinimumDistanceUsesTotalTranslation() {
    XCTAssertFalse(
      DirectionalDragGestureAdmission.hasReachedMinimumDistance(
        translation: .init(x: 3, y: 4),
        minimumDistance: 6
      )
    )
    XCTAssertTrue(
      DirectionalDragGestureAdmission.hasReachedMinimumDistance(
        translation: .init(x: 3, y: 4),
        minimumDistance: 5
      )
    )
  }

  func testActivationRegionUsesSemanticHorizontalEdges() {
    let size = CGSize(width: 100, height: 200)

    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        at: .init(x: 10, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .leftToRight
      )
    )
    XCTAssertFalse(
      DirectionalDragGestureAdmission.shouldBegin(
        at: .init(x: 10, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .rightToLeft
      )
    )
    XCTAssertTrue(
      DirectionalDragGestureAdmission.shouldBegin(
        at: .init(x: 90, y: 100),
        contentSize: size,
        region: .edge(.leading),
        layoutDirection: .rightToLeft
      )
    )
  }

  func testEndedConsumesExactlyOneEndActionAfterAChange() {
    var session = DirectionalDragGestureSession()

    XCTAssertNil(session.consumeTerminalAction(for: .ended))

    session.recordDeliveredChange()

    XCTAssertEqual(session.consumeTerminalAction(for: .ended), .end)
    XCTAssertNil(session.consumeTerminalAction(for: .ended))
  }

  func testCancellationAndFailureConsumeExactlyOneCancelAction() {
    var cancelledSession = DirectionalDragGestureSession()
    cancelledSession.recordDeliveredChange()

    XCTAssertEqual(cancelledSession.consumeTerminalAction(for: .cancelled), .cancel)
    XCTAssertNil(cancelledSession.consumeTerminalAction(for: .failed))

    var failedSession = DirectionalDragGestureSession()
    failedSession.recordDeliveredChange()

    XCTAssertEqual(failedSession.consumeTerminalAction(for: .failed), .cancel)
    XCTAssertNil(failedSession.consumeTerminalAction(for: .cancelled))
  }
}
