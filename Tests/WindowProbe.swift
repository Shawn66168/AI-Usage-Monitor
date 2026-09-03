import CoreGraphics
import Foundation

@main
struct WindowProbe {
    static func main() {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            print("WINDOW_LIST_UNAVAILABLE")
            exit(1)
        }

        let matches = windows.filter { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            return owner.localizedCaseInsensitiveContains("AIUsageMonitor")
                || owner.localizedCaseInsensitiveContains("AI Usage Monitor")
        }

        if matches.isEmpty {
            print("NO_VISIBLE_WINDOW")
            exit(2)
        }

        for window in matches {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            print("owner=\(owner) title=\(title) layer=\(layer) alpha=\(alpha) bounds=\(bounds)")
        }
    }
}
