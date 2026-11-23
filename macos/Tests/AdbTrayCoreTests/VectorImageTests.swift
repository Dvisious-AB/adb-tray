@testable import AdbTrayCore
import CoreGraphics
import ImageIO
import XCTest

final class VectorImageTests: XCTestCase {
    static let branding = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../../branding").standardizedFileURL

    private func assertRect(_ rect: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.01,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    func testArcsMakeACircle() throws {
        let path = try PathParser.path("M0,10 A10,10 0 1 0 20,10 A10,10 0 1 0 0,10Z")
        assertRect(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    func testEllipseArcsAndRelativeCommands() throws {
        // The eyes in the Appninjas symbol: an ellipse 6.6 wide and 8.4 high, centred on (14, 28).
        let eye = try PathParser.path("M10.7 28A3.3 4.2 0 1 0 17.3 28A3.3 4.2 0 1 0 10.7 28Z")
        assertRect(eye.boundingBoxOfPath, CGRect(x: 10.7, y: 23.8, width: 6.6, height: 8.4))
        let square = try PathParser.path("m10 10h5v5h-5z")
        assertRect(square.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 5, height: 5))
    }

    func testNumbersThatRunTogether() throws {
        XCTAssertEqual(try PathParser.numbers("8.5.5-1-2e1,3"), [8.5, 0.5, -1, -20, 3])
        let path = try PathParser.path("M0 0L1-1 2 0")  // implicit lineto after the second pair
        assertRect(path.boundingBoxOfPath, CGRect(x: 0, y: -1, width: 2, height: 1))
    }

    func testRejectsUnknownCommands() {
        XCTAssertThrowsError(try PathParser.path("M0 0 X 1 1"))
    }

    func testEveryPhosphorIconParsesInsideItsViewBox() throws {
        let folder = Self.branding.appendingPathComponent("phosphor")
        let icons = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".svg") }
        XCTAssertGreaterThanOrEqual(icons.count, 10)
        for name in icons {
            let image = try VectorImage(contentsOf: folder.appendingPathComponent(name))
            XCTAssertEqual(image.viewBox, CGRect(x: 0, y: 0, width: 256, height: 256), name)
            XCTAssertFalse(image.shapes.isEmpty, name)
            for shape in image.shapes {
                XCTAssertEqual(shape.fill, .currentColor, name)
                XCTAssertTrue(image.viewBox.insetBy(dx: -1, dy: -1).contains(shape.path.boundingBoxOfPath), name)
            }
        }
    }

    func testSymbolKeepsItsColours() throws {
        let image = try VectorImage(contentsOf: Self.branding.appendingPathComponent("symbol.svg"))
        XCTAssertEqual(image.viewBox, CGRect(x: 0, y: 0, width: 62.83, height: 46))
        XCTAssertEqual(image.shapes.first?.fill, .currentColor)
        XCTAssertTrue(image.shapes.first?.evenOdd ?? false)
        XCTAssertEqual(image.shapes.dropFirst().map(\.fill), Array(repeating: VectorImage.fill("#0b6670"), count: 4))
        assertRect(image.shapes[0].path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 46, height: 46))
    }

    /// Renders the app icon and reads pixels back: the tile, the hood, the band and the eye slit.
    func testAppIconRendersTheSymbolOnTheTile() throws {
        let icon = try VectorImage(contentsOf: Self.branding.appendingPathComponent("appninjas-adb.svg"))
        let data = try XCTUnwrap(icon.pngData(pixels: 256))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 256)

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 256, height: 256, bitsPerComponent: 8,
                                              bytesPerRow: 256 * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {  // y from the top
            let offset = (y * 256 + x) * 4
            return Array(pixels[offset..<offset + 4])
        }
        func near(_ actual: [UInt8], _ expected: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
            for (a, e) in zip(actual, expected) {
                XCTAssertLessThanOrEqual(abs(Int(a) - Int(e)), 3, "\(actual) vs \(expected)", file: file, line: line)
            }
        }
        // Symbol scale in the 256 px rendering: 560/62.83 * 256/1024, origin (58, 76.75).
        let scale = 560 / 62.83 / 4, originX = 58.0, originY = 76.75
        func at(_ x: Double, _ y: Double) -> [UInt8] { pixel(Int(originX + x * scale), Int(originY + y * scale)) }

        near(pixel(2, 2), [0, 0, 0, 0])  // outside the tile: transparent
        near(pixel(40, 40), [0xf6, 0xf7, 0xf7, 255])  // the tile
        near(at(23, 4), [0x12, 0x17, 0x18, 255])  // the top of the hood
        near(at(23, 12.5), [0x0b, 0x66, 0x70, 255])  // the band
        near(at(23, 28), [0xf6, 0xf7, 0xf7, 255])  // the eye slit shows the tile through
        near(at(14, 28), [0x12, 0x17, 0x18, 255])  // an eye
    }
}
