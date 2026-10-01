import AppKit
import SwiftUI

struct CropSettings {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
}

enum CropGeometry {
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
    let onApply: (NSImage, CropSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat
    @State private var offset: CGSize
    @State private var cropFailed = false

    private let viewport = CGSize(width: 480, height: 480 * 274 / 377)

    init(source: NSImage, initial: CropSettings,
         onApply: @escaping (NSImage, CropSettings) -> Void) {
        self.source = source
        self.initial = initial
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
                Text("画像をドラッグするか二本指でスクロールして位置を調整し、ピンチ操作かスライダーで拡大縮小します。枠内がカレンダーに使用されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        .frame(width: 560)
        .alert("画像を切り抜けませんでした", isPresented: $cropFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    private func applyCrop() {
        guard let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            cropFailed = true
            return
        }
        let settings = CropSettings(zoom: zoom, offset: offset)
        let size = CGSize(width: image.width, height: image.height)
        let rect = CropGeometry.sourceRect(imageSize: size, viewport: viewport, settings: settings)
        let pixelRect = CGRect(x: floor(rect.minX), y: floor(rect.minY),
                               width: ceil(rect.width), height: ceil(rect.height))
            .intersection(CGRect(origin: .zero, size: size))
        guard let cropped = image.cropping(to: pixelRect),
              cropped.width > 0, cropped.height > 0 else {
            cropFailed = true
            return
        }
        onApply(NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)),
                settings)
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
