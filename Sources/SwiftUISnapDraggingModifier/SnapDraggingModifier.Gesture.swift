import SwiftUI
import UIKit

extension SnapDraggingModifier {

  /// Carries movement in the stationary drag space, in points and points/second.
  struct GestureValue {
    let translation: CGSize
    let velocity: CGVector
  }

  /// Tracks whether a UIKit drag has produced an observable change and
  /// consumes at most one terminal action for that drag.
  struct GestureSession {

    enum TerminalAction: Equatable {
      case end
      case cancel
    }

    private(set) var hasDeliveredChange = false

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

  /// Lets the modifier cancel native pans when view updates cannot reach an
  /// active representable, and releases their scroll locks on disappearance.
  @MainActor
  final class GestureControl {

    private struct Registration {
      weak var owner: AnyObject?
      let cancel: @MainActor (Bool) -> Void
      let resume: @MainActor (Bool) -> Void
    }

    private var registrations: [Registration] = []

    func register(
      owner: AnyObject,
      cancel: @escaping @MainActor (Bool) -> Void,
      resume: @escaping @MainActor (Bool) -> Void
    ) {
      registrations.removeAll { $0.owner == nil }
      registrations.append(Registration(owner: owner, cancel: cancel, resume: resume))
    }

    /// Restores retained coordinators when their view becomes visible again.
    func resumeGestures(enabled: Bool) {
      registrations.removeAll { $0.owner == nil }
      for registration in registrations {
        registration.resume(enabled)
      }
    }

    /// Ends active owners once; `reenable` permits the next touch sequence.
    func cancelActiveGestures(reenable: Bool) {
      registrations.removeAll { $0.owner == nil }
      for registration in registrations {
        registration.cancel(reenable)
      }
    }
  }

  /// Pure axis, distance, and touch-down admission shared by UIKit adapters.
  enum GestureAdmission {

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

      if axis.contains(.horizontal) {
        if axis.contains(.vertical) {
          return horizontalMagnitude > 0 || verticalMagnitude > 0
        }
        return horizontalMagnitude > verticalMagnitude
      }
      if axis.contains(.vertical) {
        return verticalMagnitude > horizontalMagnitude
      }
      return false
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
}
