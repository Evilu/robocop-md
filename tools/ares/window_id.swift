import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
    for window in list {
        if let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
           let number = window[kCGWindowNumber as String] as? Int,
           let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
            print(number)
        }
    }
}
