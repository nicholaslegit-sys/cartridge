import AppKit

extension System {
    /// Systems whose games come in disc cases, which the 3D shelf shows.
    var isDisc: Bool {
        switch self {
        case .ps1, .ps2, .ps3, .ps4, .psp, .gamecube, .wii, .dreamcast, .saturn, .xbox: true
        default: false
        }
    }
}

/// Real-world case dimensions (metres) and colours per system.
struct CaseSpec {
    var width: CGFloat
    var height: CGFloat
    var depth: CGFloat
    var plastic: NSColor
    var band: NSColor
    var bandText: String
    var bandTextColor: NSColor = .white
    var discRadius: CGFloat = 0.06
    var discUnderside = NSColor(white: 0.78, alpha: 1)

    static func of(_ system: System) -> CaseSpec {
        let black = NSColor(white: 0.045, alpha: 1)
        let dvd = (w: 0.135, h: 0.190, d: 0.014)
        let bluRay = (w: 0.135, h: 0.171, d: 0.012)
        let jewel = (w: 0.142, h: 0.125, d: 0.0104)
        switch system {
        case .ps1:
            return CaseSpec(width: jewel.w, height: jewel.h, depth: jewel.d, plastic: black, band: black, bandText: "PlayStation", discUnderside: NSColor(white: 0.06, alpha: 1))
        case .ps2:
            return CaseSpec(width: dvd.w, height: dvd.h, depth: dvd.d, plastic: black, band: black, bandText: "PlayStation 2", discUnderside: NSColor(red: 0.30, green: 0.36, blue: 0.62, alpha: 1))
        case .ps3:
            return CaseSpec(width: bluRay.w, height: bluRay.h, depth: bluRay.d, plastic: NSColor(red: 0.10, green: 0.13, blue: 0.19, alpha: 1), band: black, bandText: "PS3")
        case .ps4:
            return CaseSpec(width: bluRay.w, height: bluRay.h, depth: bluRay.d, plastic: NSColor(red: 0.03, green: 0.20, blue: 0.55, alpha: 1), band: NSColor(red: 0.0, green: 0.26, blue: 0.68, alpha: 1), bandText: "PS4")
        case .psp:
            return CaseSpec(width: 0.104, height: 0.174, depth: 0.014, plastic: NSColor(white: 0.10, alpha: 1), band: black, bandText: "PSP", discRadius: 0.03)
        case .gamecube:
            return CaseSpec(width: dvd.w, height: dvd.h, depth: dvd.d, plastic: black, band: NSColor(red: 0.33, green: 0.25, blue: 0.62, alpha: 1), bandText: "GAMECUBE", discRadius: 0.04)
        case .wii:
            return CaseSpec(width: dvd.w, height: dvd.h, depth: dvd.d, plastic: NSColor(white: 0.93, alpha: 1), band: NSColor(white: 0.96, alpha: 1), bandText: "Wii", bandTextColor: NSColor(white: 0.45, alpha: 1))
        case .xbox:
            return CaseSpec(width: dvd.w, height: dvd.h, depth: dvd.d, plastic: black, band: NSColor(red: 0.36, green: 0.66, blue: 0.10, alpha: 1), bandText: "XBOX")
        case .dreamcast:
            return CaseSpec(width: jewel.w, height: jewel.h, depth: jewel.d, plastic: NSColor(white: 0.12, alpha: 1), band: NSColor(red: 0.93, green: 0.42, blue: 0.10, alpha: 1), bandText: "Dreamcast")
        case .saturn:
            return CaseSpec(width: jewel.w, height: jewel.h, depth: jewel.d, plastic: black, band: NSColor(white: 0.18, alpha: 1), bandText: "SEGA SATURN")
        default:
            return CaseSpec(width: dvd.w, height: dvd.h, depth: dvd.d, plastic: black, band: black, bandText: system.short)
        }
    }
}

/// SplitMix64, seeded from a game's id so its scuffs look the same every time.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(_ id: UUID, salt: UInt64 = 0) {
        state = withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) } ^ salt
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat.random(in: 0...1, using: &self) }
}

