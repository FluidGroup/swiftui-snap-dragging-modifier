// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swiftui-snap-dragging-modifier",
  platforms: [.iOS(.v15)],
  products: [
    .library(
      name: "SwiftUISnapDraggingModifier",
      targets: ["SwiftUISnapDraggingModifier"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/FluidGroup/swiftui-support", from: "0.9.0"),
    .package(url: "https://github.com/FluidGroup/swift-rubber-banding", from: "1.0.0"),
    .package(url: "https://github.com/FluidGroup/swiftui-scrollview-interoperable-drag-gesture", from: "0.1.0")
  ],
  targets: [
    .target(
      name: "SwiftUISnapDraggingModifier",
      dependencies: [
        .product(name: "RubberBanding", package: "swift-rubber-banding"),
        .product(name: "SwiftUISupportSizing", package: "swiftui-support"),
        .product(name: "SwiftUISupportGeometryEffect", package: "swiftui-support"),
        .product(name: "SwiftUIScrollViewInteroperableDragGesture", package: "swiftui-scrollview-interoperable-drag-gesture"),
      ]
    ),
    .testTarget(
      name: "SnapDraggingModifierTests",
      dependencies: ["SwiftUISnapDraggingModifier"]
    ),
  ]
)
