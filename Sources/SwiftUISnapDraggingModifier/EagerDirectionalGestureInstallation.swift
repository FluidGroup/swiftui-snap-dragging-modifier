import SwiftUI
import UIKit

/// Installs the package's existing directional recognizer on a component's UIKit host.
///
/// SwiftUI may defer `UIGestureRecognizerRepresentable` creation until the first
/// touch. A navigation failure graph must instead exist before that touch, so
/// this marker eagerly attaches the same coordinator-backed recognizer at mount.
@available(iOS 18.0, *)
struct EagerDirectionalGestureInstallation: UIViewRepresentable {
  let gesture: DirectionalDragGesture

  func makeCoordinator() -> Coordinator { Coordinator(gesture: gesture) }

  func makeUIView(context: Context) -> AttachmentMarker {
    let marker = AttachmentMarker()
    marker.isUserInteractionEnabled = false
    marker.checkAttachment = { [weak coordinator = context.coordinator] in
      coordinator?.retryAttachment()
    }
    marker.didDetach = { [weak coordinator = context.coordinator] in
      coordinator?.detach()
    }
    context.coordinator.update(gesture: gesture)
    return marker
  }

  func updateUIView(_ uiView: AttachmentMarker, context: Context) {
    context.coordinator.update(gesture: gesture)
  }

  static func dismantleUIView(_ uiView: AttachmentMarker, coordinator: Coordinator) {
    uiView.checkAttachment = {}
    uiView.didDetach = {}
    coordinator.disconnect()
  }

  /// Owns installation while all gesture behavior remains in the shared coordinator.
  @MainActor
  final class Coordinator: NSObject {
    let recognizer: UIPanGestureRecognizer
    let gestureCoordinator: DirectionalDragGesture.Coordinator
    private var gesture: DirectionalDragGesture

    init(gesture: DirectionalDragGesture) {
      self.gesture = gesture
      let shared = DirectionalDragGesture.Coordinator(
        axis: gesture.axis, activation: gesture.activation, contentSize: gesture.contentSize,
        layoutDirection: gesture.layoutDirection, configuration: gesture.configuration, converter: nil
      )
      gestureCoordinator = shared
      recognizer = shared.makeRecognizer()
      super.init()
      recognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    func update(gesture: DirectionalDragGesture) {
      self.gesture = gesture
      gestureCoordinator.update(from: gesture, recognizer: recognizer)
      retryAttachment()
    }

    func retryAttachment() {
      guard let host = gesture.configuration.attachmentView?() else {
        detach()
        return
      }
      if recognizer.view !== host {
        recognizer.view?.removeGestureRecognizer(recognizer)
        host.addGestureRecognizer(recognizer)
      }
      // Repeat after attachment so caller-owned failure relationships can use
      // the host's responder chain before UIKit begins delivering a touch.
      gesture.configuration.onRecognizer(recognizer)
    }

    func detach() { recognizer.view?.removeGestureRecognizer(recognizer) }

    func disconnect() {
      recognizer.isEnabled = false
      detach()
      recognizer.removeTarget(self, action: #selector(handlePan(_:)))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      gestureCoordinator.handleAction(recognizer, gesture: gesture)
    }
  }

  /// Retries a host that was not yet created when SwiftUI first made the marker.
  @MainActor
  final class AttachmentMarker: UIView {
    var checkAttachment: () -> Void = {}
    var didDetach: () -> Void = {}

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil { didDetach() }
      else { checkAttachment() }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      if window != nil { checkAttachment() }
    }
  }
}
