# SwiftUI - SnapDraggingModifier 

This is a small package for SwiftUI that enables the creation of a draggable view and tracks the velocity of the dragging action for use in animations when the drag is released

## Examples

<img width=250 src="https://user-images.githubusercontent.com/1888355/236678103-a982706d-ea22-4773-9071-2246b855e353.gif" />

```swift
Circle()
  .fill(Color.blue)
  .frame(width: 100, height: 100)
  .modifier(SnapDraggingModifier())
```

