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

    private let converter: CoordinateSpaceConverter
    private var session = DirectionalDragGestureSession()

    init(
      axis: Axis.Set,
      activation: SnapDraggingModifier.Activation,
      contentSize: CGSize,
      layoutDirection: LayoutDirection,
      converter: CoordinateSpaceConverter
    ) {
      self.axis = axis
      self.activation = activation
      self.contentSize = contentSize
      self.layoutDirection = layoutDirection
      self.converter = converter
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
        return false
      }

      let translation =
        converter.localTranslation
        ?? {
          panGestureRecognizer.translation(in: panGestureRecognizer.view)
        }()
      let velocity =
        converter.localVelocity
        ?? {
          panGestureRecognizer.velocity(in: panGestureRecognizer.view)
        }()

      guard
        DirectionalDragGestureAdmission.shouldBegin(
          axis: axis,
          translation: translation,
          velocity: velocity
        )
      else {
        return false
      }

      let location = converter.localLocation
      let startLocation = CGPoint(
        x: location.x - translation.x,
        y: location.y - translation.y
      )

      return DirectionalDragGestureAdmission.shouldBegin(
        at: startLocation,
        contentSize: contentSize,
        region: activation.regionToActivate,
        layoutDirection: layoutDirection
      )
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
  }

  let axis: Axis.Set
  let activation: SnapDraggingModifier.Activation
  let contentSize: CGSize
  let layoutDirection: LayoutDirection
  let onChange: (Value) -> Void
  let onEnd: (Value) -> Void
  let onCancel: () -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    Coordinator(
      axis: axis,
      activation: activation,
      contentSize: contentSize,
      layoutDirection: layoutDirection,
      converter: converter
    )
  }

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    let gestureRecognizer = UIPanGestureRecognizer()
    gestureRecognizer.maximumNumberOfTouches = 1
    // Once a directional drag begins, descendant controls must not also commit
    // their tap action. Vertical-dominant pans fail before this takes effect.
    gestureRecognizer.cancelsTouchesInView = true
    gestureRecognizer.delaysTouchesBegan = false
    gestureRecognizer.delaysTouchesEnded = false
    gestureRecognizer.delegate = context.coordinator
    return gestureRecognizer
  }

  func updateUIGestureRecognizer(_ gestureRecognizer: UIPanGestureRecognizer, context: Context) {
    context.coordinator.axis = axis
    context.coordinator.activation = activation
    context.coordinator.contentSize = contentSize
    context.coordinator.layoutDirection = layoutDirection
  }

  func handleUIGestureRecognizerAction(
    _ gestureRecognizer: UIPanGestureRecognizer,
    context: Context
  ) {
    let translation =
      context.converter.localTranslation
      ?? {
        gestureRecognizer.translation(in: gestureRecognizer.view)
      }()
    let velocity =
      context.converter.localVelocity
      ?? {
        gestureRecognizer.velocity(in: gestureRecognizer.view)
      }()
    let value = Value(
      translation: CGSize(width: translation.x, height: translation.y),
      velocity: CGVector(dx: velocity.x, dy: velocity.y)
    )

    let state = gestureRecognizer.state

    switch state {
    case .began, .changed:
      if context.coordinator.shouldDeliverChange(translation: translation) {
        onChange(value)
      }
    case .ended, .cancelled, .failed:
      switch context.coordinator.consumeTerminalAction(for: state) {
      case .end:
        onEnd(value)
      case .cancel:
        onCancel()
      case nil:
        break
      }
    case .possible:
      break
    @unknown default:
      if context.coordinator.consumeTerminalAction(for: state) == .cancel {
        onCancel()
      }
    }
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
