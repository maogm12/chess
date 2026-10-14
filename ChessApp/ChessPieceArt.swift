import UIKit

/// Vector artwork for the chess pieces, converted from the supplied 48×48 SVG icon set.
/// Keeping the geometry as paths (instead of raster assets) means every piece stays crisp at
/// board size and inside the captured-piece trays, and the colors follow `ForkChessTheme`.

enum ChessPieceInk {
    case body
    case ink
}

struct ChessPieceShape {
    let path: UIBezierPath
    let evenOdd: Bool
    let fill: ChessPieceInk?
    let stroke: ChessPieceInk?
    let strokeWidth: CGFloat
}

enum ChessPieceArt {
    private static var cache: [String: [ChessPieceShape]] = [:]

    static func shapes(kind: Character, isWhite: Bool) -> [ChessPieceShape] {
        let key = "\(kind.lowercased())-\(isWhite ? "w" : "b")"
        if let cached = cache[key] { return cached }
        let svg = isWhite ? whiteArt[kind.lowercased()] : blackArt[kind.lowercased()]
        let parsed = svg.map(SVGParser.shapes(from:)) ?? []
        cache[key] = parsed
        return parsed
    }

    private static let whiteArt: [String: String] = [
        "k": """
        <path d="M21.3 3.4 H26.7 V8 H31 V12.6 H26.7 V14.2 H31.4 Q34.5 14.2 35.1 17.8 H12.9 Q13.5 14.2 16.6 14.2 H21.3 V12.6 H17 V8 H21.3 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <rect x="15.2" y="19.4" width="17.6" height="3.5" rx="1.7" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M17.3 24.4 H30.7 Q30.5 29.6 36.1 35.9 H11.9 Q17.5 29.6 17.3 24.4 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """,
        "q": """
        <path d="M10.5 10.7 L16.1 17.3 L21.8 7.6 Q24 4.9 26.2 7.6 L31.9 17.3 L37.5 10.7 L35.2 20.1 H12.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <circle cx="10.4" cy="9.7" r="2.8" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <circle cx="24" cy="5.5" r="2.8" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <circle cx="37.6" cy="9.7" r="2.8" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <rect x="14.2" y="21.7" width="19.6" height="3.3" rx="1.65" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M17.2 26.2 H30.8 Q30.6 30.3 36.4 35.9 H11.6 Q17.4 30.3 17.2 26.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """,
        "r": """
        <path d="M11.5 6.8 H18.2 V12 H21.4 V6.8 H26.6 V12 H29.8 V6.8 H36.5 V18.3 Q36.5 19.7 35 19.7 H13 Q11.5 19.7 11.5 18.3 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <rect x="14" y="21.1" width="20" height="3.5" rx="1.6" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M17.2 25.9 H30.8 L30.1 29.2 Q30.8 32.8 35.5 35.9 H12.5 Q17.2 32.8 17.9 29.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """,
        "b": """
        <path d="M24 8.1 C31.1 11.9 35.5 17.8 33.1 23 Q30.6 27.4 24 27.5 Q17.4 27.4 14.9 23 C12.5 17.8 16.9 11.9 24 8.1 Z M28.7 14.3 L30.8 16.3 L21.5 24.7 L19.4 22.8 Z" fill="#FFF8EB" fill-rule="evenodd"/>
        <path d="M24 8.1 C31.1 11.9 35.5 17.8 33.1 23 Q30.6 27.4 24 27.5 Q17.4 27.4 14.9 23 C12.5 17.8 16.9 11.9 24 8.1 Z" fill="none" stroke="#24211F" stroke-width="1.6"/>
        <path d="M29.7 15.2 L20.5 23.8" fill="none" stroke="#24211F" stroke-width="1.4"/>
        <circle cx="24" cy="5.7" r="2.8" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <rect x="15.6" y="28.8" width="16.8" height="3.4" rx="1.7" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M18.4 33.2 H29.6 L35.7 35.9 H12.3 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """,
        "n": """
        <path d="M12.7 35.9 Q14.9 31.6 18.9 27.1 L14.3 28.6 Q9.2 30.1 6.6 25.4 Q5.1 22.3 8.6 18.8 L17 12.9 L20.5 5.0 Q21.3 3.4 22.9 5.1 L28.3 11.8 Q36.1 13 39.1 20.5 Q41.6 26.8 39.1 35.9 Z M18.0 20.0 A1.7 1.7 0 1 0 21.4 20.0 A1.7 1.7 0 1 0 18.0 20.0 Z M29.6 14.6 Q35.0 21.1 35.0 28.8 L33.0 29.0 Q32.7 22.0 27.9 16.2 Z" fill="#FFF8EB" fill-rule="evenodd"/>
        <path d="M12.7 35.9 Q14.9 31.6 18.9 27.1 L14.3 28.6 Q9.2 30.1 6.6 25.4 Q5.1 22.3 8.6 18.8 L17 12.9 L20.5 5.0 Q21.3 3.4 22.9 5.1 L28.3 11.8 Q36.1 13 39.1 20.5 Q41.6 26.8 39.1 35.9 Z" fill="none" stroke="#24211F" stroke-width="1.6"/>
        <circle cx="19.7" cy="20" r="1.55" fill="#24211F"/>
        <path d="M28.7 15.4 Q33.6 21.5 34 28.7" fill="none" stroke="#24211F" stroke-width="1.2"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """,
        "p": """
        <circle cx="24" cy="14.5" r="9.7" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <rect x="15.5" y="25.1" width="17" height="3.6" rx="1.8" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M18.2 30 H29.8 Q30.5 32.6 35.8 35.9 H12.2 Q17.5 32.6 18.2 30 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M10.5 34.8 H37.5 Q40 34.8 40 37.0 V38.5 H8 V37 Q8 34.8 10.5 34.8 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        <path d="M6.6 40.2 H41.4 Q43 40.2 43 42.1 V44.2 H5 V42.1 Q5 40.2 6.6 40.2 Z" fill="#FFF8EB" stroke="#24211F" stroke-width="1.6"/>
        """
    ]

