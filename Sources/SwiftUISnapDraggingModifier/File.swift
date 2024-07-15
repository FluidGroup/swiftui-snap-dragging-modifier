import SwiftUI
import SwiftUISupportSizing

public struct SheetModifier<DisplayContent: View>: ViewModifier {

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool
  @State var contentOffset: CGSize = .zero

  public init(
    isPresented: Binding<Bool>,
    @ViewBuilder displayContent: @escaping () -> DisplayContent
  ) {
    self._isPresented = isPresented
    self.displayContent = displayContent
  }

  public func body(content: Content) -> some View {
    ZStack {
      content
//      if isPresented {
        VStack {
          Spacer(minLength: 0)
          ZStack {
            RoundedRectangle(cornerRadius: 29)
              .fill(Color.white)
            displayContent()
          }
          .fixedSize(horizontal: false, vertical: true)
          .modifier(
            SnapDraggingModifier(
              offset: $contentOffset, 
              axis: .vertical,
              verticalBoundary: .init(min: 0, max: .infinity, bandLength: 50),
              springParameter: .hard,
              handler: .init(
                onEndDragging: { velocity, offset, contentSize in

                  if velocity.dy > 50 || offset.height > (contentSize.width / 2) {
                    print("remove")
                    return .init(width: 0, height: contentSize.height)
                  } else {
                    print("stay")
                    return .zero
                  }
                })
            )
          )
//        }
//        .transition(.opacity.animation(.smooth))

      }
    }
  }

}

#Preview {

  struct Preview: View {

    @State var isPresented = false

    var body: some View {
      VStack {
        Button("Show") {
          isPresented.toggle()
        }
        Rectangle()
          .fill(Color.red)
          .modifier(
            SheetModifier(isPresented: $isPresented) {
              VStack {
                Text("Hello, World!")
                Text("Hello, World!")
                Text("Hello, World!")
                Text("Hello, World!")
              }
            }
          )
      }
    }
  }

  return Preview()

}


#Preview("Transition") {
  
  struct TransitionExample: View {
    @State var isPresented = false
    
    var body: some View {
      VStack {
        Button("Show") {
          isPresented.toggle()
        }
        if isPresented {
          Text("Hello, World!")
            .transition(.opacity.animation(.smooth))
        }
      }
    }
  }
  
  return TransitionExample()
}
