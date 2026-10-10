import CoreGraphics
import Foundation
import ImageIO

/// Runs the system interactive selector (`screencapture -i -x`) and returns the captured image,
/// or nil if the user cancelled (Esc) or anything failed.
enum Capturer {
    static func capture() async -> CGImage? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }

        let launched: Bool = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", url.path]
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                NSLog("Screenshot: failed to launch screencapture: \(error)")
                continuation.resume(returning: false)
            }
        }
        guard launched else { return nil }

        // Read fully into memory before the file is deleted (ImageIO may decode lazily).
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
