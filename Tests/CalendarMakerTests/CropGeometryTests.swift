import XCTest
@testable import CalendarMaker

final class CropGeometryTests: XCTestCase {
    func testCenterCropMatchesViewportAspectRatio() {
        let viewport = CGSize(width: 480, height: 480 * 274 / 377)
        let rect = CropGeometry.sourceRect(
            imageSize: CGSize(width: 1200, height: 800),
            viewport: viewport,
            settings: CropSettings()
        )

        XCTAssertEqual(rect.height, 800, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 600, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 400, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, viewport.width / viewport.height, accuracy: 0.001)
    }

    func testZoomAndDragRemainInsideImage() {
        let image = CGSize(width: 1200, height: 800)
        let viewport = CGSize(width: 480, height: 480 * 274 / 377)
        let offset = CropGeometry.clampedOffset(
            CGSize(width: 10_000, height: -10_000),
            imageSize: image, viewport: viewport, zoom: 2
        )
        let rect = CropGeometry.sourceRect(
            imageSize: image, viewport: viewport,
            settings: CropSettings(zoom: 2, offset: offset)
        )

        XCTAssertGreaterThanOrEqual(rect.minX, -0.001)
        XCTAssertGreaterThanOrEqual(rect.minY, -0.001)
        XCTAssertLessThanOrEqual(rect.maxX, image.width + 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, image.height + 0.001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
    }

    func testDraggingImageMovesCropInOppositeDirection() {
        let image = CGSize(width: 1200, height: 800)
        let viewport = CGSize(width: 480, height: 480 * 274 / 377)
        let center = CropGeometry.sourceRect(
            imageSize: image, viewport: viewport,
            settings: CropSettings(zoom: 2)
        )
        let moved = CropGeometry.sourceRect(
            imageSize: image, viewport: viewport,
            settings: CropSettings(zoom: 2, offset: CGSize(width: 40, height: -20))
        )

        XCTAssertLessThan(moved.minX, center.minX)
        XCTAssertGreaterThan(moved.minY, center.minY)
    }

    func testZoomKeepsCurrentCropCenter() {
        let image = CGSize(width: 1200, height: 800)
        let viewport = CGSize(width: 480, height: 480 * 274 / 377)
        let startingOffset = CGSize(width: 60, height: -40)
        let before = CropGeometry.sourceRect(
            imageSize: image, viewport: viewport,
            settings: CropSettings(zoom: 1.5, offset: startingOffset)
        )
        let zoomedOffset = CropGeometry.offsetPreservingCenter(
            startingOffset, imageSize: image, viewport: viewport,
            from: 1.5, to: 2.5
        )
        let after = CropGeometry.sourceRect(
            imageSize: image, viewport: viewport,
            settings: CropSettings(zoom: 2.5, offset: zoomedOffset)
        )

        XCTAssertEqual(after.midX, before.midX, accuracy: 0.001)
        XCTAssertEqual(after.midY, before.midY, accuracy: 0.001)
    }
}
