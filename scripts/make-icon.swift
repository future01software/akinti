// Akıntı uygulama simgesini çizer: swift scripts/make-icon.swift <çıktı.png>
// macOS simge ızgarası: 1024 tuval, 824'lük gövde, yuvarlatılmış kare, alt gölge.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Gölge
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0, 0.05, 0.2, 0.45))
ctx.addPath(shape); ctx.setFillColor(color(0.1, 0.4, 0.8)); ctx.fillPath()
ctx.restoreGState()

// Gövde: üstte açık turkuaz-mavi, altta derin lacivert
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0.33, 0.80, 1.0), color(0.10, 0.45, 0.95), color(0.04, 0.16, 0.50)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Üstte yumuşak parıltı
let glow = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 0.35), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 900), startRadius: 0, endCenter: CGPoint(x: 380, y: 900), endRadius: 520, options: [])

// Akan dalgalar (akıntı)
func wave(y: CGFloat, amplitude: CGFloat, length: CGFloat, phase: CGFloat) -> CGPath {
    let p = CGMutablePath()
    var x: CGFloat = 40
    p.move(to: CGPoint(x: x, y: y + amplitude * sin(phase)))
    while x <= 990 {
        x += 6
        p.addLine(to: CGPoint(x: x, y: y + amplitude * sin((x / length) * 2 * .pi + phase)))
    }
    return p
}
ctx.setLineCap(.round)
for (i, (y, alpha)) in [(790.0, 0.16), (700.0, 0.24), (610.0, 0.32)].enumerated() {
    ctx.addPath(wave(y: y, amplitude: 26, length: 330, phase: CGFloat(i) * 1.1))
    ctx.setStrokeColor(color(1, 1, 1, alpha)); ctx.setLineWidth(30); ctx.strokePath()
}

// Alttaki su yüzeyi: okun indiği yer
let water = CGMutablePath()
water.addPath(wave(y: 250, amplitude: 22, length: 260, phase: 0.6))
water.addLine(to: CGPoint(x: 1000, y: 60)); water.addLine(to: CGPoint(x: 30, y: 60)); water.closeSubpath()
ctx.addPath(water); ctx.setFillColor(color(0.02, 0.10, 0.36, 0.55)); ctx.fillPath()
ctx.addPath(wave(y: 250, amplitude: 22, length: 260, phase: 0.6))
ctx.setStrokeColor(color(0.75, 0.95, 1, 0.9)); ctx.setLineWidth(18); ctx.strokePath()

// İndirme oku
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0.05, 0.25, 0.45))
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 512, y: 760)); arrow.addLine(to: CGPoint(x: 512, y: 330))
arrow.move(to: CGPoint(x: 340, y: 500)); arrow.addLine(to: CGPoint(x: 512, y: 328)); arrow.addLine(to: CGPoint(x: 684, y: 500))
ctx.addPath(arrow)
ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(112)
ctx.setStrokeColor(color(1, 1, 1)); ctx.strokePath()
ctx.restoreGState()

// İnce iç kenar çizgisi (cam hissi)
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(color(1, 1, 1, 0.18)); ctx.setLineWidth(3); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Simge yazıldı: \(out)")
