import SwiftUI

struct XTranslationEffect: GeometryEffect {
  
  var offset: CGFloat = .zero
  
  @Binding var presenting: CGFloat
    
  init(offset: CGFloat, presenting: Binding<CGFloat>) {
    self.offset = offset
    self._presenting = presenting
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
    return .init(.init(translationX: offset, y: 0))
  }
  
}

struct YTranslationEffect: GeometryEffect {
  
  var offset: CGFloat = .zero
  
  @Binding var presenting: CGFloat
  
  init(offset: CGFloat, presenting: Binding<CGFloat>) {
    self.offset = offset
    self._presenting = presenting
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
    return .init(.init(translationX: 0, y: offset))
  }
  
}

extension View {
  
  /// Applies offset effect that is animatable against ``SwiftUI/View/offset``
  func _animatableOffset(x: CGFloat, presenting: Binding<CGFloat>) -> some View {
    self.modifier(XTranslationEffect(offset: x, presenting: presenting))
  }
  
  /// Applies offset effect that is animatable against ``SwiftUI/View/offset``
  func _animatableOffset(y: CGFloat, presenting: Binding<CGFloat>) -> some View {
    self.modifier(YTranslationEffect(offset: y, presenting: presenting))
  }
  
}
