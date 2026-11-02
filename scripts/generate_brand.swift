// Deterministic DAYFUEL vector artwork. Run from the repository root with swift.
import AppKit

func render(size: Int, background: Bool, destination: String) throws {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: background ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.coderInvalidValue) }
    context.setAllowsAntialiasing(true)
    let scale = CGFloat(size)
    if background {
        context.setFillColor(CGColor(red: 0.055, green: 0.065, blue: 0.060, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    context.setFillColor(CGColor(red: 0.82, green: 0.98, blue: 0.39, alpha: 1))
    let inset = background ? 0.20 : 0.02
    let extent = 1 - inset * 2
    for (x, width, top, bottom) in [(0.06, 0.24, 0.26, 0.74), (0.36, 0.24, 0.10, 0.90), (0.66, 0.24, 0.26, 0.74)] {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (inset + x * extent) * scale, y: (1 - inset - y * extent) * scale)
        }
        let path = CGMutablePath()
        path.move(to: point(x + 0.12, top))
        path.addLine(to: point(x + width, top))
        path.addLine(to: point(x + width - 0.12, bottom))
        path.addLine(to: point(x, bottom))
        path.closeSubpath()
        context.addPath(path); context.fillPath()
    }
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: destination))
}
try render(size: 1024, background: true, destination: "Aurix/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try render(size: 256, background: false, destination: "Aurix/Resources/Assets.xcassets/AppMark.imageset/mark.png")
