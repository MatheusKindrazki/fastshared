import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

@MainActor
enum AppStoreScreenshotExporter {
    static let launchArgument = "--fastshared-export-appstore-screenshots"
    static let outputDirectoryEnvironmentKey = "FASTSHARED_SCREENSHOT_OUTPUT_DIR"

    private static let width: CGFloat = 1440
    private static let height: CGFloat = 900
    private static let scale: CGFloat = 2

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func exportAllIfNeeded() async {
        guard isEnabled else { return }
        do {
            guard let outputDirectory = ProcessInfo.processInfo.environment[outputDirectoryEnvironmentKey],
                  !outputDirectory.isEmpty else {
                throw ExportError.missingOutputDirectory
            }
            try exportAll(to: URL(fileURLWithPath: outputDirectory, isDirectory: true))
            NSApp.terminate(nil)
        } catch {
            fputs("FastShared App Store screenshot export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func exportAll(to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for (index, scene) in AppStoreScreenshotScene.allCases.enumerated() {
            let view = AppStoreScreenshotHostView(scene: scene, useScrollView: false)
                .frame(width: width, height: height)

            let renderer = ImageRenderer(content: view)
            renderer.scale = scale

            guard let image = renderer.nsImage else {
                throw ExportError.renderFailed(scene.rawValue)
            }

            let filename = String(format: "%02d_APP_DESKTOP_%@.png", index + 1, scene.fileSlug)
            let target = outputDirectory.appendingPathComponent(filename)
            try writePNG(image: image, to: target)
        }
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.pngEncodingFailed(url.lastPathComponent)
        }
        try pngData.write(to: url, options: .atomic)
    }

    private enum ExportError: LocalizedError {
        case missingOutputDirectory
        case renderFailed(String)
        case pngEncodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingOutputDirectory:
                return "Missing \(outputDirectoryEnvironmentKey)."
            case .renderFailed(let scene):
                return "Could not render screenshot scene \(scene)."
            case .pngEncodingFailed(let filename):
                return "Could not encode PNG \(filename)."
            }
        }
    }
}
#endif
