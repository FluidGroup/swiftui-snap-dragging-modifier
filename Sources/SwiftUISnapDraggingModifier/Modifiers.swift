import SwiftUI

struct XTranslationEffect: GeometryEffect {

  var offset: CGFloat = .zero

  @Binding var presenting: CGFloat
  var renderingTracker: RenderedOffsetTracker?
  var onPresentingOffsetChange: (CGSize) -> Void

  init(
    offset: CGFloat,
    presenting: Binding<CGFloat>,
    renderingTracker: RenderedOffsetTracker? = nil,
    onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in }
  ) {
    self.offset = offset
    self._presenting = presenting
    self.renderingTracker = renderingTracker
    self.onPresentingOffsetChange = onPresentingOffsetChange
  }

  var animatableData: CGFloat {
    get {
      offset
    }
    set {
      DispatchQueue.main.async { [$presenting] in
        $presenting.wrappedValue = newValue
      }
      offset = newValue
    }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    renderingTracker?.record(horizontal: offset, onChange: onPresentingOffsetChange)
    return .init(.init(translationX: offset, y: 0))
  }

}

struct YTranslationEffect: GeometryEffect {

  var offset: CGFloat = .zero

  @Binding var presenting: CGFloat
  var renderingTracker: RenderedOffsetTracker?
  var onPresentingOffsetChange: (CGSize) -> Void

  init(
    offset: CGFloat,
    presenting: Binding<CGFloat>,
    renderingTracker: RenderedOffsetTracker? = nil,
    onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in }
  ) {
    self.offset = offset
    self._presenting = presenting
    self.renderingTracker = renderingTracker
    self.onPresentingOffsetChange = onPresentingOffsetChange
  }

  var animatableData: CGFloat {
    get {
      offset
    }
    set {
      DispatchQueue.main.async { [$presenting] in
        $presenting.wrappedValue = newValue
      }
      offset = newValue
    }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    renderingTracker?.record(vertical: offset, onChange: onPresentingOffsetChange)
    return .init(.init(translationX: 0, y: offset))
  }

}

extension View {

  /// Applies offset effect that is animatable against ``SwiftUI/View/offset``
  func _animatableOffset(
    x: CGFloat,
    presenting: Binding<CGFloat>,
    renderingTracker: RenderedOffsetTracker? = nil,
    onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in }
  ) -> some View {
    self.modifier(
      XTranslationEffect(
        offset: x, presenting: presenting, renderingTracker: renderingTracker,
        onPresentingOffsetChange: onPresentingOffsetChange
      )
    )
  }

  /// Applies offset effect that is animatable against ``SwiftUI/View/offset``
  func _animatableOffset(
    y: CGFloat,
    presenting: Binding<CGFloat>,
    renderingTracker: RenderedOffsetTracker? = nil,
    onPresentingOffsetChange: @escaping (CGSize) -> Void = { _ in }
  ) -> some View {
    self.modifier(
      YTranslationEffect(
        offset: y, presenting: presenting, renderingTracker: renderingTracker,
        onPresentingOffsetChange: onPresentingOffsetChange
      )
    )
  }

}
