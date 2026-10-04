// Renders Markfops/Resources/Assets.xcassets/AppIcon.appiconset and the README
// icon: scripts/icon-art.png (a pixel paw on beige, first made with icon.kitchen) in the
// ship skill's icon frame. Run: swift scripts/make-icon.swift

// MARK: - Icon frame (ship skill: references/icon-frame.swift)
// Copied verbatim into every app's scripts/make-icon.swift; never tune it per
// app, only the artwork differs. It reproduces icon.kitchen's macOS renderer,
// in 1024-pt canvas units: an 824-pt body (figma squircle, corner radius
// 22.5%, smoothing 0.61), a bevel of two inner shadows (white 44%, 4 down,
// σ 1; black 25%, 3 up, σ 2) and an outer shadow (black 25%, 14 down, σ 10).
import Accelerate
import AppKit

/// The body: icon.kitchen's squircle on the 824-pt grid, y up.
func iconBody() -> CGPath {
    let w: CGFloat = 824, r = 0.225 * w, smoothing: CGFloat = 0.61
    let rad = { (deg: CGFloat) in deg * .pi / 180 }
    // figma-squircle's corner: a bezier, a circular arc, a bezier.
    let p = (1 + smoothing) * r
    let arcMeasure = 90 * (1 - smoothing)
    let arc = sin(rad(arcMeasure / 2)) * r * sqrt(2)
    let c = r * tan(rad((90 - arcMeasure) / 4)) * cos(rad(45 * smoothing))
    let d = c * tan(rad(45 * smoothing))
    let b = (p - arc - c - d) / 3, a = 2 * b
    // y down, like figma-squircle. Each corner in its own frame: k the corner,
    // u along the edge coming in, v along the edge going out.
    let corners: [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] = [
        ((w, 0), (1, 0), (0, 1)), ((w, w), (0, 1), (-1, 0)),
        ((0, w), (-1, 0), (0, -1)), ((0, 0), (0, -1), (1, 0)),
    ]
    let path = CGMutablePath()
    for (i, (k, u, v)) in corners.enumerated() {
        let at = { (s: CGFloat, t: CGFloat) in
            CGPoint(x: k.0 + u.0 * (s - p) + v.0 * t, y: k.1 + u.1 * (s - p) + v.1 * t)
        }
        if i == 0 { path.move(to: at(0, 0)) } else { path.addLine(to: at(0, 0)) }
        path.addCurve(to: at(a + b + c, d), control1: at(a, 0), control2: at(a + b, 0))
        let s2 = a + b + c + arc, t2 = d + arc
        let o = at(p - r, r), from = at(a + b + c, d), to = at(s2, t2)
        path.addArc(center: o, radius: r, startAngle: atan2(from.y - o.y, from.x - o.x),
                    endAngle: atan2(to.y - o.y, to.x - o.x), clockwise: false)
        path.addCurve(to: at(p, p), control1: at(s2 + d, t2 + c), control2: at(s2 + d, t2 + b + c))
    }
    path.closeSubpath()
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 100, ty: 924)
    return path.copy(using: &flip)!
}

/// A plane moved down by `dy` pixels (up if negative), sub-pixel, zero-filled.
func iconShift(_ plane: [Float], _ px: Int, _ dy: Float) -> [Float] {
    let whole = Int(dy.rounded(.down)), f = dy - Float(whole)
    var out = [Float](repeating: 0, count: plane.count)
    for y in 0..<px {
        for (src, weight) in [(y - whole, 1 - f), (y - whole - 1, f)] where weight > 0 && (0..<px).contains(src) {
            for x in 0..<px { out[y * px + x] += weight * plane[src * px + x] }
        }
    }
    return out
}

