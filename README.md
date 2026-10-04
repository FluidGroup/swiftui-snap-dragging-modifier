# SwiftUI - SnapDraggingModifier 

This is a small SwiftUI package that allows for the creation of a draggable view and tracks the velocity of the dragging action, which can be used to create fluid animations when the drag is released. This component is a big help in creating interactive user interfaces and enhancing their fluidity.

Requires iOS 18 or later. Both gesture modes use
`UIGestureRecognizerRepresentable`.

About Fluid interfaces : https://developer.apple.com/videos/play/wwdc2018/803/

> [UIKit Version](https://github.com/FluidGroup/FluidInterfaceKit) FluidInterfaceKit/FluidGesture module

## Examples

### Axes and boundaries

Specify both `horizontal` and `vertical` when creating the modifier. Each
optional `Boundary` controls direct dragging on that axis:

- `nil` disables direct dragging on the axis and preserves its current offset.
- `.infinity` enables unrestricted dragging.
- `.init(min:max:bandLength:)` adds rubber banding outside the specified range.

When both axes are `nil`, the modifier does not recognize a drag or deliver
dragging callbacks. Boundaries constrain direct manipulation; an offset
returned by `handler.onEndDragging` can still move both axes, including an axis
whose boundary is `nil`. Changing either boundary to `nil` during an active
drag cancels that drag using its mode's cancellation behavior.

`axis`, `horizontalBoundary`, and `verticalBoundary` have been replaced by
these two optional boundaries. The `.normal`, `.highPriority`, and
`.simultaneous` modes have been removed. Use `.directional` or
`.scrollViewInteroperable`.

### Directional gesture ownership

Use `.directional` when a snap gesture should begin only after movement is
dominant on its enabled axis. For example, a horizontal action
inside a vertical scrolling surface can reject vertical and equal-axis pans
before the row gesture begins. Enabling both axes allows pans in any direction.
`.directional` is the default mode:

```swift
@State var offset: CGSize = .zero

RoundedRectangle(cornerRadius: 16, style: .continuous)
  .modifier(
    SnapDraggingModifier(
      gestureMode: .directional,
      offset: $offset,
      horizontal: .init(min: -50, max: 0, bandLength: 50),
      vertical: nil
    )
  )
```

UIKit owns the pan-recognition threshold; `activation.minimumDistance` delays
offset and callback delivery after recognition rather than replacing that
system threshold.

### Scroll view handoff

Use `.scrollViewInteroperable` to coordinate dragging with a scroll view at
its edges. The configuration retains control of edge handoff, edge sticking,
and whether scroll views participate:

```swift
@State var offset: CGSize = .zero

ScrollView {
  // Scrollable content
}
.modifier(
  SnapDraggingModifier(
    gestureMode: .scrollViewInteroperable(
      .init(ignoresScrollView: false, targetEdges: .all, sticksToEdges: true)
    ),
    offset: $offset,
    horizontal: nil,
    vertical: .infinity
  )
)
```

In this mode, `activation.minimumDistance` delays outer offset and callback
delivery after handoff. It does not delay the recognizer's internal scroll
locking. Edges for disabled axes are excluded from handoff.

### Cancellation

After a drag starts, `.directional` cancellation returns the view to the most
recent snap target without calling `onEndDragging`.
`.scrollViewInteroperable` preserves its existing behavior: cancellation
finishes the drag through `onEndDragging`. A gesture rejected before activation
or ended before reaching `minimumDistance` delivers no dragging callbacks.

Changing axes, activation, layout direction, gesture mode, or scroll-view
configuration cancels the active pan. Disappearing content releases its native
pan and any scroll locking; reappearing content can recognize a new drag.

**Throwing a ball**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678103-a982706d-ea22-4773-9071-2246b855e353.gif" />

```swift
@State var offset: CGSize = .zero

Circle()
  .fill(Color.blue)
  .frame(width: 100, height: 100)
  .modifier(
    SnapDraggingModifier(
      offset: $offset,
      horizontal: .infinity,
      vertical: .infinity
    )
  )
```

---

**Fixed draggable direction and rubber banding effect**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678569-fc91431a-33ec-48cb-a09f-f6b94fcb85c4.gif" />


```swift
@State var offset: CGSize = .zero

RoundedRectangle(cornerRadius: 16, style: .continuous)
  .fill(Color.blue)
  .frame(width: 120, height: 50)
  .modifier(
    SnapDraggingModifier(
      offset: $offset,
      horizontal: nil,
      vertical: .init(min: -10, max: 10, bandLength: 50)
    )
  )
```

---

**Throwing to the point**

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678943-e6cd9b26-0c5b-407a-8ed1-c1841254cc01.gif" />

"The modifier asks for the destination point when the gesture ends, and the view will smoothly move to the specified point with velocity-based animation."

```swift
@State var offset: CGSize = .zero

RoundedRectangle(cornerRadius: 16, style: .continuous)
  .fill(Color.blue)
  .frame(width: nil, height: 50)
  .modifier(
    SnapDraggingModifier(
      offset: $offset,
      horizontal: .init(min: 0, max: .infinity, bandLength: 50),
      vertical: nil,
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
