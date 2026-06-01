import SwiftUI

/// SwiftUI wrapper around `AppIconRenderer` for in-popover use.
/// Caches the rendered image per size in a static dictionary so resizing
/// or rebuilding the view doesn't re-rasterise on every body call.
struct AppMarkView: View {
    var size: CGFloat
    var template: Bool = false

    var body: some View {
        if let image = Self.cached(size: size, template: template) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private struct CacheKey: Hashable {
        let size: Int
        let template: Bool
    }

    private static var cache: [CacheKey: NSImage] = [:]

    private static func cached(size: CGFloat, template: Bool) -> NSImage? {
        let key = CacheKey(size: Int(size.rounded()), template: template)
        if let hit = cache[key] { return hit }
        guard let image = AppIconRenderer.nsImage(size: size, template: template) else {
            return nil
        }
        cache[key] = image
        return image
    }
}
