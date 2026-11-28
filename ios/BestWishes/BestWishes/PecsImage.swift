import SwiftUI
import UIKit

/// Tight-crop a PECS picture so the subject fills the card, not a huge white square.
enum PecsImage {
    /// Near-white cutoff (255 * 0.92 ≈ 235), matching the backend trimmer.
    static let whiteThreshold: UInt8 = 235
    /// Padding left around the subject after the crop, as a fraction of the canvas.
    static let marginFraction: CGFloat = 0.06

    /// Crop near-white margins and re-pad onto a square white canvas.
    static func fillingSubject(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = data[i]
                let g = data[i + 1]
                let b = data[i + 2]
                let a = data[i + 3]
                let isBackground = a < 8 || (r >= whiteThreshold && g >= whiteThreshold && b >= whiteThreshold)
                if !isBackground {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return image }

        let contentW = maxX - minX + 1
        let contentH = maxY - minY + 1
        let fill = max(1 - 2 * marginFraction, 0.5)
        var canvas = Int((CGFloat(max(contentW, contentH)) / fill).rounded())
        canvas = max(canvas, max(contentW, contentH) + 2)

        guard let cropped = cgImage.cropping(
            to: CGRect(x: minX, y: minY, width: contentW, height: contentH)
        ) else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: canvas, height: canvas),
            format: format
        )
        let rendered = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
            let origin = CGPoint(x: (canvas - contentW) / 2, y: (canvas - contentH) / 2)
            UIImage(cgImage: cropped, scale: 1, orientation: .up)
                .draw(in: CGRect(origin: origin, size: CGSize(width: contentW, height: contentH)))
        }
        guard let out = rendered.cgImage else { return rendered }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Bounding box of non-near-white pixels in pixel coordinates, or nil if empty.
    static func contentPixelBBox(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = data[i]
                let g = data[i + 1]
                let b = data[i + 2]
                let a = data[i + 3]
                let isBackground = a < 8 || (r >= whiteThreshold && g >= whiteThreshold && b >= whiteThreshold)
                if !isBackground {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// Renders a card picture so the (trimmed) subject fills the image well, with almost no padding.
struct PecsImageView: View {
    let image: UIImage?
    var remoteURL: URL? = nil
    var placeholderSize: CGFloat = 44

    var body: some View {
        ZStack {
            Theme.cream
            if let image {
                filled(image)
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit().padding(2)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: placeholderSize, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    default:
                        ProgressView()
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    /// `image` is already trimmed and downsampled by `ThumbnailCache`; drawing it costs nothing.
    private func filled(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .padding(2)
    }
}
