import SwiftUI
import UIKit

/// A UIKit-backed pan gesture that begins only when movement is compatible
/// with its configured axes.
///
/// Axis admission happens before the recognizer enters `.began`, allowing an
/// enclosing scroll view to keep a cross-axis pan without requiring explicit
/// knowledge of that scroll view.
@available(iOS 18.0, *)
struct DirectionalDragGesture: UIGestureRecognizerRepresentable {

  struct Value {
    let translation: CGSize
    let velocity: CGVector
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {

    var axis: Axis.Set
    var activation: SnapDraggingModifier.Activation
    var contentSize: CGSize
    var layoutDirection: LayoutDirection
    var configuration: GestureModeDirectional

    private let converter: CoordinateSpaceConverter?
    private var session = DirectionalDragGestureSession()

    init(
      axis: Axis.Set,
      activation: SnapDraggingModifier.Activation,
      contentSize: CGSize,
      layoutDirection: LayoutDirection,
      configuration: GestureModeDirectional,
      converter: CoordinateSpaceConverter?
    ) {
      self.axis = axis
      self.activation = activation
      self.contentSize = contentSize
      self.layoutDirection = layoutDirection
      self.configuration = configuration
      self.converter = converter
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard configuration.isEnabled,
        let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
        return false
      }

      let translation = translation(of: panGestureRecognizer)
      let velocity = velocity(of: panGestureRecognizer)
      let location = converter?.localLocation ?? panGestureRecognizer.location(in: panGestureRecognizer.view)
      // Region admission uses the original local touch location. Eager movement
      // delivery uses window delta to avoid feeding back the host's own motion.
      let localTranslation = converter != nil
        ? translation : panGestureRecognizer.translation(in: panGestureRecognizer.view)
      let startLocation = CGPoint(
        x: location.x - localTranslation.x,
        y: location.y - localTranslation.y
      )

      return DirectionalDragGestureAdmission.shouldBegin(
        isEnabled: configuration.isEnabled,
        axis: axis,
        translation: translation,
        velocity: velocity,
        startLocation: startLocation,
        contentSize: contentSize,
        region: activation.regionToActivate,
        layoutDirection: layoutDirection
      ) {
        configuration.shouldBegin(
          .init(
            translation: translation,
            startLocation: startLocation,
            velocity: CGVector(dx: velocity.x, dy: velocity.y),
            gestureRecognizer: panGestureRecognizer
          )
        )
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
    }

    func shouldDeliverChange(translation: CGPoint) -> Bool {
      guard
        DirectionalDragGestureAdmission.hasReachedMinimumDistance(
          translation: translation,
          minimumDistance: activation.minimumDistance
        )
      else {
        return false
      }

      session.recordDeliveredChange()
      return true
    }

    func consumeTerminalAction(
      for state: UIGestureRecognizer.State
    ) -> DirectionalDragGestureSession.TerminalAction? {
      session.consumeTerminalAction(for: state)
    }

    /// Creates the same package recognizer for SwiftUI and eager UIKit installation.
    func makeRecognizer() -> UIPanGestureRecognizer {
      let recognizer = UIPanGestureRecognizer()
      recognizer.maximumNumberOfTouches = 1
      recognizer.cancelsTouchesInView = true
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = self
      recognizer.isEnabled = configuration.isEnabled
      configuration.onRecognizer(recognizer)
      return recognizer
    }

    func update(from gesture: DirectionalDragGesture, recognizer: UIPanGestureRecognizer) {
      axis = gesture.axis
      activation = gesture.activation
      contentSize = gesture.contentSize
      layoutDirection = gesture.layoutDirection
      configuration = gesture.configuration
      recognizer.isEnabled = configuration.isEnabled
      configuration.onRecognizer(recognizer)
    }

    /// Shared action dispatch preserves one end/cancel callback per delivered drag.
    func handleAction(
      _ recognizer: UIPanGestureRecognizer,
      gesture: DirectionalDragGesture,
      converter actionConverter: CoordinateSpaceConverter? = nil
    ) {
      // Preserve the original representable's current per-action converter.
      // The eager installation has no SwiftUI converter and uses window delta.
      let translation = actionConverter.map {
        $0.localTranslation ?? recognizer.translation(in: recognizer.view)
      } ?? translation(of: recognizer)
      let velocity = actionConverter.map {
        $0.localVelocity ?? recognizer.velocity(in: recognizer.view)
      } ?? velocity(of: recognizer)
      let value = Value(
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGVector(dx: velocity.x, dy: velocity.y)
      )

      switch recognizer.state {
      case .began, .changed:
        if shouldDeliverChange(translation: translation) { gesture.onChange(value) }
      case .ended, .cancelled, .failed:
        switch consumeTerminalAction(for: recognizer.state) {
        case .end: gesture.onEnd(value)
        case .cancel: gesture.onCancel()
        case nil: break
        }
      case .possible:
        break
      @unknown default:
        if consumeTerminalAction(for: recognizer.state) == .cancel { gesture.onCancel() }
      }
    }

    private func translation(of recognizer: UIPanGestureRecognizer) -> CGPoint {
      if let converter {
        return converter.localTranslation ?? recognizer.translation(in: recognizer.view)
      }
      return recognizer.translation(in: recognizer.view?.window ?? recognizer.view)
    }

    private func velocity(of recognizer: UIPanGestureRecognizer) -> CGPoint {
      if let converter {
        return converter.localVelocity ?? recognizer.velocity(in: recognizer.view)
      }
      return recognizer.velocity(in: recognizer.view?.window ?? recognizer.view)
    }
  }

