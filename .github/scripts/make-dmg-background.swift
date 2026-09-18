// Draws the installer window's background: the app icon's night sky, with a pixel-art arrow from Cartridge to the
// Applications folder. Usage: swift .github/scripts/make-dmg-background.swift <out.png> <scale> <version>
//
// Everything is drawn here, including the pixel lettering, so there is no font licence or image asset to track.
// The layout has to agree with .github/scripts/dmg-settings.py: a 660 x 400 point window, 128-point icons centred at
// (165, 190) and (495, 190).
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <out.png> <scale> <version>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let version = arguments[3]

let size = CGSize(width: 660, height: 400)
let appCentre = CGPoint(x: 165, y: 190)
let folderCentre = CGPoint(x: 495, y: 190)

func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, alpha: alpha)
}

// The icon's colours.
let pink: UInt32 = 0xff4fa8, candy: UInt32 = 0xff6ad5, butter: UInt32 = 0xffcf6a, sky: UInt32 = 0x5ae0ff
let lilac: UInt32 = 0x8f7bff, mint: UInt32 = 0x9dff8a, cream: UInt32 = 0xfff3c4

let width = Int(size.width * scale), height = Int(size.height * scale)
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// Top-left origin in points, like the Finder window it sits in.
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: scale, y: -scale)
context.interpolationQuality = .none

// MARK: Sky

let sky1 = CGGradient(colorsSpace: nil, colors: [color(0x221c52), color(0x140f33)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(sky1, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

func glow(_ centre: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ alpha: Double) {
    let gradient = CGGradient(colorsSpace: nil, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
}
glow(CGPoint(x: 560, y: 40), 330, 0xb0419a, 0.55)   // magenta, top right - as on the icon
glow(CGPoint(x: 70, y: 400), 320, 0x1f7a9a, 0.50)   // teal, bottom left
glow(CGPoint(x: 330, y: 200), 260, 0x5b3aa8, 0.30)

// Tiny pixel stars, placed the same way on every run.
var seed: UInt64 = 0x5eed_cafe
func random() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(1 << 53)
}
for _ in 0..<70 {
    let point = CGPoint(x: (random() * 660).rounded(), y: (random() * 400).rounded())
    let tint = [cream, sky, candy, lilac][Int(random() * 4)]
    context.setFillColor(color(tint, 0.35 + random() * 0.45))
    let pixel: CGFloat = random() < 0.2 ? 3 : 2
    context.fill(CGRect(x: point.x, y: point.y, width: pixel, height: pixel))
}

/// The icon's four-pointed sparkle.
func sparkle(_ centre: CGPoint, _ radius: CGFloat, _ alpha: Double) {
    glow(centre, radius * 1.8, 0xffffff, alpha * 0.25)
    let waist = radius * 0.22
    let path = CGMutablePath()
    path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
    path.addQuadCurve(to: CGPoint(x: centre.x + radius, y: centre.y), control: CGPoint(x: centre.x + waist, y: centre.y - waist))
    path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + radius), control: CGPoint(x: centre.x + waist, y: centre.y + waist))
    path.addQuadCurve(to: CGPoint(x: centre.x - radius, y: centre.y), control: CGPoint(x: centre.x - waist, y: centre.y + waist))
    path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - radius), control: CGPoint(x: centre.x - waist, y: centre.y - waist))
    context.addPath(path)
    context.setFillColor(color(0xffffff, alpha))
    context.fillPath()
}
sparkle(CGPoint(x: 54, y: 58), 11, 0.9)
sparkle(CGPoint(x: 612, y: 330), 9, 0.85)
sparkle(CGPoint(x: 598, y: 118), 5, 0.7)
sparkle(CGPoint(x: 96, y: 292), 5, 0.6)
sparkle(CGPoint(x: 330, y: 300), 4, 0.5)

// MARK: Pixel art

/// Draws a bitmap given as rows of "#" (fill) and anything else (empty), `pixel` points per dot.
func sprite(_ rows: [String], at origin: CGPoint, pixel: CGFloat, _ fill: CGColor) {
    context.setFillColor(fill)
    for (y, row) in rows.enumerated() {
        for (x, dot) in row.enumerated() where dot == "#" {
            context.fill(CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel))
        }
    }
}

/// A 5 x 7 pixel font, drawn for this file.
let font: [Character: [String]] = [
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
    ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
    "-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
]

func textWidth(_ text: String, pixel: CGFloat) -> CGFloat {
    text.reduce(0) { width, char in width + (char == " " ? 4 : 6) * pixel } - pixel
}

