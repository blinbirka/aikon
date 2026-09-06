import SwiftUI

/// A small parser for the SVG `d` path grammar, used to draw the GitHub and
/// LinkedIn marks in "About" as real vector shapes instead of SF Symbol
/// stand-ins. Supports moveto (`M`/`m`), lineto (`L`/`l`, `H`/`h`, `V`/`v`),
/// cubic and smooth-cubic curveto (`C`/`c`, `S`/`s`), quadratic curveto
/// (`Q`/`q`, `T`/`t`), elliptical arcto (`A`/`a`), and closepath (`Z`/`z`) —
/// everything the two brand marks below use, plus the smooth/quadratic
/// variants for completeness. Arcs are flattened to cubic Béziers using the
/// standard endpoint-to-center conversion (SVG 1.1 §F.6) and the
/// `4/3·tan(Δ/4)` control-point approximation, split into ≤90° segments so
/// the approximation stays accurate. See `SVGPathParserTests`.
enum SVGPathParser {

    static func path(from d: String) -> Path {
        var path = Path()
        var scanner = Scanner(d)

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCommand: Character?
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        while let command = scanner.nextCommand(orRepeat: lastCommand) {
            let isRelative = command.isLowercase

            switch command {
            case "M", "m":
                let point = scanner.nextPoint(relativeTo: isRelative ? current : .zero)
                current = point
                subpathStart = point
                path.move(to: point)
                // A repeated pair after a moveto is an implicit lineto.
                lastCommand = isRelative ? "l" : "L"

            case "L", "l":
                let point = scanner.nextPoint(relativeTo: isRelative ? current : .zero)
                path.addLine(to: point)
                current = point
                lastCommand = command

            case "H", "h":
                let x = scanner.nextNumber()
                let point = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                path.addLine(to: point)
                current = point
                lastCommand = command

            case "V", "v":
                let y = scanner.nextNumber()
                let point = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                path.addLine(to: point)
                current = point
                lastCommand = command

            case "C", "c":
                let origin = isRelative ? current : .zero
                let c1 = scanner.nextPoint(relativeTo: origin)
                let c2 = scanner.nextPoint(relativeTo: origin)
                let end = scanner.nextPoint(relativeTo: origin)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastCommand = command

            case "S", "s":
                let origin = isRelative ? current : .zero
                let c1 = lastCubicControl.map { reflect($0, about: current) } ?? current
                let c2 = scanner.nextPoint(relativeTo: origin)
                let end = scanner.nextPoint(relativeTo: origin)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastCommand = command

            case "Q", "q":
                let origin = isRelative ? current : .zero
                let c = scanner.nextPoint(relativeTo: origin)
                let end = scanner.nextPoint(relativeTo: origin)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCommand = command

            case "T", "t":
                let origin = isRelative ? current : .zero
                let c = lastQuadControl.map { reflect($0, about: current) } ?? current
                let end = scanner.nextPoint(relativeTo: origin)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCommand = command

            case "A", "a":
                let rx = abs(scanner.nextNumber())
                let ry = abs(scanner.nextNumber())
                let xRotation = scanner.nextNumber()
                let largeArc = scanner.nextFlag()
                let sweep = scanner.nextFlag()
                let end = scanner.nextPoint(relativeTo: isRelative ? current : .zero)
                appendArc(to: &path, from: current, rx: rx, ry: ry,
                          xRotationDegrees: xRotation, largeArc: largeArc, sweep: sweep, end: end)
                current = end
                lastCommand = command

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastCommand = command

            default:
                // Unknown command — stop rather than loop forever or guess.
                return path
            }

            if !"CcSs".contains(command) { lastCubicControl = nil }
            if !"QqTt".contains(command) { lastQuadControl = nil }
        }

        return path
    }

    private static func reflect(_ point: CGPoint, about center: CGPoint) -> CGPoint {
        CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }

    /// Converts one SVG elliptical arc segment into cubic Bézier curves and
    /// appends them to `path`. Follows the endpoint-to-center parameterization
    /// from the SVG 1.1 spec (§F.6.5), then walks the resulting angular span
    /// in ≤90° steps, approximating each with the standard
    /// `alpha = 4/3 · tan(Δθ/4)` cubic control-point formula.
    private static func appendArc(to path: inout Path, from start: CGPoint, rx: CGFloat, ry: CGFloat,
                                   xRotationDegrees: CGFloat, largeArc: Bool, sweep: Bool, end: CGPoint) {
        guard start != end else { return }
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }

        let phi = xRotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        var rxAdj = rx
        var ryAdj = ry
        let lambda = (x1p * x1p) / (rxAdj * rxAdj) + (y1p * y1p) / (ryAdj * ryAdj)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rxAdj *= scale
            ryAdj *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let num = max(0, rxAdj * rxAdj * ryAdj * ryAdj - rxAdj * rxAdj * y1p * y1p - ryAdj * ryAdj * x1p * x1p)
        let den = rxAdj * rxAdj * y1p * y1p + ryAdj * ryAdj * x1p * x1p
        let coefficient = den == 0 ? 0 : sign * (num / den).squareRoot()
        let cxp = coefficient * (rxAdj * y1p / ryAdj)
        let cyp = coefficient * -(ryAdj * x1p / rxAdj)

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angleBetween(1, 0, (x1p - cxp) / rxAdj, (y1p - cyp) / ryAdj)
        var deltaTheta = angleBetween((x1p - cxp) / rxAdj, (y1p - cyp) / ryAdj,
                                       (-x1p - cxp) / rxAdj, (-y1p - cyp) / ryAdj)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segmentDelta = deltaTheta / CGFloat(segmentCount)

