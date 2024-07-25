import SwiftUI
import SwiftUISupportSizing
import os.log

public struct BlancketDetent: Hashable {
  
  struct Context {
    let maxDetentValue: CGFloat
    let contentHeight: CGFloat
  }
  
  enum Node: Hashable {
    
    case fraction(CGFloat)
    case height(CGFloat)
    case content    
  }
  
  struct Resolved: Hashable {
    
    let source: BlancketDetent
    let offset: CGFloat
    
  }
  
  let node: Node
  
  public static func height(_ height: CGFloat) -> Self {
    .init(node: .height(height))
  }
  
  public static func fraction(_ fraction: CGFloat) -> Self {
    .init(node: .fraction(fraction))
  }
  
  public static var content: Self {
    .init(node: .content)
  }
      
  func resolve(in context: Context) -> CGFloat {
    switch node {
    case .content:
      return context.contentHeight
    case .fraction(let fraction):
      return context.maxDetentValue * fraction
    case .height(let height):
      return min(height, context.maxDetentValue)
    }
  }
  
}

public struct BlanketConfiguration {
  
  public struct Inline {
    
    public init() {
      
    }
  }
  
  public struct Presentation {
    
    public let backgroundColor: Color
    
    public init(
      backgroundColor: Color
    ) {
      self.backgroundColor = backgroundColor
    }
  }
  
  public enum Mode {
    case inline(Inline)
    case presentation(Presentation)
  }
  
  public let mode: Mode
  
  public init(mode: Mode) {
    self.mode = mode
  }
  
}

public struct BlanketModifier<DisplayContent: View>: ViewModifier {    

  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool
  @State var contentOffset: CGSize = .zero

  @State var contentSize: CGSize = .zero
  @State var safeAreaInsets: EdgeInsets = .init()
  
  private let onDismiss: (() -> Void)?

//  private var hidingOffset: CGFloat {
//    (contentSize.height + safeAreaInsets.bottom)
//  }
  
  @State var hidingOffset: CGFloat = 0

  private var animation: SnapDraggingModifier.SpringParameter {
    //    .interpolation(mass: 1, stiffness: 1, damping: 1)
    return .hard
  }
  
  private let detents: Set<BlancketDetent>

  public init(
    isPresented: Binding<Bool>,
    onDismiss: (() -> Void)?,
    @ViewBuilder displayContent: @escaping () -> DisplayContent
  ) {
    self._isPresented = isPresented
    self.onDismiss = onDismiss
    self.displayContent = displayContent    
    
    self.detents = .init([.content, .fraction(0.8), .fraction(1)])
  }

  public func body(content: Content) -> some View {
    ZStack {
      content

      VStack {
        Spacer(minLength: 0)

        ZStack {
          displayContent()
        }
        .readingGeometry(
          transform: \.size,
          target: $contentSize
        )
        .fixedSize(horizontal: false, vertical: true)
            
      }

      .contentShape(Rectangle())
      
      // make this draggable
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
          verticalBoundary: .init(min: .infinity * -1, max: .infinity, bandLength: 50),
          springParameter: animation,
          handler: .init(
            onEndDragging: { velocity, offset, contentSize in
              
              print(offset.height)
              
              if velocity.dy > 50 || offset.height > (contentSize.width / 2) {
                isPresented = false
                return .init(width: 0, height: hidingOffset)
              } else {
                return .zero
              }
            })
        )
      )
      
      .background(Color(white: 0, opacity: isPresented ? 0.2 : 0))
      .animation(.smooth, value: isPresented)
      .readingGeometry(
        transform: \.safeAreaInsets,
        target: $safeAreaInsets
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
      .onChange(of: contentSize) { contentSize in                
        resolve(contentSize: contentSize)
      }
      .onChange(of: hidingOffset) { hidingOffset in
        if isPresented == false {
          // init          
          print("Init", hidingOffset)
          self.contentOffset.height = hidingOffset
        }
      }
    }
  }
  
  private func resolve(contentSize: CGSize) {
    
    let context = BlancketDetent.Context(
      maxDetentValue: contentSize.height + safeAreaInsets.bottom,
      contentHeight: contentSize.height
    )
    
    let resolved = detents.map {
      let height = $0.resolve(in: context)
      return BlancketDetent.Resolved(
        source: $0,
        offset: $0.resolve(in: context)
      )
    }
      .sorted(by: { $0.offset < $1.offset })
    
    let hiddenDetent = BlancketDetent.Resolved(
      source: .fraction(0),
      offset: (contentSize.height + safeAreaInsets.bottom)
    )
            
    print(resolved.map { $0.offset }, hidingOffset)
        
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

@available(iOS 16.0, *)
#Preview("Sheet") {
  struct ContentView: View {
    @State private var showSettings = false
    
    
    var body: some View {
      Button("View Settings") {
        showSettings = true
      }
      .sheet(isPresented: $showSettings) {
        SheetContent(title: "Standard")
          .presentationDetents([.medium, .fraction(0.2), .large])
      }
    }
  }
  
  return ContentView()
}
