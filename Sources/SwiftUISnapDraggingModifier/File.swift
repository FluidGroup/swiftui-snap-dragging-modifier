import SwiftUI
import SwiftUISupportSizing

public struct SheetModifier<DisplayContent: View>: ViewModifier {

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool
  @State var contentOffset: CGSize = .zero

  @State var contentSize: CGSize = .zero
  @State var safeAreaInsets: EdgeInsets = .init()
  
  private var hidingOffset: CGFloat {
    (contentSize.height + safeAreaInsets.bottom)
  }
  
  private var animation: SnapDraggingModifier.SpringParameter {
//    .interpolation(mass: 1, stiffness: 1, damping: 1)
    return .hard
  }

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
      
      VStack {
        Spacer(minLength: 0)
        displayContent()
          .readingGeometry(
            transform: \.size,
            target: $contentSize
          )
          .fixedSize(horizontal: false, vertical: true)
          .modifier(
            SnapDraggingModifier(
              offset: $contentOffset,
              axis: .vertical,
              verticalBoundary: .init(min: 0, max: .infinity, bandLength: 50),
              springParameter: animation,
              handler: .init(
                onEndDragging: { velocity, offset, contentSize in

                  print(velocity, offset)
                  if velocity.dy > 50 || offset.height > (contentSize.width / 2) {
                    isPresented = false
                    return .init(width: 0, height: hidingOffset)
                  } else {
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
              withAnimation(.spring(response: 0.45)) {
                contentOffset.height = hidingOffset
              }
            }
          }
          .onChange(of: contentOffset) { contentOffset in

          }
      }
      .readingGeometry(
        transform: \.safeAreaInsets,
        target: $safeAreaInsets
      )    
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
            
            HStack {
              VStack {
                Text("Hello, World!")
                Text("Hello, World!")
                Text("Hello, World!")
              }
              .padding(10)
              .background(RoundedRectangle(cornerRadius: 10).fill(.tertiary))
              
              ScrollView {
                VStack {
                  ForEach(0..<50) { index in
                    Text("Hello, World!")
                  }
                }
              }
              .frame(height: 300)
            }
            
            ScrollView(.horizontal) {
              HStack {
                Text("Horizontal ScrollView")
                Text("Horizontal ScrollView")
                Text("Horizontal ScrollView")
              }
            }
            
            if isExpanded {
              VStack {
                Text("Hello, World!")
                Text("Hello, World!")
                Text("Hello, World!")
              }
              .padding(10)
              .background(RoundedRectangle(cornerRadius: 10).fill(.tertiary))
            }

            HStack {
              Spacer()
              Button("Detail") {
                withAnimation(.spring) {
                  isExpanded.toggle()
                }
              }
              .buttonBorderShape(.roundedRectangle)
            }
          }
          Spacer(minLength: 0)
        }
        .padding()
      }
      .clipped()
      .padding(8)
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
