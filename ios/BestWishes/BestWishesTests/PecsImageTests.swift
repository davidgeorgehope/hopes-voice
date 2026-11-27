import UIKit
import XCTest
@testable import BestWishes

final class PecsImageTests: XCTestCase {
    func testFillingSubjectMakesTheSubjectFillMostOfTheCanvas() {
        let source = Self.syntheticCard()
        let filled = PecsImage.fillingSubject(source)
        guard let bbox = PecsImage.contentPixelBBox(filled) else {
            XCTFail("expected a subject bbox after trim")
            return
        }
        let content = max(bbox.width, bbox.height)
        let fill = content / CGFloat(filled.cgImage?.width ?? 0)
        XCTAssertGreaterThanOrEqual(fill, 0.84)
        XCTAssertLessThanOrEqual(fill, 0.92)
    }

    func testFillingSubjectIsIdempotent() {
        let first = PecsImage.fillingSubject(Self.syntheticCard())
        let second = PecsImage.fillingSubject(first)
        XCTAssertEqual(first.cgImage?.width, second.cgImage?.width)
        XCTAssertEqual(PecsImage.contentPixelBBox(first), PecsImage.contentPixelBBox(second))
    }

    func testAllWhiteImageIsLeftAlone() {
        let white = Self.solid(color: .white, size: 64)
        XCTAssertNil(PecsImage.contentPixelBBox(white))
        let out = PecsImage.fillingSubject(white)
        XCTAssertEqual(out.cgImage?.width, white.cgImage?.width)
        XCTAssertEqual(out.cgImage?.height, white.cgImage?.height)
    }

    private static func syntheticCard() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 80, y: 80, width: 40, height: 40))
        }
    }

    private static func solid(color: UIColor, size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