    /// Black pieces use the same silhouettes: the outline and detail strokes drop away, ink
    /// details become the transparent apertures of the shared geometry, and the grid scales up
    /// 2% to compensate for the width the white outlines add.
    private static let blackArt: [String: String] = whiteArt.mapValues { art in
        let body = art.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.contains("fill=\"none\"")          // outline and detail strokes
                    && !line.contains("fill=\"#24211F\"")       // ink details sit inside apertures
            }
            .map { $0.replacingOccurrences(of: "#FFF8EB", with: "#24211F")
                    .replacingOccurrences(of: " stroke=\"#24211F\" stroke-width=\"1.6\"", with: "") }
            .joined()
        return "<g transform=\"translate(-0.48 -0.48) scale(1.02)\">\(body)</g>"
    }
}

/// Minimal SVG reader for the icon set: paths, circles, rectangles, and group transforms.
enum SVGParser {
    static func shapes(from svg: String) -> [ChessPieceShape] {
        var result: [ChessPieceShape] = []
        var transform = CGAffineTransform.identity
        var savedTransforms: [CGAffineTransform] = []
        let pattern = "<(/?)([a-zA-Z]+)([^>]*?)(/?)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: svg, range: NSRange(svg.startIndex..., in: svg))
        for match in matches {
            func text(_ group: Int) -> String {
                guard let range = Range(match.range(at: group), in: svg) else { return "" }
                return String(svg[range])
            }
            let closing = text(1) == "/"
            let name = text(2)
            let attributes = self.attributes(text(3))
            switch name {
            case "g":
                if closing { transform = savedTransforms.popLast() ?? .identity }
                else {
                    savedTransforms.append(transform)
                    transform = transform.concatenating(transformValue(attributes["transform"]))
                }
            default:
                guard !closing, let shape = shape(name: name, attributes: attributes, transform: transform) else { continue }
                result.append(shape)
            }
        }
        return result
    }

