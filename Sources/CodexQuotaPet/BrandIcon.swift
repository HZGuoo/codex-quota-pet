import AppKit
import SwiftUI

@MainActor
enum BrandIcon {
    static let accentColor = Color(red: 1.0, green: 0.20, blue: 0.17)

    static let colorImage: NSImage? = loadImage(
        isTemplate: false,
        pointSize: NSSize(width: 34, height: 34)
    )
    static let templateImage: NSImage? = loadImage(
        isTemplate: true,
        pointSize: NSSize(width: 18, height: 18)
    )

    private static func loadImage(isTemplate: Bool, pointSize: NSSize) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuIconColor", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = pointSize
        image.isTemplate = isTemplate
        return image
    }
}
