# SwiftUI - SnapDraggingModifier 

This is a small package for SwiftUI that enables the creation of a draggable view and tracks the velocity of the dragging action for use in animations when the drag is released

## Examples

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

![CleanShot 2023-05-07 at 21 47 30](https://user-images.githubusercontent.com/1888355/236678569-fc91431a-33ec-48cb-a09f-f6b94fcb85c4.gif)

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
