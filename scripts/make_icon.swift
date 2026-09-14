import AppKit

// Dark terminal with a green ">_" prompt. Rounded square badge, navy
// background, chevron + cursor. AppKit/CoreGraphics only, no external asset.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    // macOS app icons keep ~10% transparent margin around the badge so they sit
    // at the same visual size as system icons in the Dock and Cmd-Tab switcher.
    let inset = size * 0.10
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.22
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0x0f/255, green: 0x17/255, blue: 0x2a/255, alpha: 1),
        NSColor(calibratedRed: 0x1e/255, green: 0x1b/255, blue: 0x4b/255, alpha: 1)
    ])?.draw(in: bg, angle: -45)

    let chevron = NSAttributedString(string: "❯", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: rect.width * 0.42, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0x28/255, green: 0xc8/255, blue: 0x40/255, alpha: 1)
    ])
    chevron.draw(at: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.30))

    let cursor = NSBezierPath(rect: CGRect(
        x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.34,
        width: rect.width * 0.22, height: rect.height * 0.06
    ))
    NSColor(calibratedRed: 0x5a/255, green: 0xa9/255, blue: 0xe6/255, alpha: 1).setFill()
    cursor.fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for s: CGFloat in [16, 32, 64, 128, 256, 512, 1024] {
    savePNG(drawIcon(size: s), to: "\(outDir)/icon_\(Int(s)).png")
}
print("icons written to \(outDir)")
