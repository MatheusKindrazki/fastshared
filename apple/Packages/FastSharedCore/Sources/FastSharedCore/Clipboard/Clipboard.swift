import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public protocol ClipboardProtocol: Sendable {
    func copy(_ string: String)
}

public enum Clipboard {
    public static func make() -> ClipboardProtocol {
        #if canImport(UIKit)
        return UIKitClipboard()
        #elseif canImport(AppKit)
        return AppKitClipboard()
        #else
        return NoopClipboard()
        #endif
    }
}

#if canImport(UIKit)
public struct UIKitClipboard: ClipboardProtocol {
    public init() {}
    public func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
#endif

#if canImport(AppKit)
public struct AppKitClipboard: ClipboardProtocol {
    public init() {}
    public func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
#endif

public struct NoopClipboard: ClipboardProtocol {
    public init() {}
    public func copy(_ string: String) {}
}