  let axis: Axis.Set
  let activation: SnapDraggingModifier.Activation
  let contentSize: CGSize
  let layoutDirection: LayoutDirection
  let configuration: GestureModeDirectional
  let onChange: (Value) -> Void
  let onEnd: (Value) -> Void
  let onCancel: () -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    Coordinator(
      axis: axis,
      activation: activation,
      contentSize: contentSize,
      layoutDirection: layoutDirection,
      configuration: configuration,
      converter: converter
    )
  }

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    context.coordinator.makeRecognizer()
  }

  func updateUIGestureRecognizer(_ gestureRecognizer: UIPanGestureRecognizer, context: Context) {
    context.coordinator.update(from: self, recognizer: gestureRecognizer)
  }

  func handleUIGestureRecognizerAction(
    _ gestureRecognizer: UIPanGestureRecognizer,
    context: Context
  ) {
    context.coordinator.handleAction(gestureRecognizer, gesture: self, converter: context.converter)
  }
}

/// Tracks whether a directional drag has produced an observable change and
/// consumes at most one terminal action for that drag.
struct DirectionalDragGestureSession {

  enum TerminalAction: Equatable {
    case end
    case cancel
  }

  private var hasDeliveredChange = false

  mutating func recordDeliveredChange() {
    hasDeliveredChange = true
  }

  mutating func consumeTerminalAction(
    for state: UIGestureRecognizer.State
  ) -> TerminalAction? {
    let action: TerminalAction?

    switch state {
    case .ended:
      action = .end
    case .cancelled, .failed:
      action = .cancel
    case .possible, .began, .changed:
      action = nil
    @unknown default:
      action = .cancel
    }

    guard hasDeliveredChange, let action else {
      return nil
    }

    // Consume before invoking client code so re-entrant teardown cannot emit a
    // second terminal callback for the same gesture.
    hasDeliveredChange = false
    return action
  }
}

/// Pure dominant-axis admission used by the UIKit recognizer and unit tests.
enum DirectionalDragGestureAdmission {

  private static let edgeActivationWidth: CGFloat = 20

  /// Applies package admission before asking a caller to accept this pan.
  ///
  /// Caller policies cannot admit a cross-axis or out-of-region movement that
  /// the package would ordinarily reject. The closure is evaluated at most once.
  static func shouldBegin(
    isEnabled: Bool,
    axis: Axis.Set,
    translation: CGPoint,
    velocity: CGPoint,
    startLocation: CGPoint,
    contentSize: CGSize,
    region: SnapDraggingModifier.Activation.Region,
    layoutDirection: LayoutDirection,
    additionalAdmission: () -> Bool
  ) -> Bool {
    isEnabled
      && shouldBegin(axis: axis, translation: translation, velocity: velocity)
      && shouldBegin(
        at: startLocation,
        contentSize: contentSize,
        region: region,
        layoutDirection: layoutDirection
      )
      && additionalAdmission()
  }

  static func shouldBegin(
    axis: Axis.Set,
    translation: CGPoint,
    velocity: CGPoint
  ) -> Bool {
    // Translation expresses the complete movement that led UIKit to ask
    // whether this pan should begin. Instantaneous velocity can contain small
    // sampling asymmetry even when the authored path is an equal diagonal.
    let movement = translation == .zero ? velocity : translation
    let horizontalMagnitude = abs(movement.x)
    let verticalMagnitude = abs(movement.y)

    switch (axis.contains(.horizontal), axis.contains(.vertical)) {
    case (true, true):
      return horizontalMagnitude > 0 || verticalMagnitude > 0
    case (true, false):
      return horizontalMagnitude > verticalMagnitude
    case (false, true):
      return verticalMagnitude > horizontalMagnitude
    case (false, false):
      return false
    }
  }

  static func hasReachedMinimumDistance(
    translation: CGPoint,
    minimumDistance: Double
  ) -> Bool {
    hypot(translation.x, translation.y) >= max(0, minimumDistance)
  }

  static func shouldBegin(
    at startLocation: CGPoint,
    contentSize: CGSize,
    region: SnapDraggingModifier.Activation.Region,
    layoutDirection: LayoutDirection
  ) -> Bool {
    switch region {
    case .screen:
      return true
    case .edge(let edges):
      if edges.contains(.top), startLocation.y <= edgeActivationWidth {
        return true
      }

      if edges.contains(.bottom), startLocation.y >= contentSize.height - edgeActivationWidth {
        return true
      }

      let isNearLeftEdge = startLocation.x <= edgeActivationWidth
      let isNearRightEdge = startLocation.x >= contentSize.width - edgeActivationWidth

      switch layoutDirection {
      case .leftToRight:
        return (edges.contains(.leading) && isNearLeftEdge)
          || (edges.contains(.trailing) && isNearRightEdge)
      case .rightToLeft:
        return (edges.contains(.leading) && isNearRightEdge)
          || (edges.contains(.trailing) && isNearLeftEdge)
      @unknown default:
        return false
      }
    }
  }
}
