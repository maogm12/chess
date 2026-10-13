import AppKit
// Deterministic vector drawing; run from the project root to regenerate the icon.
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSGradient(starting: NSColor(calibratedRed: 0.49, green: 0.59, blue: 0.68, alpha: 1),
           ending: NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.24, alpha: 1))!
    .draw(in: NSRect(origin: .zero, size: size), angle: -65)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 12
let knight = NSAttributedString(string: "♞", attributes: [
    .font: NSFont.systemFont(ofSize: 800),
    .foregroundColor: NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.94, alpha: 1),
    .shadow: shadow
])
let bounds = knight.size()
knight.draw(at: NSPoint(x: (1024 - bounds.width)/2, y: (1024 - bounds.height)/2 + 28))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "ChessApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
