import SwiftUI
import UIKit
import XCTest

@testable import SwiftUISnapDraggingModifier

/// Verifies installation and caller configuration happen before touch recognition.
@available(iOS 18.0, *)
@MainActor
final class EagerDirectionalInstallationTests: XCTestCase {

  func testMountedHostGetsOnePackageRecognizerConfiguredBeforeTheFirstTouch() {
    let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 640))
    let controller = UIViewController()
    window.rootViewController = controller
    let host = UIView(frame: .init(x: 20, y: 80, width: 180, height: 40))
    controller.view.addSubview(host)
    window.isHidden = false
    defer { window.isHidden = true }

    var configuredBeforeTouch = false
    let gesture = makeGesture(
      attachmentView: { host },
      onRecognizer: { recognizer in
        if recognizer.view === host, host.window === window {
          configuredBeforeTouch = recognizer.state == .possible
        }
      }
    )
    let installation = EagerDirectionalGestureInstallation.Coordinator(gesture: gesture)
    installation.update(gesture: gesture)
    installation.retryAttachment()

    XCTAssertTrue(configuredBeforeTouch)
    XCTAssertTrue(installation.recognizer.view === host)
    XCTAssertTrue(installation.recognizer.delegate === installation.gestureCoordinator)
    XCTAssertEqual(host.gestureRecognizers?.filter { $0 === installation.recognizer }.count, 1)

    installation.disconnect()
    XCTAssertNil(installation.recognizer.view)
    XCTAssertFalse(installation.recognizer.isEnabled)
    XCTAssertFalse(host.gestureRecognizers?.contains { $0 === installation.recognizer } ?? false)
  }

  func testLateHostResolutionRetriesWithoutChangingRecognizerOrDelegateIdentity() {
    weak var resolvedHost: UIView?
    let gesture = makeGesture(attachmentView: { resolvedHost })
    let installation = EagerDirectionalGestureInstallation.Coordinator(gesture: gesture)
    let recognizer = installation.recognizer
    installation.update(gesture: gesture)
    XCTAssertNil(recognizer.view)

    let host = UIView(frame: .init(x: 0, y: 0, width: 180, height: 40))
    resolvedHost = host
    installation.retryAttachment()
    XCTAssertTrue(recognizer.view === host)
    XCTAssertTrue(recognizer === installation.recognizer)
    XCTAssertTrue(recognizer.delegate === installation.gestureCoordinator)

    resolvedHost = nil
    installation.retryAttachment()
    XCTAssertNil(recognizer.view)
    XCTAssertFalse(host.gestureRecognizers?.contains { $0 === recognizer } ?? false)
    installation.disconnect()
  }

  private func makeGesture(
    attachmentView: @escaping @MainActor () -> UIView?,
    onRecognizer: @escaping @MainActor (UIPanGestureRecognizer) -> Void = { _ in }
  ) -> DirectionalDragGesture {
    DirectionalDragGesture(
      axis: .horizontal,
      activation: .init(),
      contentSize: .init(width: 180, height: 40),
      layoutDirection: .leftToRight,
      configuration: .init(attachmentView: attachmentView, onRecognizer: onRecognizer),
      onChange: { _ in }, onEnd: { _ in }, onCancel: {}
    )
  }
}