/// A plane under a gaussian blur of standard deviation `sigma` pixels.
func iconBlur(_ plane: [Float], _ px: Int, _ sigma: Float) -> [Float] {
    let radius = Int((3 * sigma).rounded(.up))
    guard radius >= 1 else { return plane }
    var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
    let sum = kernel.reduce(0, +)
    kernel = kernel.map { $0 / sum }
    var src = plane, out = [Float](repeating: 0, count: plane.count)
    src.withUnsafeMutableBytes { s in
        out.withUnsafeMutableBytes { o in
            let n = vImagePixelCount(px)
            var from = vImage_Buffer(data: s.baseAddress, height: n, width: n, rowBytes: px * 4)
            var into = vImage_Buffer(data: o.baseAddress, height: n, width: n, rowBytes: px * 4)
            _ = vImageSepConvolve_PlanarF(&from, &into, nil, 0, 0, kernel, UInt32(kernel.count),
                                          kernel, UInt32(kernel.count), 0, 0, vImage_Flags(kvImageBackgroundColorFill))
        }
    }
    return out
}

/// The icon at `px` square, as PNG data. `art` paints the body in 1024-pt
/// coordinates, y up, already clipped to the body. The current
/// NSGraphicsContext is the same context, so AppKit drawing works too.
func renderIcon(_ px: Int, art: (CGContext) -> Void) -> Data {
    let n = px * px, s = Float(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
    ctx.addPath(iconBody())
    ctx.clip()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    art(ctx)
    NSGraphicsContext.restoreGraphicsState()
    // Premultiplied RGBA, rows top down.
    let bytes = ctx.data!.bindMemory(to: UInt8.self, capacity: n * 4)
    var rgba = (0..<n * 4).map { Float(bytes[$0]) / 255 }
    let alpha = (0..<n).map { rgba[$0 * 4 + 3] }
    for (color, opacity, dy, sigma) in [(Float(1), Float(0.44), Float(4), Float(1)), (0, 0.25, -3, 2)] {
        let cover = iconBlur(iconShift(alpha, px, dy * s), px, sigma * s)
        for i in 0..<n {
            let k = (1 - cover[i]) * opacity
            for ch in 0..<3 { rgba[i * 4 + ch] = rgba[i * 4 + ch] * (1 - k) + color * k * alpha[i] }
        }
    }
    let shadow = iconShift(iconBlur(alpha, px, 10 * s), px, 14 * s)
    for i in 0..<n { rgba[i * 4 + 3] += 0.25 * shadow[i] * (1 - rgba[i * 4 + 3]) }
    for i in 0..<n * 4 { bytes[i] = UInt8((min(max(rgba[i], 0), 1) * 255).rounded()) }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

/// The ten macOS icon images: file name and pixel size.
let macIconImages = [16, 32, 128, 256, 512].flatMap { pt in
    [1, 2].map { (name: "icon_\(pt)x\(pt)\($0 == 2 ? "@2x" : "").png", pt: pt, scale: $0) }
}

/// Writes an asset catalog .appiconset: the ten images and Contents.json.
func writeAppIconset(_ dir: URL, art: (CGContext) -> Void) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var entries: [String] = []
    for image in macIconImages {
        try! renderIcon(image.pt * image.scale, art: art).write(to: dir.appending(path: image.name))
        entries.append("""
                { "filename" : "\(image.name)", "idiom" : "mac", "scale" : "\(image.scale)x", "size" : "\(image.pt)x\(image.pt)" }
            """)
    }
    let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try! contents.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

/// Writes an .icns of the ten images, through iconutil.
func writeIcns(_ file: URL, art: (CGContext) -> Void) {
    let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for image in macIconImages {
        try! renderIcon(image.pt * image.scale, art: art).write(to: iconset.appending(path: image.name))
    }
    try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", file.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
}

/// Writes one PNG at `px` square, for a homepage or README.
func writePNG(_ file: URL, _ px: Int, art: (CGContext) -> Void) {
    try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! renderIcon(px, art: art).write(to: file)
}
// MARK: - End of icon frame

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let artwork = NSImage(contentsOf: root.appending(path: "scripts/icon-art.png"))!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!

func art(_ ctx: CGContext) {
    ctx.interpolationQuality = .high
    ctx.draw(artwork, in: CGRect(x: 100, y: 100, width: 824, height: 824))
}

let iconset = root.appending(path: "Markfops/Resources/Assets.xcassets/AppIcon.appiconset")
writeAppIconset(iconset, art: art)
writePNG(root.appending(path: ".github/assets/icon.png"), 512, art: art)
print(iconset.path)
