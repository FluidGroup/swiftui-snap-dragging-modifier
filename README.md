# SwiftUI - SnapDraggingModifier 

This is a small SwiftUI package that allows for the creation of a draggable view and tracks the velocity of the dragging action, which can be used to create fluid animations when the drag is released. This component is a big help in creating interactive user interfaces and enhancing their fluidity.

About Fluid interfaces : https://developer.apple.com/videos/play/wwdc2018/803/

> [UIKit Version](https://github.com/FluidGroup/FluidInterfaceKit) FluidInterfaceKit/FluidGesture module

## Examples

### Directional gesture ownership

Use `.directional` when a snap gesture should begin only after movement is
dominant on the modifier's existing `axis`. For example, a horizontal action
inside a vertical scrolling surface can reject vertical and equal-axis pans
before the row gesture begins:

```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
  .modifier(
    SnapDraggingModifier(
      gestureMode: .directional,
      offset: $offset,
      axis: [.horizontal],
      horizontalBoundary: .init(min: -50, max: 0, bandLength: 50)
    )
  )
```

`.directional` is available on iOS 18 and later. It is separate from
`.scrollViewInteroperable`, which coordinates edge handoff with a scroll view.
UIKit owns the pan-recognition threshold; `activation.minimumDistance` delays
offset and callback delivery after recognition rather than replacing that
system threshold.

**Throwing a ball**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678103-a982706d-ea22-4773-9071-2246b855e353.gif" />

```swift
Circle()
  .fill(Color.blue)
  .frame(width: 100, height: 100)
  .modifier(SnapDraggingModifier())
```

---

**Fixed draggable direction and rubber banding effect**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678569-fc91431a-33ec-48cb-a09f-f6b94fcb85c4.gif" />


```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
  .fill(Color.blue)
  .frame(width: 120, height: 50)
  .modifier(
    SnapDraggingModifier(
      axis: [.vertical],
      verticalBoundary: .init(min: -10, max: 10, bandLength: 50)
    )
  )
```

---

**Thowing to the point**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678943-e6cd9b26-0c5b-407a-8ed1-c1841254cc01.gif" />

"The modifier asks for the destination point when the gesture ends, and the view will smoothly move to the specified point with velocity-based animation."

```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
  .fill(Color.blue)
  .frame(width: nil, height: 50)
  .modifier(
    SnapDraggingModifier(
      axis: .horizontal,
      horizontalBoundary: .init(min: 0, max: .infinity, bandLength: 50),
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
```
