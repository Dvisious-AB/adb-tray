import CoreGraphics
import Foundation
import ImageIO

/// A small reader for the flat SVG files in `branding/`: the Appninjas symbol, the generated app icon and
/// the Phosphor icons. It understands `viewBox`, and `<path>` elements with `d`, `fill`, `fill-rule` and a
/// `matrix(...)` transform, which is all those files use. AppKit cannot read SVG on every macOS version
/// the app supports, and drawing the files themselves keeps them the single source of every icon.
public struct VectorImage {
    public enum Fill: Equatable {
        case currentColor
        case none
        case rgb(red: CGFloat, green: CGFloat, blue: CGFloat)
    }

    public struct Shape {
        public let path: CGPath
        public let fill: Fill
        public let evenOdd: Bool
    }

    public enum ParseError: Error, Equatable {
        case missingViewBox
        case badPathData(String)
    }

    public let viewBox: CGRect
    public let shapes: [Shape]

    public init(svg: String) throws {
        guard let box = Self.attribute("viewBox", in: Self.firstTag("svg", in: svg) ?? "") else {
            throw ParseError.missingViewBox
        }
        let numbers = try PathParser.numbers(box)
        guard numbers.count == 4 else { throw ParseError.missingViewBox }
        viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])

        // A fill on the root element (Phosphor sets fill="currentColor" there) is inherited by the paths.
        let rootFill = Self.attribute("fill", in: Self.firstTag("svg", in: svg) ?? "").map(Self.fill) ?? .rgb(red: 0, green: 0, blue: 0)
        var shapes: [Shape] = []
        for tag in Self.tags("path", in: svg) {
            guard let data = Self.attribute("d", in: tag) else { continue }
            var transform = CGAffineTransform.identity
            if let matrix = Self.attribute("transform", in: tag) {
                transform = try Self.matrix(matrix)
            }
            let path = try PathParser.path(data, transform: transform)
            shapes.append(Shape(path: path,
                                fill: Self.attribute("fill", in: tag).map(Self.fill) ?? rootFill,
                                evenOdd: Self.attribute("fill-rule", in: tag) == "evenodd"))
        }
        self.shapes = shapes
    }

    public init(contentsOf url: URL) throws {
        try self.init(svg: String(contentsOf: url, encoding: .utf8))
    }

    /// Draws the image scaled to fit `rect`, centred, in a context whose origin is at the top left
    /// (as in SVG). `currentColor` is drawn in `currentColor`.
    public func draw(in context: CGContext, rect: CGRect, currentColor: CGColor) {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        context.saveGState()
        context.translateBy(x: rect.midX - viewBox.width * scale / 2, y: rect.midY - viewBox.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        for shape in shapes {
            switch shape.fill {
            case .none: continue
            case .currentColor: context.setFillColor(currentColor)
            case let .rgb(red, green, blue): context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            }
            context.addPath(shape.path)
            context.fillPath(using: shape.evenOdd ? .evenOdd : .winding)
        }
        context.restoreGState()
    }

    /// Renders a square PNG, for the app icon's `.iconset`.
    public func pngData(pixels: Int) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Flip so that y runs downwards, as in SVG.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)
        draw(in: context, rect: CGRect(x: 0, y: 0, width: pixels, height: pixels),
             currentColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - XML, just enough for these files

    static func tags(_ name: String, in svg: String) -> [String] {
        let pattern = "<\(name)\\s[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)
        return regex.matches(in: svg, range: range).compactMap { Range($0.range, in: svg).map { String(svg[$0]) } }
    }

    static func firstTag(_ name: String, in svg: String) -> String? {
        tags(name, in: svg).first
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?:^|\\s)\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }

    static func fill(_ value: String) -> Fill {
        if value == "none" { return .none }
        if value == "currentColor" { return .currentColor }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return .currentColor }
        return .rgb(red: CGFloat((number >> 16) & 0xFF) / 255,
                    green: CGFloat((number >> 8) & 0xFF) / 255,
                    blue: CGFloat(number & 0xFF) / 255)
    }

    static func matrix(_ value: String) throws -> CGAffineTransform {
        guard value.hasPrefix("matrix("), value.hasSuffix(")") else { throw ParseError.badPathData(value) }
        let numbers = try PathParser.numbers(String(value.dropFirst(7).dropLast()))
        guard numbers.count == 6 else { throw ParseError.badPathData(value) }
        return CGAffineTransform(a: numbers[0], b: numbers[1], c: numbers[2], d: numbers[3], tx: numbers[4], ty: numbers[5])
    }
}

