import Foundation
import CoreGraphics

/// World geometry is independent of source image pixels. Replacing an asset never changes
/// section positions, scroll distance, or the motion controller's coordinate system.
@MainActor
enum WorldSectionLayout {
    static func frame(index: Int, position: Double, width: Double,
                      sectionHeight height: Double, overlap: Double, displayScale: Double) -> CGRect {
        let scale = max(displayScale, 1)
        // Compute both edges from world coordinates so neighbouring sections share an edge,
        // including at fractional scroll offsets and on 2x/3x displays.
        let step = height - overlap
        let top = ((Double(index) * step - position) * scale).rounded() / scale
        let bottom = ((Double(index) * step + height - position) * scale).rounded() / scale
        return CGRect(x: 0, y: top, width: width, height: bottom - top)
    }

    /// Aspect-fills the image into `frame`. `topCrop` (0...<1) hides that fraction of the image's
    /// top edge (e.g. the sky of a cross-section) so neighbouring sections read as continuous ground.
    static func aspectFillRect(imageSize: CGSize, in frame: CGRect, topCrop: Double = 0) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let crop = min(max(topCrop, 0), 0.9)
        let scale = max(frame.width / imageSize.width, frame.height / (imageSize.height * (1 - crop)))
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        if crop == 0 {
            return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
        }
        return CGRect(x: frame.midX - width / 2, y: frame.minY - height * crop, width: width, height: height)
    }
}
