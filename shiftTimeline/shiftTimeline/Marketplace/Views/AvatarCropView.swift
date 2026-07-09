import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Constants

/// Geometry of the marketplace profile picture.
///
/// The avatar's dominant surface is the **hero banner** — full width by 190pt on
/// `VendorPublicProfileView` and 150pt on `VendorCard` — not the small circles.
/// Every surface renders it with `.scaledToFill()`, which hard centre-crops, so a
/// subject that isn't dead-centre gets cut off. Cropping to the banner's aspect
/// lets the vendor choose the region that survives.
///
/// 16:9 is the canonical target: it sits between the profile banner (~1.9:1 on
/// iPhone) and the card hero, and a subject centred here still reads correctly in
/// the 48pt/72pt circles, which take the middle of the frame.
enum AvatarCrop {
    static let aspectRatio: CGFloat = 16.0 / 9.0
    /// Exported pixel size. Retina-safe for a full-width banner on any device.
    static let outputSize = CGSize(width: 1600, height: 900)
    static let jpegQuality: CGFloat = 0.9
    static let maxZoom: CGFloat = 5
}

// MARK: - Pure geometry (unit-tested)

/// The crop maths, free of SwiftUI and UIKit so it can be tested directly.
///
/// Model: the image is drawn aspect-*filled* into the crop window (`baseScale`),
/// then multiplied by the user's `zoom` and shifted by `offset`. Offsets are
/// clamped so the window is never left showing empty space.
enum AvatarCropGeometry {

    /// The scale at which `imageSize` exactly covers `windowSize` (aspect-fill).
    static func baseScale(imageSize: CGSize, windowSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(windowSize.width / imageSize.width, windowSize.height / imageSize.height)
    }

    /// Zoom is never below the aspect-fill baseline (no letterboxing) nor absurd.
    static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 1), AvatarCrop.maxZoom)
    }

    /// The furthest the image may travel on each axis while still covering the
    /// window. Zero on an axis the image only just covers.
    static func maxOffset(imageSize: CGSize, windowSize: CGSize, zoom: CGFloat) -> CGSize {
        let scale = baseScale(imageSize: imageSize, windowSize: windowSize) * zoom
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGSize(
            width: max(0, (scaled.width - windowSize.width) / 2),
            height: max(0, (scaled.height - windowSize.height) / 2)
        )
    }

    /// Clamps a proposed pan so the crop window stays fully covered.
    static func clampOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        windowSize: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        let limit = maxOffset(imageSize: imageSize, windowSize: windowSize, zoom: zoom)
        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    /// Where to draw the source image on the export canvas so the exported pixels
    /// are exactly what the crop window showed. The window maps onto the canvas by
    /// a single factor `k`, and the image keeps its relative position and scale.
    static func drawRect(
        imageSize: CGSize,
        windowSize: CGSize,
        zoom: CGFloat,
        offset: CGSize,
        outputSize: CGSize
    ) -> CGRect {
        guard windowSize.width > 0, windowSize.height > 0 else {
            return CGRect(origin: .zero, size: outputSize)
        }
        let k = outputSize.width / windowSize.width
        let scale = baseScale(imageSize: imageSize, windowSize: windowSize) * zoom
        let drawSize = CGSize(
            width: imageSize.width * scale * k,
            height: imageSize.height * scale * k
        )
        let origin = CGPoint(
            x: (outputSize.width - drawSize.width) / 2 + offset.width * k,
            y: (outputSize.height - drawSize.height) / 2 + offset.height * k
        )
        return CGRect(origin: origin, size: drawSize)
    }
}

#if canImport(UIKit)

// MARK: - Sheet payload

/// Identifiable wrapper so a picked image can drive `.sheet(item:)`.
struct CroppableAvatar: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Crop view

/// Pan-and-zoom crop for the marketplace profile picture. The user positions the
/// image inside a 16:9 window that matches the hero banner; `onCrop` receives the
/// exported JPEG, ready for `uploadAvatar(data:)`.
struct AvatarCropView: View {

    let image: UIImage
    let onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Committed transform (updated when a gesture ends).
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// In-flight gesture deltas.
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    /// The crop window's point size, captured for export.
    @State private var window: CGSize = .zero

    private var liveZoom: CGFloat {
        AvatarCropGeometry.clampZoom(zoom * pinch)
    }

    private func liveOffset(in windowSize: CGSize) -> CGSize {
        AvatarCropGeometry.clampOffset(
            CGSize(width: offset.width + pan.width, height: offset.height + pan.height),
            imageSize: image.size,
            windowSize: windowSize,
            zoom: liveZoom
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geo in
                    let windowWidth = geo.size.width
                    let windowHeight = windowWidth / AvatarCrop.aspectRatio
                    let windowSize = CGSize(width: windowWidth, height: windowHeight)

                    VStack(spacing: 20) {
                        Spacer(minLength: 0)
                        cropWindow(windowSize)
                        hint
                        Spacer(minLength: 0)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear { window = windowSize }
                    .onChange(of: windowSize) { _, new in window = new }
                }
            }
            .navigationTitle(String(localized: "Position Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Use Photo")) {
                        if let data = exportJPEG() {
                            Haptics.tap()
                            onCrop(data)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.avatarCrop)
    }

    // MARK: Window

    private func cropWindow(_ windowSize: CGSize) -> some View {
        let scale = AvatarCropGeometry.baseScale(imageSize: image.size, windowSize: windowSize) * liveZoom
        let current = liveOffset(in: windowSize)

        return Image(uiImage: image)
            .resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .offset(x: current.width, y: current.height)
            // Collapse the oversized image down to the crop window, then clip.
            .frame(width: windowSize.width, height: windowSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Border sits *after* the clip so the stroke isn't shaved at the corners.
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
            }
            // Gestures target the window, not the (much larger) image.
            .contentShape(Rectangle())
            .gesture(panGesture(windowSize).simultaneously(with: zoomGesture(windowSize)))
            .accessibilityLabel(String(localized: "Drag to reposition, pinch to zoom"))
    }

    private var hint: some View {
        Text(String(localized: "Drag to reposition · Pinch to zoom"))
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: Gestures

    private func panGesture(_ windowSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($pan) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = AvatarCropGeometry.clampOffset(
                    CGSize(width: offset.width + value.translation.width,
                           height: offset.height + value.translation.height),
                    imageSize: image.size,
                    windowSize: windowSize,
                    zoom: zoom
                )
            }
    }

    private func zoomGesture(_ windowSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                zoom = AvatarCropGeometry.clampZoom(zoom * value.magnification)
                // Zooming out can leave the image short of the window edges.
                offset = AvatarCropGeometry.clampOffset(
                    offset, imageSize: image.size, windowSize: windowSize, zoom: zoom
                )
            }
    }

    // MARK: Export

    /// Renders exactly what the crop window shows into `AvatarCrop.outputSize`.
    /// Drawing outside the canvas is clipped by the renderer, and the offset clamp
    /// guarantees full coverage — so the export never contains empty pixels.
    private func exportJPEG() -> Data? {
        guard window.width > 0 else { return image.jpegData(compressionQuality: AvatarCrop.jpegQuality) }
        let rect = AvatarCropGeometry.drawRect(
            imageSize: image.size,
            windowSize: window,
            zoom: zoom,
            offset: offset,
            outputSize: AvatarCrop.outputSize
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1        // output points == output pixels
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: AvatarCrop.outputSize, format: format)
        let cropped = renderer.image { _ in image.draw(in: rect) }
        return cropped.jpegData(compressionQuality: AvatarCrop.jpegQuality)
    }
}

#endif
