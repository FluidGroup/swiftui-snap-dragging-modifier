import SwiftUI
import XCTest

@testable import SwiftUISnapDraggingModifier

/// Regression coverage for caller admission and Portal handoff cancellation.
final class DirectionalIntegrationTests: XCTestCase {

  func testAdditionalAdmissionCannotOverrideDisabledAxisOrActivationRejection() {
    var calls = 0
    let alwaysAccept: () -> Bool = {
      calls += 1
      return true
    }

    XCTAssertFalse(admit(isEnabled: false, translation: .init(x: 40, y: 0), additionalAdmission: alwaysAccept))
    XCTAssertFalse(admit(translation: .init(x: 5, y: 40), additionalAdmission: alwaysAccept))
    XCTAssertFalse(admit(translation: .init(x: 40, y: 40), additionalAdmission: alwaysAccept))
    XCTAssertFalse(
      admit(
        translation: .init(x: 40, y: 0),
        startLocation: .init(x: 100, y: 50),
        region: .edge(.leading),
        additionalAdmission: alwaysAccept
      )
    )
    XCTAssertEqual(calls, 0)
  }

  func testCallerCanReserveRightSwipesWhileLeftAndVerticalMovementRemainUnclaimed() {
    var calls = 0
    let physicalRightOnly: (CGPoint) -> Bool = { translation in
      calls += 1
      return translation.x > 0
    }

    let right = CGPoint(x: 40, y: 5)
    XCTAssertTrue(admit(translation: right) { physicalRightOnly(right) })

    let left = CGPoint(x: -40, y: 5)
    XCTAssertFalse(admit(translation: left) { physicalRightOnly(left) })

    let vertical = CGPoint(x: 5, y: 40)
    XCTAssertFalse(admit(translation: vertical) { physicalRightOnly(vertical) })
    XCTAssertEqual(calls, 2, "Cross-axis movement must fail before the caller policy runs.")
  }

  func testAdditionalAdmissionCanRejectAnOtherwiseEligiblePan() {
    var calls = 0
    XCTAssertFalse(admit(translation: .init(x: 40, y: 0)) {
      calls += 1
      return false
    })
    XCTAssertEqual(calls, 1)
  }

  func testRestingCancellationTargetSupersedesAnAcceptedHandoffPosition() {
    // After a Portal accepts this offset, the caller resets the hidden source's
    // public binding to zero. Upstream's private target still holds this value.
    let acceptedHandoff = CGSize(width: 82, height: 0)
    let target = SnapDraggingCancellation.target(lastTarget: acceptedHandoff, explicitTarget: .zero)
    XCTAssertEqual(target, .zero)

    // Once cancellation recovers to rest, a further cancellation stays at rest.
    XCTAssertEqual(SnapDraggingCancellation.target(lastTarget: target, explicitTarget: .zero), .zero)
  }

  func testDefaultCancellationPreservesThePreviousUpstreamTarget() {
    let target = CGSize(width: 120, height: 30)
    XCTAssertEqual(SnapDraggingCancellation.target(lastTarget: target, explicitTarget: nil), target)
  }

  func testExistingReleaseCallbackReceivesModelOffsetAndPreservesVelocityMutation() {
    let model = CGSize(width: 88, height: 0)
    let drawing = CGSize(width: 57, height: 0)
    let size = CGSize(width: 180, height: 40)
    var calls = 0
    let handler = SnapDraggingModifier.Handler(onEndDragging: { velocity, offset, contentSize in
      calls += 1
      XCTAssertEqual(offset, model)
      XCTAssertEqual(contentSize, size)
      velocity.dx = 120
      return .zero
    })

    var velocity = CGVector(dx: 1_500, dy: 0)
    let target = handler.targetOffset(
      velocity: &velocity, offset: model, presentingOffset: drawing, contentSize: size
    )
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(target, .zero)
    XCTAssertEqual(velocity.dx, 120)
  }

  func testPresentationReleaseCallbackTakesPrecedenceAndReceivesDistinctDrawingOffset() {
    let model = CGSize(width: 88, height: 0)
    let drawing = CGSize(width: 57, height: 0)
    let size = CGSize(width: 180, height: 40)
    var calls = 0
    let handler = SnapDraggingModifier.Handler(
      onEndDragging: { _, _, _ in
        XCTFail("Only one release callback may resolve the target.")
        return .zero
      },
      onEndDraggingWithPresentation: { velocity, offset, presentingOffset, contentSize in
        calls += 1
        XCTAssertEqual(offset, model)
        XCTAssertEqual(presentingOffset, drawing)
        XCTAssertEqual(contentSize, size)
        XCTAssertEqual(velocity.dx, 1_500)
        velocity.dy = 0
        return offset
      }
    )

    var velocity = CGVector(dx: 1_500, dy: 40)
    let target = handler.targetOffset(
      velocity: &velocity, offset: model, presentingOffset: drawing, contentSize: size
    )
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(target, model)
    XCTAssertEqual(velocity.dx, 1_500)
    XCTAssertEqual(velocity.dy, 0)
  }

  private func admit(
    isEnabled: Bool = true,
    translation: CGPoint,
    startLocation: CGPoint = .init(x: 50, y: 50),
    region: SnapDraggingModifier.Activation.Region = .screen,
    additionalAdmission: () -> Bool
  ) -> Bool {
    DirectionalDragGestureAdmission.shouldBegin(
      isEnabled: isEnabled,
      axis: .horizontal,
      translation: translation,
      velocity: .zero,
      startLocation: startLocation,
      contentSize: .init(width: 200, height: 100),
      region: region,
      layoutDirection: .leftToRight,
      additionalAdmission: additionalAdmission
    )
  }
}