/// Pixel text centred on `centreX`, with a hard drop shadow like an old title screen.
func title(_ text: String, centreX: CGFloat, top: CGFloat, pixel: CGFloat, _ fill: UInt32, shadow: UInt32?, alpha: Double = 1) {
    for pass in shadow == nil ? [0] : [1, 0] {
        var x = (centreX - textWidth(text, pixel: pixel) / 2).rounded()
        let offset = CGFloat(pass) * pixel
        for char in text {
            if let glyph = font[char] {
                sprite(glyph, at: CGPoint(x: x + offset, y: top + offset), pixel: pixel,
                       pass == 1 ? color(shadow!, alpha) : color(fill, alpha))
            }
            x += (char == " " ? 4 : 6) * pixel
        }
    }
}

title("INSERT CARTRIDGE", centreX: 330, top: 30, pixel: 4, cream, shadow: pink)
title("DRAG IT INTO YOUR APPLICATIONS FOLDER", centreX: 330, top: 76, pixel: 2, sky, shadow: nil, alpha: 0.85)

// MARK: Where the icons sit

/// A soft glowing pad under an icon, like the glass floor on the app icon.
func pad(_ centre: CGPoint, _ hex: UInt32) {
    context.saveGState()
    context.translateBy(x: centre.x, y: centre.y + 58)
    context.scaleBy(x: 1, y: 0.22)
    glow(.zero, 90, hex, 0.55)
    context.restoreGState()
}
pad(appCentre, candy)
pad(folderCentre, sky)

/// A plate behind each icon's name. Finder draws names black in light mode and white in dark mode, whatever the
/// background, so the plate's lightness sits between the two: both read at better than 4:1.
func plate(_ centre: CGPoint) {
    let rect = CGRect(x: centre.x - 62, y: centre.y + 70, width: 124, height: 22)
    context.setFillColor(color(0x7e6ccb))
    context.fill(rect.insetBy(dx: 2, dy: 0))
    context.fill(rect.insetBy(dx: 0, dy: 2))   // the notched corners of a pixel-art box
    context.setFillColor(color(0xffffff, 0.18))
    context.fill(CGRect(x: rect.minX + 2, y: rect.minY, width: rect.width - 4, height: 2))
}
plate(appCentre)
plate(folderCentre)

// MARK: The arrow

/// An 8-bit arrow: a dashed shaft that runs from pink to butter yellow, then a stepped head, with a dark shadow.
func arrow(from start: CGFloat, to end: CGFloat, y: CGFloat) {
    let pixel: CGFloat = 5
    let head = ["#......", "##.....", "###....", "####...", "#####..", "######.", "#######", "######.", "#####..", "####...", "###....", "##.....", "#......"]
    let headWidth = CGFloat(head[0].count) * pixel
    let shaftEnd = end - headWidth
    func blend(_ t: CGFloat) -> CGColor {
        func channel(_ a: UInt32, _ b: UInt32, _ shift: UInt32) -> Double {
            let x = Double((a >> shift) & 0xff), z = Double((b >> shift) & 0xff)
            return (x + (z - x) * Double(t)) / 255
        }
        return CGColor(srgbRed: channel(pink, butter, 16), green: channel(pink, butter, 8), blue: channel(pink, butter, 0), alpha: 1)
    }
    for pass in [1, 0] {   // shadow first, then the arrow on top
        let shift = CGFloat(pass) * pixel
        var x = start
        while x + pixel * 3 <= shaftEnd {
            context.setFillColor(pass == 1 ? color(0x0c0822, 0.8) : blend((x - start) / (end - start)))
            context.fill(CGRect(x: x + shift, y: y - pixel + shift, width: pixel * 3, height: pixel * 3))
            x += pixel * 5
        }
        sprite(head, at: CGPoint(x: shaftEnd + shift, y: y - CGFloat(head.count) * pixel / 2 + pixel / 2 + shift), pixel: pixel,
               pass == 1 ? color(0x0c0822, 0.8) : color(butter))
    }
}
arrow(from: 250, to: 410, y: appCentre.y)

// MARK: Bottom line

let heart = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
for (index, tint) in [pink, pink, candy].enumerated() {
    sprite(heart, at: CGPoint(x: 22 + CGFloat(index) * 20, y: 368), pixel: 2, color(tint, index == 2 ? 0.45 : 1))
}
title("1UP", centreX: 98, top: 370, pixel: 2, mint, shadow: nil, alpha: 0.8)
let versionText = "VERSION \(version.uppercased())"
title(versionText, centreX: size.width - 22 - textWidth(versionText, pixel: 2) / 2, top: 370, pixel: 2, cream, shadow: nil, alpha: 0.55)

// MARK: CRT scanlines

context.setFillColor(color(0x000000, 0.10))
for line in stride(from: 0, to: size.height, by: 3) {
    context.fill(CGRect(x: 0, y: line, width: size.width, height: 1))
}

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: output)
