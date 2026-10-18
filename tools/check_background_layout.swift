import Foundation
import CoreGraphics

/// Run with the production layout and motion sources; no Xcode test target is required.
@main
struct BackgroundLayoutChecks {
    @MainActor static func main() {
        let sizes = [CGSize(width: 603, height: 603), CGSize(width: 1206, height: 3000),
                     CGSize(width: 2000, height: 1000)]
        var checks = 0
        for width in [320.0, 375, 402, 430, 852] {
            for scale in [2.0, 3.0] {
                let sectionHeight = width * WorldMotionController.sectionAspect
                let overlap = sectionHeight * WorldMotionController.overlapFraction
                for position in stride(from: -600.25, through: sectionHeight * Double(WorldMotionController.imageCount) + 600, by: 37.125) {
                    for index in 0..<WorldMotionController.imageCount {
                        let frame = WorldSectionLayout.frame(index: index, position: position,
                                                             width: width, sectionHeight: sectionHeight, overlap: overlap,
                                                             displayScale: scale)
                        let next = WorldSectionLayout.frame(index: index + 1, position: position,
                                                            width: width, sectionHeight: sectionHeight, overlap: overlap,
                                                             displayScale: scale)
                        precondition(abs((frame.maxY - next.minY) - overlap) < 1.0 / scale + 0.000001, "neighbouring sections must overlap by the blend height")
                        for size in sizes {
                            let image = WorldSectionLayout.aspectFillRect(imageSize: size, in: frame)
                            precondition(image.minX <= frame.minX + 0.000001 &&
                                         image.minY <= frame.minY + 0.000001 &&
                                         image.maxX >= frame.maxX - 0.000001 &&
                                         image.maxY >= frame.maxY - 0.000001, "image must cover frame")
                            precondition(abs(image.width / image.height - size.width / size.height) < 0.000001,
                                         "image aspect ratio must be preserved")
                            checks += 1
                        }
                    }
                }
            }
        }
        print("PASS: \(checks) image coverage/aspect-ratio checks; all \(WorldMotionController.imageCount) image seams on 2x/3x displays")
    }
}