        func point(on theta: CGFloat) -> CGPoint {
            CGPoint(
                x: cx + rxAdj * cos(theta) * cosPhi - ryAdj * sin(theta) * sinPhi,
                y: cy + rxAdj * cos(theta) * sinPhi + ryAdj * sin(theta) * cosPhi
            )
        }

        var currentTheta = theta1
        for _ in 0..<segmentCount {
            let nextTheta = currentTheta + segmentDelta
            let alpha = (4.0 / 3.0) * tan(segmentDelta / 4)

            // Unit-circle tangent handles, then mapped through the same
            // rotate/scale/translate as `point(on:)` above.
            let c1 = CGPoint(x: cos(currentTheta) - alpha * sin(currentTheta),
                              y: sin(currentTheta) + alpha * cos(currentTheta))
            let c2 = CGPoint(x: cos(nextTheta) + alpha * sin(nextTheta),
                              y: sin(nextTheta) - alpha * cos(nextTheta))

            func transform(_ p: CGPoint) -> CGPoint {
                CGPoint(
                    x: cx + rxAdj * p.x * cosPhi - ryAdj * p.y * sinPhi,
                    y: cy + rxAdj * p.x * sinPhi + ryAdj * p.y * cosPhi
                )
            }

            path.addCurve(to: point(on: nextTheta), control1: transform(c1), control2: transform(c2))
            currentTheta = nextTheta
        }
    }

    /// Hand-rolled character scanner for the SVG number/flag grammar —
    /// `Foundation.Scanner` doesn't handle the no-separator runs SVG paths
    /// use (`"0-3.16"`, two numbers glued by a sign) the way this needs.
    private struct Scanner {
        private let characters: [Character]
        private var index = 0

        init(_ string: String) { characters = Array(string) }

        private func peek() -> Character? { index < characters.count ? characters[index] : nil }
        private mutating func advance() { index += 1 }

        private mutating func skipSeparators() {
            while let c = peek(), c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                advance()
            }
        }

        /// Returns the next command letter, or `lastCommand` if the next
        /// token is a bare number (an implicit repeat of the previous
        /// command, e.g. extra point pairs after a lineto).
        mutating func nextCommand(orRepeat lastCommand: Character?) -> Character? {
            skipSeparators()
            guard let c = peek() else { return nil }
            if c.isLetter {
                advance()
                return c
            }
            return lastCommand
        }

        mutating func nextNumber() -> CGFloat {
            skipSeparators()
            var text = ""
            if let c = peek(), c == "+" || c == "-" {
                text.append(c)
                advance()
            }
            while let c = peek(), c.isNumber {
                text.append(c)
                advance()
            }
            if let c = peek(), c == "." {
                text.append(c)
                advance()
                while let c = peek(), c.isNumber {
                    text.append(c)
                    advance()
                }
            }
            if let c = peek(), c == "e" || c == "E" {
                let expStart = index
                var expText = String(c)
                advance()
                if let s = peek(), s == "+" || s == "-" {
                    expText.append(s)
                    advance()
                }
                var hasExpDigits = false
                while let d = peek(), d.isNumber {
                    expText.append(d)
                    advance()
                    hasExpDigits = true
                }
                if hasExpDigits {
                    text += expText
                } else {
                    index = expStart
                }
            }
            return CGFloat(Double(text) ?? 0)
        }

        /// Arc flags are always exactly one character (`0` or `1`) per the
        /// SVG spec — read as a single digit, not a general number, so a
        /// flag glued to the next coordinate (`"...1-3.88..."`) doesn't get
        /// swallowed into one token.
        mutating func nextFlag() -> Bool {
            skipSeparators()
            guard let c = peek(), c == "0" || c == "1" else { return false }
            advance()
            return c == "1"
        }

        mutating func nextPoint(relativeTo origin: CGPoint) -> CGPoint {
            let x = nextNumber()
            let y = nextNumber()
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }
    }
}

/// Renders an SVG path string (24×24 viewBox) as a `Shape`, scaled to fill
/// whatever frame it's given.
struct SVGGlyph: Shape {
    let pathData: String
    private let viewBoxSize: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let raw = SVGPathParser.path(from: pathData)
        let scale = CGAffineTransform(scaleX: rect.width / viewBoxSize, y: rect.height / viewBoxSize)
        let translate = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return raw.applying(scale.concatenating(translate))
    }
}

/// The two brand mark outlines used in "About" — GitHub's mark-github
/// octicon and LinkedIn's "in" badge, both on a 24×24 grid, filled solid
/// with no stroke.
enum BrandGlyphPaths {
    static let github = "M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.56-1.11-4.56-4.94 0-1.09.39-1.99 1.03-2.69-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.03a9.5 9.5 0 0 1 5 0c1.91-1.3 2.75-1.03 2.75-1.03.55 1.38.2 2.4.1 2.65.64.7 1.03 1.6 1.03 2.69 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2z"

    static let linkedIn = "M6.94 5.5a1.94 1.94 0 1 1-3.88 0 1.94 1.94 0 0 1 3.88 0zM3.4 9h3.1v11.5H3.4zM9.5 9h2.97v1.57h.04c.41-.78 1.42-1.6 2.93-1.6 3.13 0 3.71 2.06 3.71 4.73v6.8h-3.1v-6.03c0-1.44-.03-3.29-2-3.29-2 0-2.31 1.57-2.31 3.19v6.13H9.5z"
}
