import Foundation
import CoreGraphics

/// World geometry is independent of source image pixels. Replacing an asset never changes
/// section positions, scroll distance, or the motion controller's coordinate system.
@MainActor
enum WorldSectionLayout {
    static func frame(index: Int, position: Double, width: Double,
                      displayScale: Double) -> CGRect {
        let scale = max(displayScale, 1)
        let height = WorldMotionController.sectionHeight
        // Compute both edges from world coordinates so neighbouring sections share an edge,
        // including at fractional scroll offsets and on 2x/3x displays.
        let top = ((Double(index) * height - position) * scale).rounded() / scale
        let bottom = ((Double(index + 1) * height - position) * scale).rounded() / scale
        return CGRect(x: 0, y: top, width: width, height: bottom - top)
    }

    static func aspectFillRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                      width: width, height: height)
    }
}
