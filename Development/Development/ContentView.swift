//
//  ContentView.swift
//  Development
//
//  Created by Muukii on 2024/07/23.
//

import SwiftUI
import SwiftUISnapDraggingModifier

struct ContentView: View {
  var body: some View {
    Joystick()
  }
}

#Preview {
  ContentView()
}

struct Joystick: View {
  
  @State var offset: CGSize = .zero
  
  @State var isOn: Bool = false
  
  var body: some View {
    stick
      .padding(10)
  }
  
  private var stick: some View {
    
    VStack {
      
      Button("Add offset") {
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 1, damping: 1, initialVelocity: 0)) {
          offset.width += 10
        }
      }
      
      Circle()
        .fill(Color.yellow)
        .frame(width: 100, height: 100)
        .modifier(
          SnapDraggingModifier(
            offset: $offset,
            springParameter: .interpolation(mass: 1, stiffness: 1, damping: 1)
          )
        )
      Circle()
        .fill(Color.green)
        .frame(width: 100, height: 100)
      
    }
    .padding(20)
    .background(Color.secondary)
    .coordinateSpace(name: "A")
    
  }
}
