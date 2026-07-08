import CoreVideo
import Foundation

enum LookSmoke {
    static func run(settingsURL: URL? = nil) -> Int32 {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            1280,
            720,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            print("Look smoke failed: could not create pixel buffer (\(status))")
            return 1
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let pointer = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    pointer[offset + 0] = UInt8((x + y) % 255)
                    pointer[offset + 1] = UInt8((x / 5) % 255)
                    pointer[offset + 2] = UInt8((y / 3) % 255)
                    pointer[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let renderer = LookRenderer()
        let settings: LookSettings
        if let settingsURL {
            do {
                let data = try Data(contentsOf: settingsURL)
                settings = try JSONDecoder().decode(LookSettings.self, from: data)
            } catch {
                print("Look smoke failed: could not decode \(settingsURL.path): \(error.localizedDescription)")
                return 1
            }
        } else {
            settings = LookPresetCatalog.presets.first { $0.name == "C1 Signature" } ?? .neutral
        }
        guard let image = renderer.render(pixelBuffer: pixelBuffer, settings: settings) else {
            print("Look smoke failed: renderer returned nil")
            return 1
        }
        print("Look smoke ok: \(image.width)x\(image.height), preset=\(settings.name), warmth=\(settings.warmth), blur=\(settings.backgroundBlur)")
        return 0
    }

    static func runActivePersistenceSmoke() -> Int32 {
        let previous = LookPresetStore.loadActive()
        defer {
            if let previous {
                LookPresetStore.saveActive(previous)
            } else {
                LookPresetStore.clearActive()
            }
        }
        var look = LookPresetCatalog.presets.first { $0.name == "C1 Signature" } ?? .neutral
        look.name = "Persistence Smoke"
        look.studioMatchAmount = 0.37
        LookPresetStore.saveActive(look)
        guard let restored = LookPresetStore.loadActive() else {
            print("Active look smoke failed: no active look restored")
            return 1
        }
        guard restored.name == look.name,
              abs(restored.studioMatchAmount - look.studioMatchAmount) < 0.0001 else {
            print("Active look smoke failed: restored \(restored.name), match=\(restored.studioMatchAmount)")
            return 1
        }
        print("Active look smoke ok: \(restored.name), match=\(restored.studioMatchAmount)")
        return 0
    }
}
