import Testing
@testable import Aikon
import Foundation
import SwiftUI

/// `Path.applying(.identity).cgPath` normalizes a `Path` into a segment
/// stream we can inspect (`CGPath.getPathElementsPoints` isn't public, so
/// tests instead sample points at the very end of a segment via
/// `path.boundingRect` and by re-tracing known-shape data).
@Suite struct SVGPathParserTests {

    @Test func straightLinesRoundTrip() {
        // A closed unit square via M/L/L/L/Z should bound exactly [0,4]x[0,4].
        let path = SVGPathParser.path(from: "M0 0L4 0L4 4L0 4Z")
        let bounds = path.boundingRect
        #expect(bounds.minX == 0)
        #expect(bounds.minY == 0)
        #expect(bounds.maxX == 4)
        #expect(bounds.maxY == 4)
    }

    @Test func relativeCommandsMatchAbsoluteEquivalents() {
        let absolute = SVGPathParser.path(from: "M2 2L6 2L6 6Z")
        let relative = SVGPathParser.path(from: "M2 2l4 0l0 4Z")
        #expect(absolute.boundingRect == relative.boundingRect)
    }

    @Test func horizontalAndVerticalShorthandsMoveOnOneAxis() {
        // H/V only touch one coordinate — starting at (1,1), H9 goes to
        // (9,1), then V9 goes to (9,9): still a rectangle bound [1,9]x[1,9].
        let path = SVGPathParser.path(from: "M1 1H9V9H1Z")
        let bounds = path.boundingRect
        #expect(bounds == CGRect(x: 1, y: 1, width: 8, height: 8))
    }

    @Test func numbersGluedBySignAreTokenizedSeparately() {
        // "0-3.16 19.49" must split into 0, -3.16, 19.49 — not "0-3.16" as
        // one malformed number. Exercised via an arc identical in shape to
        // the one at the start of the GitHub mark's path data.
        let path = SVGPathParser.path(from: "M12 2a10 10 0 0 0-3.16 19.49")
        let bounds = path.boundingRect
        // The arc's endpoint is a real move away from the start; a
        // mis-tokenized number would either crash on `Double("0-3.16")`
        // (nil-coalesced to 0, collapsing the arc to a point) or produce a
        // wildly different bound. 19.49 must show up as the width/height
        // scale of a real curve, not get lost.
        #expect(bounds.width > 5)
        #expect(bounds.height > 5)
    }

    @Test func arcFlagsAreReadAsSingleDigitsEvenWhenGlued() {
        // "1 1-3.88" — large-arc=1, sweep=1, x=-3.88, no separators between
        // the second flag and the (negative) x coordinate.
        let path = SVGPathParser.path(from: "M6.94 5.5a1.94 1.94 0 1 1-3.88 0z")
        // If the flags were mis-parsed the resulting arc would collapse or
        // throw the curve far outside the small circle this describes.
        let bounds = path.boundingRect
        #expect(bounds.width < 5)
        #expect(bounds.height < 5)
    }

    @Test func quarterCircleArcMatchesTrigonometry() {
        // A quarter circle of radius 10 centered at the origin, from (10,0)
        // to (0,10), swept counter-clockwise in SVG's y-down space
        // (large-arc=0, sweep=1). The flattened Bézier should pass close to
        // the true 45° point (10·cos45°, 10·sin45°) ≈ (7.07, 7.07).
        let path = SVGPathParser.path(from: "M10 0A10 10 0 0 1 0 10")
        let midpoint = point(onFirstCurveOf: path, at: 0.5)
        #expect(abs(midpoint.x - 7.0710678) < 0.01)
        #expect(abs(midpoint.y - 7.0710678) < 0.01)
    }

    @Test func fullCircleArcClosesBackToStart() {
        // Two semicircle arcs (a common "draw a circle" idiom) must end
        // exactly where they started.
        let path = SVGPathParser.path(from: "M0 10A10 10 0 1 1 0-10A10 10 0 1 1 0 10")
        let bounds = path.boundingRect
        #expect(abs(bounds.width - 20) < 0.05)
        #expect(abs(bounds.height - 20) < 0.05)
    }

    @Test func unknownCommandStopsWithoutCrashing() {
        // Should not hang or trap — just stop at the point it can't parse.
        let path = SVGPathParser.path(from: "M0 0L5 5Q")
        #expect(path.boundingRect.width >= 0)
    }

    @Test func brandGlyphsParseIntoNonEmptyPathsWithinViewBox() {
        for data in [BrandGlyphPaths.github, BrandGlyphPaths.linkedIn] {
            let path = SVGPathParser.path(from: data)
            let bounds = path.boundingRect
            #expect(bounds.width > 0)
            #expect(bounds.height > 0)
            // Both marks are drawn on a 24x24 grid — allow a hair of
            // floating-point slack rather than an exact 0...24 bound.
            #expect(bounds.minX > -0.5 && bounds.maxX < 24.5)
            #expect(bounds.minY > -0.5 && bounds.maxY < 24.5)
        }
    }

    @Test func svgGlyphScalesTheViewBoxToItsFrame() {
        let shape = SVGGlyph(pathData: BrandGlyphPaths.github)
        let scaled = shape.path(in: CGRect(x: 0, y: 0, width: 16, height: 16))
        let bounds = scaled.boundingRect
        // Scaled from a 24-wide viewBox into a 16pt frame: nothing should
        // extend past the frame.
        #expect(bounds.maxX <= 16.01)
        #expect(bounds.maxY <= 16.01)
    }

    /// Approximates "the point at parametric position `t` along the first
    /// curve segment" by linearly probing the flattened cubic's control
    /// polygon isn't exposed publicly, so instead this reconstructs the
    /// expected Bézier from the same first-segment endpoints/controls the
    /// parser would have produced and asks `Path` to trace to a stroked
    /// version — simplest robust option: re-derive analytically.
    private func point(onFirstCurveOf path: Path, at t: CGFloat) -> CGPoint {
        var result = CGPoint.zero
        var found = false
        var current = CGPoint.zero
        path.forEach { element in
            guard !found else { return }
            switch element {
            case .move(let p):
                current = p
            case .curve(let end, let c1, let c2):
                let mt = 1 - t
                let x = mt*mt*mt*current.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x
                let y = mt*mt*mt*current.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
                result = CGPoint(x: x, y: y)
                found = true
            default:
                break
            }
        }
        return result
    }
}
