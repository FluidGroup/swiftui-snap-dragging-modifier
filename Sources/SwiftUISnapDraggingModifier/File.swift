import SwiftUI

public struct SheetModifier<DisplayContent: View>: ViewModifier {

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool

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
      if isPresented {
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

        }
        .transition(.opacity.animation(.smooth))

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

#Preview {
  struct SwipeAction: View {

    var body: some View {

      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.blue)
        .frame(width: nil, height: 50)
        .modifier(
          SnapDraggingModifier(
            axis: .horizontal,
            horizontalBoundary: .init(min: 0, max: .infinity, bandLength: 50),
            springParameter: .interpolation(mass: 1, stiffness: 1, damping: 1),
            handler: .init(onEndDragging: { velocity, offset, contentSize in

              print(velocity, offset, contentSize)

              if velocity.dx > 50 || offset.width > (contentSize.width / 2) {
                print("remove")
                return .init(width: contentSize.width, height: 0)
              } else {
                print("stay")
                return .zero
              }
            })
          )
        )
        .padding(.horizontal, 20)

    }

  }

  return SwipeAction()
}
