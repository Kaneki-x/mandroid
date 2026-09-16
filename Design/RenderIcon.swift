import AppKit

// Render Apple's full-resolution glass composite once, then derive the legacy
// sizes from that image. The preview bundle contains only Assets.car so a
// smaller ICNS compatibility image cannot take precedence over the catalog.
let bundle = Bundle(path: CommandLine.arguments[1])!
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
    guard let icon = bundle.image(forResource: "AppIcon") else { fatalError("Compiled AppIcon is missing") }
    let full = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: full)
    icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    guard let pixels = full.bitmapData,
          stride(from: 3, to: full.bytesPerRow * full.pixelsHigh, by: 4).contains(where: { pixels[$0] > 0 }) else {
        fatalError("Compiled icon rendered transparent; no PNGs were exported")
    }
    guard let composite = full.cgImage else { fatalError("Icon render failed") }
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(composite, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try! bitmap.representation(using: .png, properties: [:])!.write(
            to: destination.appendingPathComponent("icon_\(size).png"))
    }
}