/// SVG path data (`d`) to a CGPath: every command, absolute and relative, including elliptical arcs.
enum PathParser {
    static func path(_ data: String, transform: CGAffineTransform = .identity) throws -> CGPath {
        var scanner = Tokens(data)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?  // for S and T
        var lastCommand: Character = " "
        let t = transform

        func point(_ x: CGFloat, _ y: CGFloat, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while let command = try scanner.command(repeating: lastCommand) {
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(try scanner.number(), try scanner.number(), relative: relative)
                start = current
                path.move(to: current, transform: t)
                lastControl = nil
                // Further pairs after a moveto are implicit linetos.
                lastCommand = relative ? "l" : "L"
                continue
            case "L":
                current = point(try scanner.number(), try scanner.number(), relative: relative)
                path.addLine(to: current, transform: t)
                lastControl = nil
            case "H":
                let x = try scanner.number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current, transform: t)
                lastControl = nil
            case "V":
                let y = try scanner.number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current, transform: t)
                lastControl = nil
            case "C", "S":
                let control1: CGPoint
                if command.uppercased() == "C" {
                    control1 = point(try scanner.number(), try scanner.number(), relative: relative)
                } else {
                    control1 = reflect(lastControl, around: current, if: "CcSs", lastCommand)
                }
                let control2 = point(try scanner.number(), try scanner.number(), relative: relative)
                let end = point(try scanner.number(), try scanner.number(), relative: relative)
                path.addCurve(to: end, control1: control1, control2: control2, transform: t)
                lastControl = control2
                current = end
            case "Q", "T":
                let control: CGPoint
                if command.uppercased() == "Q" {
                    control = point(try scanner.number(), try scanner.number(), relative: relative)
                } else {
                    control = reflect(lastControl, around: current, if: "QqTt", lastCommand)
                }
                let end = point(try scanner.number(), try scanner.number(), relative: relative)
                path.addQuadCurve(to: end, control: control, transform: t)
                lastControl = control
                current = end
            case "A":
                let rx = try scanner.number(), ry = try scanner.number(), rotation = try scanner.number()
                let largeArc = try scanner.flag(), sweep = try scanner.flag()
                let end = point(try scanner.number(), try scanner.number(), relative: relative)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation,
                       largeArc: largeArc, sweep: sweep, transform: t)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                throw VectorImage.ParseError.badPathData(String(command))
            }
            lastCommand = command
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, around current: CGPoint, if commands: String,
                                _ lastCommand: Character) -> CGPoint {
        guard let control, commands.contains(lastCommand) else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    /// The endpoint-to-centre conversion from the SVG specification (implementation notes, F.6.5 and F.6.6).
    private static func addArc(to path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, rx: CGFloat, ry: CGFloat,
                               rotation: CGFloat, largeArc: Bool, sweep: Bool, transform: CGAffineTransform) {
        if p1 == p2 { return }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: p2, transform: transform)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(x: cosPhi * cx1 - sinPhi * cy1 + (p1.x + p2.x) / 2,
                             y: sinPhi * cx1 + cosPhi * cy1 + (p1.y + p2.y) / 2)

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let startAngle = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // A unit circle at the origin, scaled to the ellipse, rotated and moved to the centre.
        let arcTransform = CGAffineTransform(scaleX: rx, y: ry)
            .concatenating(CGAffineTransform(rotationAngle: phi))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            .concatenating(transform)
        path.addRelativeArc(center: .zero, radius: 1, startAngle: startAngle, delta: delta, transform: arcTransform)
    }

    static func numbers(_ text: String) throws -> [CGFloat] {
        var tokens = Tokens(text)
        var result: [CGFloat] = []
        while tokens.hasMore {
            result.append(try tokens.number())
        }
        return result
    }

    /// Reads commands and numbers from path data. Numbers may run together ("8.5.5", "-1-2").
    struct Tokens {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) {
            characters = Array(text)
        }

        var hasMore: Bool {
            mutating get {
                skipSeparators()
                return index < characters.count
            }
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == "," || characters[index].isWhitespace {
                index += 1
            }
        }

        /// The next command letter, or `repeating` when a number follows a command implicitly.
        mutating func command(repeating previous: Character) throws -> Character? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                return character
            }
            guard previous != " ", previous.uppercased() != "Z" else {
                throw VectorImage.ParseError.badPathData(String(character))
            }
            return previous
        }

        mutating func flag() throws -> Bool {
            skipSeparators()
            guard index < characters.count, characters[index] == "0" || characters[index] == "1" else {
                throw VectorImage.ParseError.badPathData("flag")
            }
            index += 1
            return characters[index - 1] == "1"
        }

        mutating func number() throws -> CGFloat {
            skipSeparators()
            let begin = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var seenDot = false, seenExponent = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    index += 1
                } else if character == ".", !seenDot, !seenExponent {
                    seenDot = true
                    index += 1
                } else if character == "e" || character == "E", !seenExponent {
                    seenExponent = true
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
                } else {
                    break
                }
            }
            guard let value = Double(String(characters[begin..<index])) else {
                throw VectorImage.ParseError.badPathData(String(characters[begin..<min(index + 1, characters.count)]))
            }
            return CGFloat(value)
        }
    }
}
