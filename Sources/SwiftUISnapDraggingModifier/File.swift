import SwiftUI
import SwiftUISupportSizing

public struct BlanketModifier<DisplayContent: View>: ViewModifier {

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool
  @State var contentOffset: CGSize = .zero

  @State var contentSize: CGSize = .zero
  @State var safeAreaInsets: EdgeInsets = .init()
  
  private let onDismiss: (() -> Void)?

  private var hidingOffset: CGFloat {
    (contentSize.height + safeAreaInsets.bottom)
  }

  private var animation: SnapDraggingModifier.SpringParameter {
    //    .interpolation(mass: 1, stiffness: 1, damping: 1)
    return .hard
  }

  public init(
    isPresented: Binding<Bool>,
    onDismiss: (() -> Void)?,
    @ViewBuilder displayContent: @escaping () -> DisplayContent
  ) {
    self._isPresented = isPresented
    self.onDismiss = onDismiss
    self.displayContent = displayContent    
  }

  public func body(content: Content) -> some View {
    ZStack {
      content

      VStack {
        Spacer(minLength: 0)

        ZStack {
          displayContent()
            .onAppear(perform: {
              print("appear")
            })
        }
        .readingGeometry(
          transform: \.size,
          target: $contentSize
        )
        .fixedSize(horizontal: false, vertical: true)
        .modifier(
          SnapDraggingModifier(
            gestureMode: {
              if #available(iOS 18.0, *) {
                return .scrollViewInteroperable(
                  .init(ignoresScrollView: false, sticksToEdges: true)
                )
              } else {
                return .normal
              }
            }(),
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
        .onChange(of: hidingOffset) { hidingOffset in
          if isPresented == false {
            self.contentOffset.height = hidingOffset
          }
        }
      }
      .readingGeometry(
        transform: \.safeAreaInsets,
        target: $safeAreaInsets
      )
    }
  }

}

extension View {

  public func blanket<Item, Content>(
    item: Binding<Item?>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View where Item: Identifiable, Content: View {

    self.modifier(
      BlanketModifier(
        isPresented: .init(
          get: { item.wrappedValue != nil },
          set: { if !$0 { item.wrappedValue = nil } }
        ),
        onDismiss: onDismiss,
        displayContent: {
          if let item = item.wrappedValue {
            content(item)
          }       
        }
      )
    )

  }

  public func blanket<Content>(
    isPresented: Binding<Bool>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View where Content: View {

    self.modifier(
      BlanketModifier(isPresented: isPresented, onDismiss: onDismiss, displayContent: content)
    )

  }

}

#if DEBUG

struct SheetContent: View {
  
  @State var isExpanded = false
  
  private let title: String
  
  init(title: String) {
    self.title = title
  }
  
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 20)
        .fill(.background)
      HStack {
        VStack(alignment: .leading) {
          
          Text(title)
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

#Preview("isPresented") {


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
      .blanket(isPresented: $isPresented) {
        SheetContent(title: "This is a blanket")
      }
    }
  }

  return Preview()

}

#Preview("item") {
  
  struct Item: Identifiable {
    let id = UUID()
    let title: String
  }
  
  struct Preview: View {
    
    @State var item: Item?
    
    var body: some View {
      VStack {
        Button("Show A") {
          item = .init(title: "This is a blanket A")
        }
        Button("Show B") {
          item = .init(title: "This is a blanket B")
        }
        Button("Show C") {
          item = .init(title: "This is a blanket C")
        }
        Rectangle()
          .fill(Color.purple)
          .ignoresSafeArea()
      }
      .blanket(item: $item) { item in
        SheetContent(title: item.title)
      }
    }
  }
  
  return Preview()
}

#endif


