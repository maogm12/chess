import Foundation
import ImageIO

// Run from the project root to resize the supplied artwork without redrawing it.
let variants = [
    (source: "design/app-icon-light.jpg", output: "AppIcon.png"),
    (source: "design/app-icon-dark.jpg", output: "AppIcon-dark.png")
]
let outputDirectory = URL(fileURLWithPath: "ChessApp/Assets.xcassets/AppIcon.appiconset")
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 1024
]

for variant in variants {
    let sourceURL = URL(fileURLWithPath: variant.source)
    let outputURL = outputDirectory.appendingPathComponent(variant.output)
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          image.width == 1024, image.height == 1024,
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL, "public.png" as CFString, 1, nil
          ) else {
        fatalError("Cannot prepare 1024x1024 icon from \(variant.source)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Cannot write \(outputURL.path)")
    }
}
