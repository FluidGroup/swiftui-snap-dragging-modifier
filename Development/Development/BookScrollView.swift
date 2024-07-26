//
//  BookScrollView.swift
//  Development
//
//  Created by Muukii on 2024/07/25.
//

import SwiftUI
import SwiftUIScrollViewInteroperableDragGesture
import SwiftUISnapDraggingModifier

#if DEBUG

@available(iOS 18, *)
private var scrollView: some View {
  ScrollView([.horizontal, .vertical]) {
    Grid(horizontalSpacing: 20, verticalSpacing: 20) {
      ForEach(0..<4) { _ in
        GridRow {
          ForEach(0..<4) { _ in Color.teal.frame(width: 30, height: 30) }
        }
      }
    }
    .padding()
    .background(Color.red)
    .padding()
    .background(Color.blue)
  }
}

@available(iOS 18, *)
#Preview("Normal") {
  
  @Previewable @State var offset: CGSize = .zero

  ZStack {

    VStack {
      scrollView
    }
    .frame(width: 200, height: 200)
    .background(Color.green.secondary)
    .padding()
    .background(Color.green.tertiary)
    .modifier(
      SnapDraggingModifier(
        gestureMode: .scrollViewInteroperable(
          .init(ignoresScrollView: false, sticksToEdges: false)
        ),
        offset: $offset
      )
    )
    .background(Color.purple.tertiary)

  }
}

@available(iOS 18, *)
#Preview("SticksToEdges") {
  
  @Previewable @State var offset: CGSize = .zero
  
  ZStack {
    
    VStack {
      scrollView
    }
    .frame(width: 200, height: 200)
    .background(Color.green.secondary)
    .padding()
    .background(Color.green.tertiary)
    .modifier(
      SnapDraggingModifier(
        gestureMode: .scrollViewInteroperable(
          .init(ignoresScrollView: false, sticksToEdges: true)
        ),
        offset: $offset
      )
    )
    .background(Color.purple.tertiary)
    
  }
}

@available(iOS 18, *)
#Preview("IgnoreScrollView") {
  
  @Previewable @State var offset: CGSize = .zero
  
  ZStack {
    
    VStack {
      scrollView
    }
    .frame(width: 200, height: 200)
    .background(Color.green.secondary)
    .padding()
    .background(Color.green.tertiary)
    .modifier(
      SnapDraggingModifier(
        gestureMode: .scrollViewInteroperable(
          .init(ignoresScrollView: true, sticksToEdges: true)
        ),
        offset: $offset
      )
    )
    .background(Color.purple.tertiary)
    
  }
}


#endif