    private static func shape(name: String, attributes: [String: String], transform: CGAffineTransform) -> ChessPieceShape? {
        let path: UIBezierPath
        switch name {
        case "path":
            guard let d = attributes["d"] else { return nil }
            path = pathValue(d)
        case "circle":
            let radius = number(attributes["r"])
            guard radius > 0 else { return nil }
            path = UIBezierPath(ovalIn: CGRect(x: number(attributes["cx"]) - radius, y: number(attributes["cy"]) - radius,
                                               width: radius * 2, height: radius * 2))
        case "rect":
            let rect = CGRect(x: number(attributes["x"]), y: number(attributes["y"]),
                              width: number(attributes["width"]), height: number(attributes["height"]))
            guard rect.width > 0, rect.height > 0 else { return nil }
            let radius = number(attributes["rx"])
            path = radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)
        default:
            return nil
        }
        path.apply(transform)
        return ChessPieceShape(path: path, evenOdd: attributes["fill-rule"] == "evenodd",
                               fill: ink(attributes["fill"]), stroke: ink(attributes["stroke"]),
                               strokeWidth: number(attributes["stroke-width"]))
    }

    private static func ink(_ value: String?) -> ChessPieceInk? {
        switch value?.uppercased() {
        case "#FFF8EB": return .body
        case "#24211F": return .ink
        default: return nil
        }
    }

    private static func number(_ value: String?) -> CGFloat {
        guard let value, let parsed = Double(value) else { return 0 }
        return CGFloat(parsed)
    }

    private static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z-]+)=\"([^\"]*)\"") else { return result }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text) else { continue }
            result[String(text[nameRange])] = String(text[valueRange])
        }
        return result
    }

    private static func transformValue(_ text: String?) -> CGAffineTransform {
        guard let text else { return .identity }
        var result = CGAffineTransform.identity
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z]+)\\(([^)]*)\\)") else { return result }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text) else { continue }
            let values = text[valueRange].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            switch text[nameRange] {
            case "translate": result = result.concatenating(CGAffineTransform(translationX: CGFloat(values.first ?? 0), y: CGFloat(values.count > 1 ? values[1] : 0)))
            case "scale": result = result.concatenating(CGAffineTransform(scaleX: CGFloat(values.first ?? 1), y: CGFloat(values.count > 1 ? values[1] : values.first ?? 1)))
            case "matrix":
                guard values.count == 6 else { continue }
                result = result.concatenating(CGAffineTransform(a: CGFloat(values[0]), b: CGFloat(values[1]), c: CGFloat(values[2]),
                                                                d: CGFloat(values[3]), tx: CGFloat(values[4]), ty: CGFloat(values[5])))
            default: continue
            }
        }
        return result
    }

    private static func pathValue(_ d: String) -> UIBezierPath {
        let path = UIBezierPath()
        let characters = Array(d)
        var index = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var previousCommand: Character = "M"
        let commands: Set<Character> = ["M", "m", "L", "l", "H", "h", "V", "v", "C", "c", "Q", "q", "A", "a", "Z", "z"]

        func skipSeparators() {
            while index < characters.count, " ,\n\t\r".contains(characters[index]) { index += 1 }
        }
        func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "+" || characters[index] == "-" { index += 1 }
            var hasDigits = false
            while index < characters.count, characters[index].isNumber { index += 1; hasDigits = true }
            if index < characters.count, characters[index] == "." {
                index += 1
                while index < characters.count, characters[index].isNumber { index += 1; hasDigits = true }
            }
            guard hasDigits, let value = Double(String(characters[start..<index])) else { index = start; return nil }
            return CGFloat(value)
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }
        func resolved(_ point: CGPoint, _ relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
        }

        while index < characters.count {
            skipSeparators()
            guard index < characters.count else { break }
            let command: Character
            if commands.contains(characters[index]) { command = characters[index]; index += 1 }
            else if previousCommand == "M" { command = "L" }
            else if previousCommand == "m" { command = "l" }
            else { command = previousCommand }
            previousCommand = command
            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                guard let value = point() else { index = characters.count; break }
                current = resolved(value, relative)
                path.move(to: current)
                subpathStart = current
            case "L":
                guard let value = point() else { index = characters.count; break }
                current = resolved(value, relative)
                path.addLine(to: current)
            case "H":
                guard let x = number() else { index = characters.count; break }
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                guard let y = number() else { index = characters.count; break }
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "Q":
                guard let controlValue = point(), let endValue = point() else { index = characters.count; break }
                let end = resolved(endValue, relative)
                path.addQuadCurve(to: end, controlPoint: resolved(controlValue, relative))
                current = end
            case "C":
                guard let firstValue = point(), let secondValue = point(), let endValue = point() else { index = characters.count; break }
                let end = resolved(endValue, relative)
                path.addCurve(to: end, controlPoint1: resolved(firstValue, relative), controlPoint2: resolved(secondValue, relative))
                current = end
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let largeArc = number(), let sweep = number(), let endValue = point() else { index = characters.count; break }
                let end = resolved(endValue, relative)
                addArc(path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc != 0, sweep: sweep != 0)
                current = end
            case "Z":
                path.close()
                current = subpathStart
            default:
                index = characters.count
            }
        }
        return path
    }

    /// Endpoint-to-center conversion for the circular arcs used by the icon set.
    private static func addArc(_ path: UIBezierPath, from start: CGPoint, to end: CGPoint,
                               rx: CGFloat, ry: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        let radius = max(abs(rx), abs(ry))
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        guard radius > 0, distance > 0.0001 else { path.addLine(to: end); return }
        let resolvedRadius = max(radius, distance / 2)
        let offset = sqrt(max(0, resolvedRadius * resolvedRadius - (distance / 2) * (distance / 2)))
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let center = CGPoint(x: (start.x + end.x) / 2 + sign * (-dy / distance) * offset,
                             y: (start.y + end.y) / 2 + sign * (dx / distance) * offset)
        path.addArc(withCenter: center, radius: resolvedRadius,
                    startAngle: atan2(start.y - center.y, start.x - center.x),
                    endAngle: atan2(end.y - center.y, end.x - center.x),
                    clockwise: sweep)
    }
}