/// Everything painted onto the 3D cases. Pure CoreGraphics, safe off the main thread.
enum ShelfArt {
    static let pixelsPerMetre: CGFloat = 5400

    static func canvas(_ width: CGFloat, _ height: CGFloat, _ draw: (CGContext, CGRect) -> Void) -> CGImage {
        let w = max(Int(width.rounded()), 4), h = max(Int(height.rounded()), 4)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx, CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// Colour maths in sRGB; NSColor's own helpers throw on grey or catalogue colours.
    static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let x = a.usingColorSpace(.sRGB) ?? .black, y = b.usingColorSpace(.sRGB) ?? .black
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t, alpha: 1)
    }

    static func brightness(_ color: NSColor) -> CGFloat {
        (color.usingColorSpace(.sRGB) ?? .black).brightnessComponent
    }

    /// Decodes an image file at no more than `maxPixels` on its long side. Thread-safe.
    static func load(_ url: URL, maxPixels: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Splits a full wrap-around scan (back | spine | front) using the case's proportions.
    static func splitFullCover(_ full: CGImage, spec: CaseSpec) -> (back: CGImage, spine: CGImage, front: CGImage)? {
        let w = CGFloat(full.width), h = CGFloat(full.height)
        guard w > h else { return nil }
        var spine = w - 2 * (h * spec.width / spec.height)
        // Scans are rarely trimmed exactly; if the maths gives something implausible, use a typical spine share.
        if spine < w * 0.02 || spine > w * 0.2 { spine = w * spec.depth / (2 * spec.width + spec.depth) }
        let face = (w - spine) / 2
        guard let back = full.cropping(to: CGRect(x: 0, y: 0, width: face, height: h).integral),
              let middle = full.cropping(to: CGRect(x: face, y: 0, width: spine, height: h).integral),
              let front = full.cropping(to: CGRect(x: face + spine, y: 0, width: w - face - spine, height: h).integral)
        else { return nil }
        return (back, middle, front)
    }

    /// Everything printed on a game's case, from its scans where it has them.
    struct Scans {
        var front: CGImage?
        var back: CGImage?
        var spine: CGImage?
        var disc: CGImage?
        var title: CGImage?

        /// `spineOnly` skips everything but the spine (and the front, if `withFront`), for cases standing on the shelf.
        init(game: Game, spec: CaseSpec, spineOnly: Bool = false, withFront: Bool = false) {
            let full = ShelfArt.load(game.artFile(.full)).flatMap { ShelfArt.splitFullCover($0, spec: spec) }
            spine = ShelfArt.load(game.artFile(.spine), maxPixels: 1024) ?? full?.spine
            if !spineOnly || withFront { front = ShelfArt.load(game.artFile(.front)) ?? full?.front }
            guard !spineOnly else { return }
            back = ShelfArt.load(game.artFile(.back)) ?? full?.back
            disc = ShelfArt.load(game.artFile(.disc))
            title = ShelfArt.load(game.artFile(.title), maxPixels: 1024)
        }
    }

    static func cgImage(_ image: NSImage?) -> CGImage? {
        image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Draws `image` scaled to cover `rect`, cropping the overflow.
    static func fill(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    static func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let height = attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin]).height
        attributed.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func averageColor(_ image: CGImage) -> NSColor {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        var sum = [CGFloat](repeating: 0, count: 3)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for c in 0..<3 { sum[c] += CGFloat(pixels[i + c]) }
        }
        let n = CGFloat(side * side * 255)
        return NSColor(srgbRed: sum[0] / n, green: sum[1] / n, blue: sum[2] / n, alpha: 1)
    }

    /// Scratches, scuffed patches, specks and worn edges, as years in a shelf would leave.
    static func scuffs(_ ctx: CGContext, _ rect: CGRect, _ rng: inout SeededRandom, amount: CGFloat = 1) {
        let area = rect.width * rect.height / 500_000
        ctx.saveGState()
        ctx.setLineCap(.round)
        for _ in 0..<Int(70 * area * amount + 12) {
            let start = CGPoint(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height)
            let angle = rng.unit() * .pi * 2
            let length = 6 + rng.unit() * rng.unit() * 90
            let bend = (rng.unit() - 0.5) * length * 0.4
            let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            let control = CGPoint(x: (start.x + end.x) / 2 - sin(angle) * bend, y: (start.y + end.y) / 2 + cos(angle) * bend)
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.05 + rng.unit() * 0.22).cgColor)
            ctx.setLineWidth(0.5 + rng.unit() * 1.3)
            ctx.move(to: start)
            ctx.addQuadCurve(to: end, control: control)
            ctx.strokePath()
        }
        for _ in 0..<Int(6 * area * amount + 2) {
            let center = CGPoint(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height)
            let radius = 20 + rng.unit() * 70
            let gradient = CGGradient(colorsSpace: nil, colors: [NSColor(white: 1, alpha: 0.07 * amount).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        for _ in 0..<Int(160 * area * amount + 20) {
            let dot = CGRect(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height, width: 1 + rng.unit() * 2, height: 1 + rng.unit() * 2)
            ctx.setFillColor(NSColor(white: rng.unit() > 0.5 ? 1 : 0, alpha: 0.10 + rng.unit() * 0.25).cgColor)
            ctx.fillEllipse(in: dot)
        }
        // Edge wear: the corners and rims rub first.
        for _ in 0..<3 {
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.05 + rng.unit() * 0.08 * amount).cgColor)
            ctx.setLineWidth(1 + rng.unit() * 3)
            ctx.stroke(rect.insetBy(dx: rng.unit() * 3, dy: rng.unit() * 3))
        }
        ctx.restoreGState()
    }

    /// Clear-coat roughness: smooth plastic, rougher where it is scratched.
    static func roughness(_ id: UUID) -> CGImage {
        var rng = SeededRandom(id, salt: 7)
        return canvas(512, 512) { ctx, rect in
            ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
            ctx.fill(rect)
            scuffs(ctx, rect, &rng, amount: 1.4)
        }
    }

    static func placeholderCover(_ ctx: CGContext, _ rect: CGRect, game: Game, spec: CaseSpec) {
        let color = NSColor(game.system.color)
        let gradient = CGGradient(colorsSpace: nil, colors: [color.cgColor, mix(color, .black, 0.65).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        text(game.title, in: rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.25), size: rect.width * 0.11, weight: .heavy, color: .white)
    }

    static func header(_ ctx: CGContext, _ rect: CGRect, spec: CaseSpec) -> CGRect {
        let band = CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.075, width: rect.width, height: rect.height * 0.075)
        ctx.setFillColor(spec.band.cgColor)
        ctx.fill(band)
        text(spec.bandText, in: band.insetBy(dx: band.width * 0.05, dy: 0), size: band.height * 0.5, weight: .semibold, color: spec.bandTextColor, alignment: .left)
        return band
    }

    // MARK: Case faces

    /// Spines are drawn for every case on the shelf, so they use a lower resolution than the faces.
    static func spine(game: Game, spec: CaseSpec, scan: CGImage? = nil) -> CGImage {
        let w = spec.depth * 3600, h = spec.height * 3600
        var rng = SeededRandom(game.id, salt: 1)
        let titleColor: NSColor = brightness(spec.plastic) > 0.5 ? NSColor(white: 0.2, alpha: 1) : .white
        return canvas(w, h) { ctx, rect in
            if let scan {
                fill(ctx, scan, in: rect)
                scuffs(ctx, rect, &rng, amount: 0.8)
                return
            }
            ctx.setFillColor(spec.plastic.cgColor)
            ctx.fill(rect)
            let band = CGRect(x: 0, y: rect.height * 0.86, width: rect.width, height: rect.height * 0.14)
            ctx.setFillColor(spec.band.cgColor)
            ctx.fill(band)
            let reads = rect.width * 0.46
            // Spine lettering runs top to bottom, as on North American cases.
            ctx.saveGState()
            ctx.translateBy(x: band.midX, y: band.midY)
            ctx.rotate(by: -.pi / 2)
            text(spec.bandText, in: CGRect(x: -band.height / 2, y: -band.width / 2, width: band.height, height: band.width), size: reads * 0.72, weight: .semibold, color: spec.bandTextColor)
            ctx.restoreGState()

            let titleArea = CGRect(x: 0, y: rect.height * 0.08, width: rect.width, height: rect.height * 0.76)
            ctx.saveGState()
            ctx.translateBy(x: titleArea.midX, y: titleArea.midY)
            ctx.rotate(by: -.pi / 2)
            text(game.title, in: CGRect(x: -titleArea.height / 2, y: -titleArea.width / 2, width: titleArea.height, height: titleArea.width), size: reads, weight: .heavy, color: titleColor)
            ctx.restoreGState()
            scuffs(ctx, rect, &rng, amount: 0.8)
        }
    }

    static func front(game: Game, spec: CaseSpec, art: CGImage?) -> CGImage {
        let w = spec.width * pixelsPerMetre, h = spec.height * pixelsPerMetre
        var rng = SeededRandom(game.id, salt: 2)
        return canvas(w, h) { ctx, rect in
            if let art {
                fill(ctx, art, in: rect)
            } else {
                placeholderCover(ctx, rect, game: game, spec: spec)
                _ = header(ctx, rect, spec: spec)
            }
            scuffs(ctx, rect, &rng)
        }
    }

    static func back(game: Game, spec: CaseSpec, art: CGImage?, shot: CGImage?, scan: CGImage? = nil) -> CGImage {
        let w = spec.width * pixelsPerMetre, h = spec.height * pixelsPerMetre
        var rng = SeededRandom(game.id, salt: 3)
        return canvas(w, h) { ctx, rect in
            if let scan {
                fill(ctx, scan, in: rect)
                scuffs(ctx, rect, &rng)
                return
            }
            let base = art.map { mix(averageColor($0), .black, 0.6) } ?? spec.plastic
            ctx.setFillColor(base.cgColor)
            ctx.fill(rect)
            let band = header(ctx, rect, spec: spec)
            let inset = rect.width * 0.07
            text(game.title, in: CGRect(x: inset, y: band.minY - rect.height * 0.1, width: rect.width - inset * 2, height: rect.height * 0.08), size: rect.width * 0.065, weight: .heavy, color: .white)

            // Two "screenshots" and a block of blurb.
            let shotHeight = rect.height * 0.2
            for (i, source) in [shot ?? art, art].enumerated() {
                let frame = CGRect(x: inset + CGFloat(i) * (rect.width - inset * 2) / 2 + (i == 1 ? inset / 2 : 0),
                                   y: band.minY - rect.height * 0.13 - shotHeight,
                                   width: (rect.width - inset * 3) / 2, height: shotHeight)
                ctx.setFillColor(NSColor(white: 0, alpha: 0.5).cgColor)
                ctx.fill(frame)
                if let source { fill(ctx, source, in: frame.insetBy(dx: 3, dy: 3)) }
            }
            var y = rect.height * 0.42
            for line in 0..<9 {
                let lineWidth = (rect.width - inset * 2) * (line % 4 == 3 ? 0.6 : 0.92 + rng.unit() * 0.08)
                ctx.setFillColor(NSColor(white: 1, alpha: 0.28).cgColor)
                ctx.fill(CGRect(x: inset, y: y, width: min(lineWidth, rect.width - inset * 2), height: rect.height * 0.009))
                y -= rect.height * 0.022
            }
            // Rating box and barcode.
            let footer = rect.height * 0.05
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: inset, y: footer, width: rect.width * 0.1, height: rect.height * 0.08))
            ctx.fill(CGRect(x: rect.maxX - inset - rect.width * 0.25, y: footer, width: rect.width * 0.25, height: rect.height * 0.06))
            ctx.setFillColor(NSColor.black.cgColor)
            var x = rect.maxX - inset - rect.width * 0.24
            while x < rect.maxX - inset - rect.width * 0.02 {
                let bar = 1 + rng.unit() * 3
                ctx.fill(CGRect(x: x, y: footer + 6, width: bar, height: rect.height * 0.05 - 10))
                x += bar + 1 + rng.unit() * 3
            }
            scuffs(ctx, rect, &rng)
        }
    }

    /// The moulded inside: a disc hub on the tray side, clips on the cover side.
    static func inside(spec: CaseSpec, tray: Bool) -> CGImage {
        let w = spec.width * pixelsPerMetre / 2, h = spec.height * pixelsPerMetre / 2
        return canvas(w, h) { ctx, rect in
            let light = brightness(spec.plastic) > 0.5
            let plastic = mix(spec.plastic, light ? .black : .white, 0.12)
            ctx.setFillColor(plastic.cgColor)
            ctx.fill(rect)
            let px = pixelsPerMetre / 2
            ctx.setStrokeColor(NSColor(white: light ? 0 : 1, alpha: 0.12).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 0.006 * px, dy: 0.006 * px))
            if tray {
                let c = CGPoint(x: rect.midX, y: rect.midY)
                for r in [spec.discRadius + 0.002, 0.016, 0.011] {
                    ctx.strokeEllipse(in: CGRect(x: c.x - r * px, y: c.y - r * px, width: r * 2 * px, height: r * 2 * px))
                }
            } else {
                ctx.setFillColor(NSColor(white: 0.5, alpha: 0.18).cgColor)
                for y in [rect.height * 0.2, rect.height * 0.8] {
                    ctx.fill(CGRect(x: rect.maxX - 0.012 * px, y: y - 0.01 * px, width: 0.008 * px, height: 0.02 * px))
                }
            }
        }
    }

    static func manual(game: Game, spec: CaseSpec, art: CGImage?) -> CGImage {
        let w = spec.width * 0.9 * pixelsPerMetre, h = spec.height * 0.92 * pixelsPerMetre
        var rng = SeededRandom(game.id, salt: 4)
        return canvas(w, h) { ctx, rect in
            ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
            ctx.fill(rect)
            let artRect = rect.insetBy(dx: rect.width * 0.035, dy: rect.width * 0.035)
            if let art {
                fill(ctx, art, in: artRect)
            } else {
                placeholderCover(ctx, artRect, game: game, spec: spec)
            }
            let band = CGRect(x: artRect.minX, y: artRect.minY, width: artRect.width, height: rect.height * 0.07)
            ctx.setFillColor(NSColor(white: 0, alpha: 0.72).cgColor)
            ctx.fill(band)
            text("INSTRUCTION BOOKLET", in: band, size: band.height * 0.38, weight: .semibold, color: .white)
            // Paper fibres.
            for _ in 0..<400 {
                ctx.setFillColor(NSColor(white: rng.unit() > 0.5 ? 1 : 0.6, alpha: 0.05).cgColor)
                ctx.fill(CGRect(x: rng.unit() * rect.width, y: rng.unit() * rect.height, width: 1 + rng.unit() * 4, height: 1))
            }
            scuffs(ctx, rect, &rng, amount: 0.35)
        }
    }

    static func disc(game: Game, spec: CaseSpec, label: CGImage?, art: CGImage?, scan: CGImage? = nil) -> CGImage {
        var rng = SeededRandom(game.id, salt: 5)
        return canvas(1024, 1024) { ctx, rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let mm = r / (spec.discRadius * 1000)
            func circle(_ radius: CGFloat) -> CGRect { CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2) }

            // A real disc scan fills its image edge to edge, hub and all, so it maps straight onto the disc.
            if let scan {
                ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
                ctx.fillEllipse(in: circle(r))
                ctx.saveGState()
                ctx.addEllipse(in: circle(r))
                ctx.clip()
                ctx.interpolationQuality = .high
                ctx.draw(scan, in: rect)
                scuffs(ctx, rect, &rng, amount: 0.4)
                ctx.restoreGState()
                return
            }

            ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
            ctx.fillEllipse(in: circle(r))
            // Printed label between the clear hub and the rim.
            ctx.saveGState()
            ctx.addEllipse(in: circle(r - 1.2 * mm))
            ctx.addEllipse(in: circle(min(18 * mm, r * 0.45)))
            ctx.clip(using: .evenOdd)
            if let source = label ?? art {
                fill(ctx, source, in: circle(r))
                let shade = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0, alpha: 0.75).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(shade, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y - r * 0.2), options: [])
            } else {
                ctx.setFillColor(NSColor(game.system.color).cgColor)
                ctx.fill(rect)
            }
            ctx.restoreGState()
            text(game.title, in: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.78, width: r * 1.2, height: r * 0.24), size: r * 0.09, weight: .heavy, color: .white)
            text(spec.bandText, in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.58, width: r, height: r * 0.16), size: r * 0.075, weight: .bold, color: NSColor(white: 1, alpha: 0.92))

            // Clear hub with its moulded ring.
            ctx.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor)
            ctx.fillEllipse(in: circle(min(18 * mm, r * 0.45)))
            ctx.setStrokeColor(NSColor(white: 0.6, alpha: 1).cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: circle(min(11 * mm, r * 0.3)))
            ctx.saveGState()
            ctx.addEllipse(in: circle(r))
            ctx.clip()
            scuffs(ctx, rect, &rng, amount: 0.5)
            ctx.restoreGState()
        }
    }

    static func plate(_ text: String) -> CGImage {
        canvas(640, 80) { ctx, rect in
            let brass = CGGradient(colorsSpace: nil, colors: [NSColor(red: 0.80, green: 0.66, blue: 0.38, alpha: 1).cgColor, NSColor(red: 0.55, green: 0.42, blue: 0.20, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(brass, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: 0), options: [])
            Self.text(text.uppercased(), in: rect.insetBy(dx: 16, dy: 0), size: 38, weight: .heavy, color: NSColor(red: 0.18, green: 0.12, blue: 0.05, alpha: 1))
        }
    }

    static let wood: CGImage = {
        var rng = SeededRandom(UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)))
        return canvas(1024, 512) { ctx, rect in
            ctx.setFillColor(NSColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1).cgColor)
            ctx.fill(rect)
            // Broad colour bands, then fine grain lines that wander gently along the board.
            for _ in 0..<18 {
                let y = rng.unit() * rect.height
                ctx.setFillColor(NSColor(red: 0.25 + rng.unit() * 0.18, green: 0.14 + rng.unit() * 0.09, blue: 0.07, alpha: 0.35).cgColor)
                ctx.fill(CGRect(x: 0, y: y, width: rect.width, height: 8 + rng.unit() * 40))
            }
            for _ in 0..<420 {
                let y = rng.unit() * rect.height
                let wave = 0.5 + rng.unit() * 2.5
                let period = 180 + rng.unit() * 400
                let phase = rng.unit() * 6
                ctx.setStrokeColor(NSColor(red: 0.16 + rng.unit() * 0.14, green: 0.09 + rng.unit() * 0.07, blue: 0.04, alpha: 0.18 + rng.unit() * 0.3).cgColor)
                ctx.setLineWidth(0.5 + rng.unit() * 1.5)
                ctx.move(to: CGPoint(x: 0, y: y + sin(phase) * wave))
                var x: CGFloat = 0
                while x < rect.width {
                    x += 12
                    ctx.addLine(to: CGPoint(x: x, y: y + sin(x / period * 2 * .pi + phase) * wave))
                }
                ctx.strokePath()
            }
        }
    }()

    /// Soft studio lights for reflections on the plastic.
    static let environment: CGImage = canvas(1024, 512) { ctx, rect in
        let room = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0.18, alpha: 1).cgColor, NSColor(white: 0.03, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(room, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: 0), options: [])
        for (x, y, radius, white) in [(0.25, 0.78, 110.0, 0.55), (0.62, 0.72, 80.0, 0.45), (0.9, 0.6, 60.0, 0.3)] {
            let center = CGPoint(x: rect.width * x, y: rect.height * y)
            let light = CGGradient(colorsSpace: nil, colors: [NSColor(red: 1, green: 0.95, blue: 0.86, alpha: white).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
    }
}
