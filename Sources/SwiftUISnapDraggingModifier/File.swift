import RubberBanding
import SwiftUI
import SwiftUIScrollViewInteroperableDragGesture
import SwiftUISupportSizing
import os.log

enum Log {

  static func debug(_ values: Any...) {
    #if DEBUG
      let date = Date().formatted(.iso8601)
    print("[\(date)] \(values.map { "\($0)" }.joined(separator: " "))")
    #endif
  }

}

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

private struct Resolved {
  
  let detents: [BlancketDetent.Resolved]
  
  var maxDetent: BlancketDetent.Resolved {
    detents.last!
  }
  
  var minDetent: BlancketDetent.Resolved! {
    detents.first
  }
  
  func nearestDetent(to offset: CGFloat) -> BlancketDetent.Resolved {
    detents.min {
      abs($0.offset - offset) < abs($1.offset - offset)
    }!
  }
  
}

@available(iOS 18.0, *)
public struct BlanketModifier<DisplayContent: View>: ViewModifier {
    
  private let displayContent: () -> DisplayContent
  @Binding var isPresented: Bool

  @State private var contentOffset: CGSize = .zero
  @State private var presentingContentOffset: CGSize = .zero
  @State private var targetOffset: CGSize = .zero

  @State private var contentSize: CGSize?
  @State private var maximumSize: CGSize?
  @State private var safeAreaInsets: EdgeInsets = .init()
  
  @State var customHeight: CGFloat?

  private let onDismiss: (() -> Void)?

  //  private var hidingOffset: CGFloat {
  //    (contentSize.height + safeAreaInsets.bottom)
  //  }

  @State private var hidingOffset: CGFloat = 0
  
  @State private var resolved: Resolved?

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

          VStack {

            Spacer()
              .layoutPriority(1)

            displayContent()
              .readingGeometry(
                transform: \.size,
                target: $contentSize
              )
              .frame(height: customHeight)

          }

        }

      }

      .background(
        Color.clear.readingGeometry(
          transform: \.size,
          target: $maximumSize
        )
      )
//      .contentShape(Rectangle())

      // make this draggable
      .gesture(_gesture(configuration: .init(ignoresScrollView: false, sticksToEdges: true)))
      ._animatableOffset(y: contentOffset.height, presenting: $presentingContentOffset.height)

      #if false
      .background(Color(white: 0, opacity: isPresented ? 0.2 : 0))
      #endif
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
        guard let contentSize else { return }
        guard customHeight == nil else { return }
        resolve(contentSize: contentSize)
      }
      .onChange(of: hidingOffset) { hidingOffset in
        if isPresented == false {
          // init
          self.contentOffset.height = hidingOffset
        }
      }
    }
  }

  private func resolve(contentSize: CGSize) {

    Log.debug("resolve")

    let context = BlancketDetent.Context(
      maxDetentValue: maximumSize?.height ?? 0,
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

    hidingOffset = hiddenDetent.offset

    self.resolved = .init(detents: resolved)

  }

  @available(iOS 18.0, *)
  @available(macOS, unavailable)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  @available(visionOS, unavailable)
  private func _gesture(
    configuration: ScrollViewInteroperableDragGesture.Configuration
  )
    -> ScrollViewInteroperableDragGesture
  {

    let baseOffset = presentingContentOffset
    let baseCustomHeight = customHeight ?? contentSize?.height ?? 0

    return ScrollViewInteroperableDragGesture(
      configuration: configuration,
      coordinateSpaceInDragging: .named(_CoordinateSpaceTag.transition),
      onChange: { value in

        onChange(
          baseOffset: baseOffset,
          baseCustomHeight: baseCustomHeight,
          translation: value.translation
        )

      },
      onEnd: { value in
        onEnd(
          velocity: .init(
            dx: value.velocity.width,
            dy: value.velocity.height
          )
        )
      }
    )
  }

  private func onChange(
    baseOffset: CGSize,
    baseCustomHeight: CGFloat,
    translation: CGSize
  ) {
    
    guard let resolved else { return }
    
    let proposedHeight = baseCustomHeight - translation.height

    let lowestDetent = resolved.minDetent.offset
    let highestDetent = resolved.maxDetent.offset

    if proposedHeight < lowestDetent {

      // moving view

      Log.debug("Use intrinsict height")

      customHeight = nil

      let proposedOffset = CGSize(
        width: baseOffset.width + translation.width,
        height: baseOffset.height + translation.height
      )

      withAnimation(.interactiveSpring()) {

        contentOffset.height = rubberBand(
          value: proposedOffset.height,
          min: 0,
          max: .infinity,
          bandLength: 50
        )

      }

    } else if proposedHeight > highestDetent {

      Log.debug("reached max")
      customHeight = highestDetent

    } else {

      // stretching view
      Log.debug("Use custom height")
      contentOffset.height = 0
      customHeight = proposedHeight
    }

  }

  private func onEnd(velocity: CGVector) {
    
    guard let resolved else { return }
        
    if let customHeight {
      Log.debug("End - stretching")
            
      let nearest = resolved.nearestDetent(to: customHeight)
      
      Log.debug("\(nearest)")
            
      let distance = CGSize(
        width: 0,
        height: nearest.offset - customHeight
      )
      
      let mappedVelocity = CGVector(
        dx: velocity.dx / distance.width,
        dy: velocity.dy / distance.height
      )
      
      var animationY: Animation {
        .interpolatingSpring(
          mass: 1,
          stiffness: 200,
          damping: 20,
          initialVelocity: -mappedVelocity.dy
        )
      }
      
      if #available(iOS 17.0, *) {
        
        withAnimation(animationY) {
          self.customHeight = nearest.offset
        } completion: {
          
        }
        
      } else {
        
        withAnimation(
          animationY
        ) {
          self.customHeight = nearest.offset
        }
      }
            
    } else {
      
      Log.debug("End - moving", velocity.dy, contentOffset.height)
      
      let targetOffset: CGSize
      
      if velocity.dy > 50 || contentOffset.height > 50 {
        targetOffset = .init(width: 0, height: hidingOffset)
      } else {
        targetOffset = .zero
      }
                      
      self.targetOffset = targetOffset
                  
      let distance = CGSize(
        width: targetOffset.width - contentOffset.width,
        height: targetOffset.height - contentOffset.height
      )
      
      let mappedVelocity = CGVector(
        dx: velocity.dx / distance.width,
        dy: velocity.dy / distance.height
      )
      
      var animationY: Animation {
        .interpolatingSpring(
          mass: 1,
          stiffness: 200,
          damping: 20,
          initialVelocity: mappedVelocity.dy
        )
      }
      
      if #available(iOS 17.0, *) {
        
        withAnimation(animationY) {
          contentOffset.height = targetOffset.height
        } completion: {
          
        }
        
      } else {
        
        withAnimation(
          animationY
        ) {
          contentOffset.height = targetOffset.height
        }
      }    
  
    }

  }

}

private enum _CoordinateSpaceTag: Hashable {
  case pointInView
  case transition
}

@available(iOS 18.0, *)
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
        RoundedRectangle(cornerRadius: 20).fill(.background)
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
        .background(Color.red)
      }
      .clipped()
      .padding(8)
    }
  }

  @available(iOS 18.0, *)#Preview("isPresented"){

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

  @available(iOS 18.0, *)#Preview("item"){

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
          SheetContent(
            title: item.title
          )
        }
      }
    }

    return Preview()
  }

#endif

@available(iOS 16.0, *)#Preview("Sheet"){
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
