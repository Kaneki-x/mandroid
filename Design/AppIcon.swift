import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments[1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
func gradient(_ c: [UInt32], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: c.map { color($0) } as CFArray, locations: locs)!
}

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// macOS icon grid: 824 px squircle centred on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 824 * 0.2237
let bodyPath = rr(body, radius)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x151B2B)); ctx.fillPath()
ctx.restoreGState()

// Screen: dark slate gradient (window content)
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([0x243247, 0x151B2B], [0, 1]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
// Subtle diagonal sheen
ctx.drawLinearGradient(gradient([0xFFFFFF, 0xFFFFFF], [0, 1]).self,
                       start: .zero, end: .zero, options: [])
let sheen = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY), options: [])

// Title bar
let barH: CGFloat = 158
let bar = CGRect(x: body.minX, y: body.maxY - barH, width: body.width, height: barH)
ctx.drawLinearGradient(gradient([0xF4F5F8, 0xE3E6EC], [0, 1]),
                       start: CGPoint(x: 0, y: bar.maxY), end: CGPoint(x: 0, y: bar.minY), options: [])
ctx.setFillColor(color(0xC9CED8)); ctx.fill(CGRect(x: bar.minX, y: bar.minY - 3, width: bar.width, height: 3))

// Traffic lights
let lights: [UInt32] = [0xFF5F57, 0xFEBC2E, 0x28C840]
let rings: [UInt32] = [0xE0443E, 0xDEA123, 0x1AAB29]
for (i, c) in lights.enumerated() {
    let cx = body.minX + 96 + CGFloat(i) * 78, cy = bar.midY, r: CGFloat = 26
    ctx.setFillColor(color(rings[i])); ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    ctx.setFillColor(color(c)); ctx.fillEllipse(in: CGRect(x: cx - r + 3, y: cy - r + 3, width: 2 * r - 6, height: 2 * r - 6))
}
ctx.restoreGState()

// Android head (green dome + antennae + eyes) centred in the screen area
let screen = CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height - barH)
let green = color(0x3DDC84)
let domeW: CGFloat = 470, domeR = domeW / 2
let domeCenter = CGPoint(x: screen.midX, y: screen.midY - 70)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x3DDC84, 0.35))
ctx.setFillColor(green)
// dome: top half circle with a flat bottom, slightly rounded corners
let dome = CGMutablePath()
dome.move(to: CGPoint(x: domeCenter.x - domeR, y: domeCenter.y))
dome.addArc(center: domeCenter, radius: domeR, startAngle: .pi, endAngle: 0, clockwise: true)
dome.addLine(to: CGPoint(x: domeCenter.x + domeR, y: domeCenter.y - 34))
dome.addArc(center: CGPoint(x: domeCenter.x + domeR - 22, y: domeCenter.y - 34), radius: 22, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
dome.addLine(to: CGPoint(x: domeCenter.x - domeR + 22, y: domeCenter.y - 56))
dome.addArc(center: CGPoint(x: domeCenter.x - domeR + 22, y: domeCenter.y - 34), radius: 22, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
dome.closeSubpath()
ctx.addPath(dome); ctx.fillPath()
// antennae
ctx.setStrokeColor(green); ctx.setLineWidth(26); ctx.setLineCap(.round)
for sgn: CGFloat in [-1, 1] {
    let a: CGFloat = .pi / 2 + sgn * 0.62
    let p0 = CGPoint(x: domeCenter.x + cos(a) * (domeR - 20), y: domeCenter.y + sin(a) * (domeR - 20))
    let p1 = CGPoint(x: domeCenter.x + cos(a) * (domeR + 88), y: domeCenter.y + sin(a) * (domeR + 88))
    ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
}
ctx.restoreGState()
// eyes
ctx.setFillColor(color(0x151B2B))
for sgn: CGFloat in [-1, 1] {
    let e = CGPoint(x: domeCenter.x + sgn * 108, y: domeCenter.y + 84), r: CGFloat = 26
    ctx.fillEllipse(in: CGRect(x: e.x - r, y: e.y - r, width: 2 * r, height: 2 * r))
}
// eye highlights
ctx.setFillColor(color(0xFFFFFF, 0.9))
for sgn: CGFloat in [-1, 1] {
    let e = CGPoint(x: domeCenter.x + sgn * 108 + 9, y: domeCenter.y + 84 + 9), r: CGFloat = 7
    ctx.fillEllipse(in: CGRect(x: e.x - r, y: e.y - r, width: 2 * r, height: 2 * r))
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
