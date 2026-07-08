import AVFoundation
import CoreMedia
import Foundation

enum AppleEffectsProbe {
    static func run() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first(where: { device in
            device.localizedName.lowercased().contains("opal") || device.uniqueID.lowercased().contains("f63b")
        }) else {
            print("Apple Effects: Opal C1 not found")
            return
        }

        print("Device: \(device.localizedName)")
        print("Portrait enabled in Control Center: \(AVCaptureDevice.isPortraitEffectEnabled)")
        print("Portrait active on C1 current format: \(device.isPortraitEffectActive)")
        print("Center Stage enabled in Control Center: \(AVCaptureDevice.isCenterStageEnabled)")
        print("Center Stage active on C1 current format: \(device.isCenterStageActive)")
        if #available(macOS 13.0, *) {
            print("Studio Light enabled in Control Center: \(AVCaptureDevice.isStudioLightEnabled)")
            print("Studio Light active on C1 current format: \(device.isStudioLightActive)")
        }

        let rows = device.formats.compactMap { format -> String? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let frameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let studioLightSupported: Bool
            if #available(macOS 13.0, *) {
                studioLightSupported = format.isStudioLightSupported
            } else {
                studioLightSupported = false
            }
            guard format.isPortraitEffectSupported || format.isCenterStageSupported || studioLightSupported else {
                return nil
            }
            return "- \(dimensions.width)x\(dimensions.height) @ \(String(format: "%.2f", frameRate)) fps: portrait=\(format.isPortraitEffectSupported), studioLight=\(studioLightSupported), centerStage=\(format.isCenterStageSupported)"
        }

        if rows.isEmpty {
            print("Supported Apple effect formats: none reported for C1")
        } else {
            print("Supported Apple effect formats:")
            rows.forEach { print($0) }
        }
    }
}
