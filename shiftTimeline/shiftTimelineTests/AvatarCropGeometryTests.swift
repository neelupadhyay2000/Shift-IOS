import CoreGraphics
import Foundation
import Testing
@testable import shiftTimeline

/// Locks the pan/zoom crop maths behind the marketplace profile picture.
///
/// The viewport is **square** (Instagram: a 1:1 crop shown in a circle). The
/// critical invariant: for any clamped transform, the exported canvas is fully
/// covered by the source image — a crop can never bake in empty pixels.
@Suite("Avatar crop geometry")
struct AvatarCropGeometryTests {

    /// A square viewport, matching the square export canvas. `drawRect` maps the
    /// window onto the canvas by a single factor, so the two must share an aspect.
    private let window = CGSize(width: 320, height: 320)

    private let landscape = CGSize(width: 4000, height: 3000)
    private let portrait  = CGSize(width: 1080, height: 1920)
    private let square    = CGSize(width: 2000, height: 2000)

    // MARK: - Shape contract

    @Test("the profile picture is square, and the canvas matches the viewport")
    func shapeIsSquare() {
        #expect(AvatarCrop.aspectRatio == 1)
        #expect(AvatarCrop.outputSize.width == AvatarCrop.outputSize.height)
        // window aspect == output aspect, or drawRect's single scale factor lies.
        #expect(window.width / window.height == AvatarCrop.outputSize.width / AvatarCrop.outputSize.height)
    }

    // MARK: - baseScale

    @Test("baseScale aspect-fills: the image always covers the window")
    func baseScaleFills() {
        let scale = AvatarCropGeometry.baseScale(imageSize: landscape, windowSize: window)
        // max(320/4000, 320/3000) = max(0.08, 0.1067) = 0.1067 — driven by the short edge.
        #expect(abs(scale - (320.0 / 3000.0)) < 0.0001)

        let scaled = CGSize(width: landscape.width * scale, height: landscape.height * scale)
        #expect(scaled.width >= window.width - 0.001)
        #expect(scaled.height >= window.height - 0.001)
    }

    @Test("degenerate image size doesn't divide by zero")
    func baseScaleGuardsZero() {
        #expect(AvatarCropGeometry.baseScale(imageSize: .zero, windowSize: window) == 1)
    }

    // MARK: - Clamping

    @Test("zoom is clamped to the aspect-fill baseline and the max")
    func zoomClamped() {
        #expect(AvatarCropGeometry.clampZoom(0.2) == 1)      // never letterbox
        #expect(AvatarCropGeometry.clampZoom(2.5) == 2.5)
        #expect(AvatarCropGeometry.clampZoom(99) == AvatarCrop.maxZoom)
    }

    @Test("a landscape photo pans horizontally only; a portrait one vertically only")
    func travelAxesFollowOrientation() {
        let wide = AvatarCropGeometry.maxOffset(imageSize: landscape, windowSize: window, zoom: 1)
        #expect(wide.width > 0)                 // (4000*0.1067 - 320)/2 ≈ 53.3
        #expect(abs(wide.height) < 0.001)       // short edge exactly fills

        let tall = AvatarCropGeometry.maxOffset(imageSize: portrait, windowSize: window, zoom: 1)
        #expect(abs(tall.width) < 0.001)
        #expect(tall.height > 0)                // ≈ 124.4 — pick the head or the feet
    }

    @Test("pan is clamped so the window never shows empty space")
    func offsetClamped() {
        let clamped = AvatarCropGeometry.clampOffset(
            CGSize(width: 0, height: 9999), imageSize: portrait, windowSize: window, zoom: 1
        )
        let limit = AvatarCropGeometry.maxOffset(imageSize: portrait, windowSize: window, zoom: 1)
        #expect(abs(clamped.height - limit.height) < 0.001)

        let negative = AvatarCropGeometry.clampOffset(
            CGSize(width: 0, height: -9999), imageSize: portrait, windowSize: window, zoom: 1
        )
        #expect(abs(negative.height + limit.height) < 0.001)
    }

    @Test("a square photo has no travel at 1x, and gains it on zoom")
    func zoomUnlocksPan() {
        let atOne = AvatarCropGeometry.maxOffset(imageSize: square, windowSize: window, zoom: 1)
        #expect(abs(atOne.width) < 0.001)
        #expect(abs(atOne.height) < 0.001)

        let atTwo = AvatarCropGeometry.maxOffset(imageSize: square, windowSize: window, zoom: 2)
        #expect(atTwo.width > 0)
        #expect(atTwo.height > 0)
    }

    // MARK: - drawRect

    @Test("centred, unzoomed landscape overflows horizontally and fits vertically")
    func drawRectCentered() {
        let output = AvatarCrop.outputSize
        let rect = AvatarCropGeometry.drawRect(
            imageSize: landscape, windowSize: window, zoom: 1, offset: .zero, outputSize: output
        )
        let k = output.width / window.width                       // 3.2
        let scale = 320.0 / 3000.0                                // baseScale
        #expect(abs(rect.width - landscape.width * scale * k) < 0.01)
        #expect(abs(rect.height - output.height) < 0.01)          // short edge fills exactly
        #expect(rect.origin.x < 0)                                // cropped left+right
        #expect(abs(rect.origin.y) < 0.01)
    }

    @Test("panning a portrait photo to its max reveals the top of the source")
    func drawRectHonoursOffset() {
        let output = AvatarCrop.outputSize
        let limit = AvatarCropGeometry.maxOffset(imageSize: portrait, windowSize: window, zoom: 1)
        let rect = AvatarCropGeometry.drawRect(
            imageSize: portrait, windowSize: window, zoom: 1,
            offset: CGSize(width: 0, height: limit.height), outputSize: output
        )
        // The image's top edge lands exactly on the canvas top edge.
        #expect(abs(rect.origin.y) < 0.01)
    }

    @Test("degenerate window falls back to filling the canvas")
    func drawRectGuardsZeroWindow() {
        let rect = AvatarCropGeometry.drawRect(
            imageSize: landscape, windowSize: .zero, zoom: 1, offset: .zero,
            outputSize: AvatarCrop.outputSize
        )
        #expect(rect.size == AvatarCrop.outputSize)
    }

    // MARK: - The invariant

    @Test("INVARIANT: any clamped transform fully covers the export canvas")
    func exportIsAlwaysFullyCovered() {
        let output = AvatarCrop.outputSize
        let sources = [landscape, portrait, square, CGSize(width: 6000, height: 1000)]
        let zooms: [CGFloat] = [1, 1.3, 2, 3.7, AvatarCrop.maxZoom]
        let pans = [
            CGSize(width: 0, height: 0),
            CGSize(width: 9999, height: 9999),
            CGSize(width: -9999, height: -9999),
            CGSize(width: 9999, height: -9999),
        ]

        for source in sources {
            for zoom in zooms {
                for pan in pans {
                    let clamped = AvatarCropGeometry.clampOffset(
                        pan, imageSize: source, windowSize: window, zoom: zoom
                    )
                    let rect = AvatarCropGeometry.drawRect(
                        imageSize: source, windowSize: window, zoom: zoom,
                        offset: clamped, outputSize: output
                    )
                    let epsilon: CGFloat = 0.01
                    #expect(rect.minX <= epsilon, "left gap: \(source) z\(zoom)")
                    #expect(rect.minY <= epsilon, "top gap: \(source) z\(zoom)")
                    #expect(rect.maxX >= output.width - epsilon, "right gap: \(source) z\(zoom)")
                    #expect(rect.maxY >= output.height - epsilon, "bottom gap: \(source) z\(zoom)")
                }
            }
        }
    }
}
