import SwiftUI
import SwiftUISupportSizing

public struct SheetModifier<DisplayContent: View>: ViewModifier {

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool
  @State var contentOffset: CGSize = .zero
  
  @State var contentSize: CGSize = .zero

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
          displayContent()
          .fixedSize(horizontal: false, vertical: true)
          .measureSize($contentSize)
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
          .onChange(of: isPresented) { isPresented in
            if isPresented {
              withAnimation(.spring(response: 0.45)) {
                contentOffset.height = 0
              }
            } else {
              
            }
          }
          .onChange(of: contentSize) { contentSize in
            print("contentSize: \(contentSize)")
            
            self.contentOffset.height = contentSize.height
          }
//        }
//        .transition(.opacity.animation(.smooth))

      }
    }
  }

}

#Preview {
  
  struct SheetContent: View {
    
    @State var isExpanded = false
    
    var body: some View {
      ZStack {
        RoundedRectangle(cornerRadius: 20)
          .fill(.background)
        HStack {
          VStack(alignment: .leading) {                            
            Text("This is a sheet")
              .font(.title)    
            VStack {
              Text("Hello, World!")
              Text("Hello, World!")
              Text("Hello, World!")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.secondary))
            
            if isExpanded {
              VStack {
                Text("Hello, World!")
                Text("Hello, World!")
                Text("Hello, World!")
              }
              .padding()
              .background(RoundedRectangle(cornerRadius: 20).fill(Color.secondary))
            }
            
            Button("Detail") {
              isExpanded.toggle()
            }
            .buttonBorderShape(.roundedRectangle)
          }
          Spacer(minLength: 0)
        }
        .padding()
      }
      .padding()
    }
  }

  struct Preview: View {

    @State var isPresented = false

    var body: some View {
      VStack {
        Button("Show") {
          isPresented.toggle()
        }
        Rectangle()
          .fill(Color.purple)      
          .ignoresSafeArea()
      }
      .modifier(
        SheetModifier(isPresented: $isPresented) {
          SheetContent()
        }
      )
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
