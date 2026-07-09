import CoreGraphics
import Foundation
import Testing
@testable import shiftTimeline

/// Locks the pan/zoom crop maths behind the marketplace profile picture. The
/// critical invariant: for any clamped transform, the exported canvas is fully
/// covered by the source image — a crop can never bake in empty pixels.
@Suite("Avatar crop geometry")
struct AvatarCropGeometryTests {

    /// A 4:3 photo positioned inside the 16:9 hero window.
    private let image = CGSize(width: 4000, height: 3000)
    private let window = CGSize(width: 320, height: 180)

    // MARK: - baseScale

    @Test("baseScale aspect-fills: the image always covers the window")
    func baseScaleFills() {
        let scale = AvatarCropGeometry.baseScale(imageSize: image, windowSize: window)
        // max(320/4000, 180/3000) = max(0.08, 0.06) = 0.08
        #expect(abs(scale - 0.08) < 0.0001)

        let scaled = CGSize(width: image.width * scale, height: image.height * scale)
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

    @Test("maxOffset is zero on the axis the image only just covers")
    func maxOffsetAxes() {
        let limit = AvatarCropGeometry.maxOffset(imageSize: image, windowSize: window, zoom: 1)
        // Width covers exactly (4000*0.08 = 320) → no horizontal travel.
        #expect(abs(limit.width) < 0.001)
        // Height overflows (3000*0.08 = 240) → (240-180)/2 = 30pt of travel.
        #expect(abs(limit.height - 30) < 0.001)
    }

    @Test("pan is clamped so the window never shows empty space")
    func offsetClamped() {
        let clamped = AvatarCropGeometry.clampOffset(
            CGSize(width: 500, height: 500), imageSize: image, windowSize: window, zoom: 1
        )
        #expect(abs(clamped.width) < 0.001)
        #expect(abs(clamped.height - 30) < 0.001)

        let negative = AvatarCropGeometry.clampOffset(
            CGSize(width: -500, height: -500), imageSize: image, windowSize: window, zoom: 1
        )
        #expect(abs(negative.height + 30) < 0.001)
    }

    @Test("zooming in unlocks horizontal travel that didn't exist at 1x")
    func zoomUnlocksPan() {
        let atOne = AvatarCropGeometry.maxOffset(imageSize: image, windowSize: window, zoom: 1)
        let atTwo = AvatarCropGeometry.maxOffset(imageSize: image, windowSize: window, zoom: 2)
        #expect(atOne.width == 0)
        #expect(atTwo.width > 0)
        #expect(atTwo.height > atOne.height)
    }

    // MARK: - drawRect

    @Test("centred, unzoomed draw is horizontally exact and vertically overflowing")
    func drawRectCentered() {
        let rect = AvatarCropGeometry.drawRect(
            imageSize: image, windowSize: window, zoom: 1, offset: .zero,
            outputSize: AvatarCrop.outputSize
        )
        // k = 1600/320 = 5; scale = 0.08 → 4000*0.08*5 = 1600 wide, 3000*0.08*5 = 1200 tall
        #expect(abs(rect.width - 1600) < 0.01)
        #expect(abs(rect.height - 1200) < 0.01)
        #expect(abs(rect.origin.x) < 0.01)
        #expect(abs(rect.origin.y - (-150)) < 0.01)   // (900-1200)/2
    }

    @Test("panning down by the max offset reveals the top of the source image")
    func drawRectHonoursOffset() {
        let rect = AvatarCropGeometry.drawRect(
            imageSize: image, windowSize: window, zoom: 1,
            offset: CGSize(width: 0, height: 30),      // the clamped maximum
            outputSize: AvatarCrop.outputSize
        )
        // -150 + 30*5 = 0 → the image's top edge lands on the canvas top edge.
        #expect(abs(rect.origin.y) < 0.01)
    }

    @Test("degenerate window falls back to filling the canvas")
    func drawRectGuardsZeroWindow() {
        let rect = AvatarCropGeometry.drawRect(
            imageSize: image, windowSize: .zero, zoom: 1, offset: .zero,
            outputSize: AvatarCrop.outputSize
        )
        #expect(rect.size == AvatarCrop.outputSize)
    }

    // MARK: - The invariant

    @Test("INVARIANT: any clamped transform fully covers the export canvas")
    func exportIsAlwaysFullyCovered() {
        let output = AvatarCrop.outputSize
        // Portrait, landscape, and square sources across the zoom range.
        let sources = [
            CGSize(width: 4000, height: 3000),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 2000, height: 2000),
            CGSize(width: 6000, height: 1000),
        ]
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
