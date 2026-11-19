import Foundation
import ImageIO

/// Decode any supported image (including HEIC) and re-encode as a downscaled JPEG for cheap vision calls.
func downscaleJPEG(path: String, maxDim: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary) else {
        return nil
    }
    let opts = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDim,
        kCGImageSourceCreateThumbnailWithTransform: true
    ] as CFDictionary
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}