extension ChessPieceArt {
    /// Draws one piece into `rect`, matching `ChessPieceArtworkView` exactly. Used by the
    /// offscreen renderer that draws puzzle thumbnails.
    static func draw(kind: Character, isWhite: Bool, in rect: CGRect, context: CGContext) {
        let shapes = shapes(kind: kind, isWhite: isWhite)
        guard !shapes.isEmpty else { return }
        let side = min(rect.width, rect.height)
        context.saveGState()
        context.translateBy(x: rect.minX + (rect.width - side) / 2, y: rect.minY + (rect.height - side) / 2)
        context.scaleBy(x: side / 48, y: side / 48)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for shape in shapes {
            if let fill = shape.fill {
                color(fill, isWhite: isWhite).setFill()
                shape.path.usesEvenOddFillRule = shape.evenOdd
                shape.path.fill()
            }
            if let stroke = shape.stroke, shape.strokeWidth > 0 {
                color(stroke, isWhite: isWhite).setStroke()
                shape.path.lineWidth = shape.strokeWidth
                shape.path.stroke()
            }
        }
        context.restoreGState()
    }

    static func color(_ ink: ChessPieceInk, isWhite: Bool) -> UIColor {
        switch ink {
        case .body: return ChessPiecePalette.body(isWhite: isWhite)
        case .ink: return ChessPiecePalette.ink
        }
    }
}

/// Draws one piece from the icon set, scaled to the view's bounds.
class ChessPieceArtworkView: UIView {
    var kind: Character = "p" { didSet { if oldValue != kind { setNeedsDisplay() } } }
    var isWhite = true { didSet { if oldValue != isWhite { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override var intrinsicContentSize: CGSize { CGSize(width: 48, height: 48) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let shapes = ChessPieceArt.shapes(kind: kind, isWhite: isWhite)
        guard !shapes.isEmpty else { return }
        let side = min(bounds.width, bounds.height)
        let scale = side / 48
        context.saveGState()
        context.translateBy(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        context.scaleBy(x: scale, y: scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for shape in shapes {
            if let fill = shape.fill {
                color(fill).setFill()
                shape.path.usesEvenOddFillRule = shape.evenOdd
                shape.path.fill()
            }
            if let stroke = shape.stroke, shape.strokeWidth > 0 {
                color(stroke).setStroke()
                shape.path.lineWidth = shape.strokeWidth
                shape.path.stroke()
            }
        }
        context.restoreGState()
    }

    private func color(_ ink: ChessPieceInk) -> UIColor {
        switch ink {
        case .body: return ChessPiecePalette.body(isWhite: isWhite)
        case .ink: return ChessPiecePalette.ink
        }
    }
}

enum ChessPiecePalette {
    /// Warm ivory for the white pieces, drawn against the app's cool panel colors.
    static func body(isWhite: Bool) -> UIColor {
        isWhite ? UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1) : ink
    }
    static let ink = ForkChessTheme.navy
}
