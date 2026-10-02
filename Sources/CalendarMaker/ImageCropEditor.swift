import AppKit
import SwiftUI

struct CropSettings {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
}

enum CropGeometry {
    static func viewport(photoSize: CGSize, fittingWithin bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / photoSize.width, bounds.height / photoSize.height)
        return CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
    }

    static func clampedOffset(_ offset: CGSize, imageSize: CGSize,
                              viewport: CGSize, zoom: CGFloat) -> CGSize {
        let baseScale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let maximumX = max(0, (imageSize.width * baseScale * zoom - viewport.width) / 2)
        let maximumY = max(0, (imageSize.height * baseScale * zoom - viewport.height) / 2)
        return CGSize(width: min(max(offset.width, -maximumX), maximumX),
                      height: min(max(offset.height, -maximumY), maximumY))
    }

    static func offsetPreservingCenter(_ offset: CGSize, imageSize: CGSize,
                                       viewport: CGSize, from oldZoom: CGFloat,
                                       to newZoom: CGFloat) -> CGSize {
        let ratio = newZoom / oldZoom
        return clampedOffset(
            CGSize(width: offset.width * ratio, height: offset.height * ratio),
            imageSize: imageSize, viewport: viewport, zoom: newZoom
        )
    }

    static func sourceRect(imageSize: CGSize, viewport: CGSize,
                           settings: CropSettings) -> CGRect {
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
            * settings.zoom
        let visibleSize = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        let offset = clampedOffset(settings.offset, imageSize: imageSize,
                                   viewport: viewport, zoom: settings.zoom)
        let origin = CGPoint(x: (imageSize.width - visibleSize.width) / 2 - offset.width / scale,
                             y: (imageSize.height - visibleSize.height) / 2 - offset.height / scale)
        return CGRect(origin: origin, size: visibleSize)
    }
}

struct ImageCropEditor: View {
    let source: NSImage
    let initial: CropSettings
    let photoSize: CGSize
    let templateName: String
    let pagePreview: (NSImage?) -> AnyView
    let onApply: (NSImage, CropSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat
    @State private var offset: CGSize
    @State private var cropFailed = false

    private let pageSize = CGSize(width: 595.28, height: 841.89)
    private let pageScale: CGFloat = 0.45
    private var viewport: CGSize {
        CropGeometry.viewport(photoSize: photoSize, fittingWithin: CGSize(width: 480, height: 320))
    }

    init(source: NSImage, initial: CropSettings, photoSize: CGSize,
         templateName: String, pagePreview: @escaping (NSImage?) -> AnyView,
         onApply: @escaping (NSImage, CropSettings) -> Void) {
        self.source = source
        self.initial = initial
        self.photoSize = photoSize
        self.templateName = templateName
        self.pagePreview = pagePreview
        self.onApply = onApply
        _zoom = State(initialValue: initial.zoom)
        _offset = State(initialValue: initial.offset)
    }

    private var pixelSize: CGSize {
        guard let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return source.size
        }
        return CGSize(width: image.width, height: image.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("アイキャッチ画像を編集")
                    .font(.title2.bold())
                Text("写真を動かすと、右の\(templateName)の紙面にも反映されます。二本指で移動・拡大縮小できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("写真の切り抜き範囲")
                        .font(.headline)
                    cropCanvas
                        .frame(width: 480, height: 320)
                    zoomControl
                }
                .frame(width: 480)

                VStack(alignment: .leading, spacing: 12) {
                    Text("印刷イメージ · \(templateName)")
                        .font(.headline)
                    pagePreview(croppedImage(settings: CropSettings(zoom: zoom, offset: offset)))
                        .scaleEffect(pageScale, anchor: .topLeading)
                        .frame(width: pageSize.width * pageScale,
                               height: pageSize.height * pageScale,
                               alignment: .topLeading)
                        .overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
                }
            }

            HStack {
                Button("位置と倍率をリセット") {
                    zoom = 1
                    offset = .zero
                }
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("適用") { applyCrop() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 820)
        .alert("画像を切り抜けませんでした", isPresented: $cropFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    private var cropCanvas: some View {
            Image(nsImage: source)
                .resizable()
                .scaledToFill()
                .frame(width: viewport.width, height: viewport.height)
                .scaleEffect(zoom)
                .offset(offset)
                .frame(width: viewport.width, height: viewport.height)
                .clipped()
                .overlay(CropGrid().stroke(.white.opacity(0.7), lineWidth: 0.8))
                .overlay(Rectangle().stroke(.primary.opacity(0.45), lineWidth: 1))
                .overlay {
                    CropInteractionView(
                        onPan: { delta in
                            offset = CropGeometry.clampedOffset(
                                CGSize(width: offset.width + delta.width,
                                       height: offset.height + delta.height),
                                imageSize: pixelSize, viewport: viewport, zoom: zoom
                            )
                        },
                        onMagnify: { delta in
                            zoom = min(max(zoom * (1 + delta), 1), 3)
                        }
                    )
                }
                .accessibilityLabel("画像の切り抜き範囲。ドラッグまたは二本指で位置を調整")
    }

    private var zoomControl: some View {
            HStack {
                Text("縮小")
                Slider(value: $zoom, in: 1...3, step: 0.01) {
                    Text("拡大率")
                }
                .onChange(of: zoom) { oldValue, newValue in
                    offset = CropGeometry.offsetPreservingCenter(
                        offset, imageSize: pixelSize, viewport: viewport,
                        from: oldValue, to: newValue
                    )
                }
                Text("拡大")
                Text("\(Int(zoom * 100))%")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
    }

    private func croppedImage(settings: CropSettings) -> NSImage? {
        guard let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let size = CGSize(width: image.width, height: image.height)
        let rect = CropGeometry.sourceRect(imageSize: size, viewport: viewport, settings: settings)
        let pixelRect = CGRect(x: floor(rect.minX), y: floor(rect.minY),
                               width: ceil(rect.width), height: ceil(rect.height))
            .intersection(CGRect(origin: .zero, size: size))
        guard let cropped = image.cropping(to: pixelRect),
              cropped.width > 0, cropped.height > 0 else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func applyCrop() {
        let settings = CropSettings(zoom: zoom, offset: offset)
        guard let cropped = croppedImage(settings: settings) else {
            cropFailed = true
            return
        }
        onApply(cropped, settings)
        dismiss()
    }
}

private struct CropInteractionView: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onMagnify: (CGFloat) -> Void

    func makeNSView(context: Context) -> CropInteractionNSView {
        CropInteractionNSView()
    }

    func updateNSView(_ view: CropInteractionNSView, context: Context) {
        view.onPan = onPan
        view.onMagnify = onMagnify
    }
}

private final class CropInteractionNSView: NSView {
    var onPan: ((CGSize) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    private var lastDragLocation: NSPoint?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        lastDragLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let lastDragLocation {
            onPan?(CGSize(width: location.x - lastDragLocation.x,
                          height: location.y - lastDragLocation.y))
        }
        lastDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }
        onPan?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }
}

private struct CropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = rect.width * fraction
            let y = rect.height * fraction
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
