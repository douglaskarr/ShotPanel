import AppKit
import ImageIO

enum ImageThumb {
    static func pixelSize(url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = number(props[kCGImagePropertyPixelWidth]),
              let height = number(props[kCGImagePropertyPixelHeight]),
              width > 0, height > 0 else {
            return CGSize(width: 16, height: 10)
        }
        // Orientations 5 through 8 swap the axes. The thumbnail transform
        // bakes that in, so the widget's aspect ratio has to match.
        let orientation = number(props[kCGImagePropertyOrientation]) ?? 1
        if orientation >= 5 && orientation <= 8 {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    static func make(url: URL, maxPixel: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func number(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat(truncating: $0) }
    }
}
