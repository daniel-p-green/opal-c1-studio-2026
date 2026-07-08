import Foundation

enum CameraControlKey: String, CaseIterable {
    case whiteBalanceTemperature
    case whiteBalanceAuto
    case focusAbsolute
    case focusAuto
    case exposureTime
    case exposureAuto
    case gain
    case brightness
    case contrast
    case saturation
    case sharpness
    case gamma
    case powerLineFrequency
    case zoomAbsolute
    case irisAbsolute

    var title: String {
        switch self {
        case .whiteBalanceTemperature: "White balance"
        case .whiteBalanceAuto: "Auto white balance"
        case .focusAbsolute: "Focus"
        case .focusAuto: "Auto focus"
        case .exposureTime: "Exposure"
        case .exposureAuto: "Auto exposure"
        case .gain: "Gain"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .sharpness: "Sharpness"
        case .gamma: "Gamma"
        case .powerLineFrequency: "Anti-flicker"
        case .zoomAbsolute: "Zoom"
        case .irisAbsolute: "Iris"
        }
    }

    var unit: String {
        switch self {
        case .whiteBalanceTemperature: "K"
        case .exposureTime: "100us"
        case .powerLineFrequency: "mode"
        default: ""
        }
    }
}

enum CameraControlValue: Equatable {
    case bool(Bool)
    case int(Int)
    case unavailable

    var displayValue: String {
        switch self {
        case .bool(let value): value ? "On" : "Off"
        case .int(let value): "\(value)"
        case .unavailable: "Unavailable"
        }
    }
}

struct CameraControlCapability: Equatable {
    let key: CameraControlKey
    var readable: Bool
    var writable: Bool
    var minimum: Int?
    var maximum: Int?
    var step: Int?
    var defaultValue: CameraControlValue
    var currentValue: CameraControlValue
    var backend: String
    var lastError: String?
    var entity: Int?
    var selector: Int?

    var status: String {
        if let lastError {
            return lastError
        }
        if writable {
            return "Ready through \(backend)"
        }
        if readable {
            return "Read-only through \(backend)"
        }
        return "Blocked"
    }
}

struct CameraPreset {
    let name: String
    let subtitle: String
    let values: [CameraControlKey: CameraControlValue]
}

protocol CameraControlTransport {
    func discoverC1() -> Bool
    func readCapabilities() -> [CameraControlCapability]
    func readValue(_ key: CameraControlKey) -> CameraControlValue
    func writeValue(_ key: CameraControlKey, value: CameraControlValue) -> Result<Void, CameraControlTransportError>
    func applyPreset(_ preset: CameraPreset) -> [CameraControlKey: Result<Void, CameraControlTransportError>]
    func resetToAuto() -> [CameraControlKey: Result<Void, CameraControlTransportError>]
}

struct CameraControlTransportError: Error, CustomStringConvertible, Equatable {
    let description: String
}

final class DescriptorBackedControlTransport: CameraControlTransport {
    private let writeBlockedReason = "USB write path is disabled. Run Lab Mode, then relaunch with C1_STUDIO_ENABLE_UVC_WRITES=1 only after helper access is proven."
    private var experimentalWritesEnabled: Bool {
        ProcessInfo.processInfo.environment["C1_STUDIO_ENABLE_UVC_WRITES"] == "1"
    }

    func discoverC1() -> Bool {
        true
    }

    func readCapabilities() -> [CameraControlCapability] {
        [
            bool(.whiteBalanceAuto, entity: 3, selector: 15, defaultValue: true),
            int(.whiteBalanceTemperature, min: 2500, max: 8000, step: 50, defaultValue: 5000, entity: 3, selector: 10),
            bool(.focusAuto, entity: 1, selector: 17, defaultValue: true),
            int(.focusAbsolute, min: 0, max: 255, step: 1, defaultValue: 128, entity: 1, selector: 6),
            bool(.exposureAuto, entity: 1, selector: 2, defaultValue: true),
            int(.exposureTime, min: 1, max: 10000, step: 1, defaultValue: 333, entity: 1, selector: 4),
            int(.gain, min: 0, max: 255, step: 1, defaultValue: 64, entity: 3, selector: 4),
            int(.brightness, min: -64, max: 64, step: 1, defaultValue: 0, entity: 3, selector: 2),
            int(.contrast, min: 0, max: 64, step: 1, defaultValue: 32, entity: 3, selector: 3),
            int(.saturation, min: 0, max: 128, step: 1, defaultValue: 64, entity: 3, selector: 7),
            int(.sharpness, min: 0, max: 64, step: 1, defaultValue: 16, entity: 3, selector: 8),
            int(.gamma, min: 1, max: 500, step: 1, defaultValue: 100, entity: 3, selector: 9),
            int(.powerLineFrequency, min: 0, max: 2, step: 1, defaultValue: 2, entity: 3, selector: 5),
            int(.zoomAbsolute, min: 100, max: 400, step: 1, defaultValue: 100, entity: 1, selector: 10, exposed: true),
            int(.irisAbsolute, min: 0, max: 0, step: 1, defaultValue: 0, entity: 1, selector: 8, exposed: false)
        ]
    }

    func readValue(_ key: CameraControlKey) -> CameraControlValue {
        readCapabilities().first(where: { $0.key == key })?.currentValue ?? .unavailable
    }

    func writeValue(_ key: CameraControlKey, value: CameraControlValue) -> Result<Void, CameraControlTransportError> {
        guard ProcessInfo.processInfo.environment["C1_STUDIO_ENABLE_UVC_WRITES"] == "1" else {
            return .failure(CameraControlTransportError(description: writeBlockedReason))
        }
        guard let intValue = value.helperIntValue else {
            return .failure(CameraControlTransportError(description: "\(key.title) value is not writable"))
        }
        let scriptURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return .failure(CameraControlTransportError(description: "UVC helper not found at \(scriptURL.path)"))
        }

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = [
            "--json",
            "--write-control", key.rawValue,
            "--value", "\(intValue)",
            "--yes-write",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let writeResult = parsed?["write_result"] as? [String: Any]
            if writeResult?["ok"] as? Bool == true {
                return .success(())
            }
            let error = writeResult?["error"] as? String ?? "helper write failed"
            return .failure(CameraControlTransportError(description: error))
        } catch {
            return .failure(CameraControlTransportError(description: error.localizedDescription))
        }
    }

    func applyPreset(_ preset: CameraPreset) -> [CameraControlKey: Result<Void, CameraControlTransportError>] {
        Dictionary(uniqueKeysWithValues: preset.values.map { key, value in
            (key, writeValue(key, value: value))
        })
    }

    func resetToAuto() -> [CameraControlKey: Result<Void, CameraControlTransportError>] {
        [
            .whiteBalanceAuto: writeValue(.whiteBalanceAuto, value: .bool(true)),
            .focusAuto: writeValue(.focusAuto, value: .bool(true)),
            .exposureAuto: writeValue(.exposureAuto, value: .bool(true))
        ]
    }

    private func bool(_ key: CameraControlKey, entity: Int, selector: Int, defaultValue: Bool) -> CameraControlCapability {
        CameraControlCapability(
            key: key,
            readable: false,
            writable: experimentalWritesEnabled,
            minimum: 0,
            maximum: 1,
            step: 1,
            defaultValue: .bool(defaultValue),
            currentValue: .bool(defaultValue),
            backend: experimentalWritesEnabled ? "Experimental UVC helper" : "C1 descriptor map",
            lastError: experimentalWritesEnabled ? "Experimental writes enabled; verify one low-risk value at a time" : "Awaiting helper access verification",
            entity: entity,
            selector: selector
        )
    }

    private func int(
        _ key: CameraControlKey,
        min: Int,
        max: Int,
        step: Int,
        defaultValue: Int,
        entity: Int,
        selector: Int,
        exposed: Bool = true
    ) -> CameraControlCapability {
        CameraControlCapability(
            key: key,
            readable: false,
            writable: exposed && experimentalWritesEnabled,
            minimum: min,
            maximum: max,
            step: step,
            defaultValue: .int(defaultValue),
            currentValue: .int(defaultValue),
            backend: experimentalWritesEnabled ? "Experimental UVC helper" : "C1 descriptor map",
            lastError: exposed
                ? (experimentalWritesEnabled ? "Experimental writes enabled; verify one low-risk value at a time" : "Awaiting helper access verification")
                : "Hidden until hardware response proves support",
            entity: entity,
            selector: selector
        )
    }

    private func helperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/c1_reverse_lab.py")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("Tools/c1_reverse_lab.py")
    }
}

private extension CameraControlValue {
    var helperIntValue: Int? {
        switch self {
        case .bool(let value): value ? 1 : 0
        case .int(let value): value
        case .unavailable: nil
        }
    }
}

enum C1PresetCatalog {
    static let presets: [CameraPreset] = [
        CameraPreset(
            name: "Zoom Natural",
            subtitle: "Neutral WB, restrained processing, stable call look",
            values: [
                .whiteBalanceAuto: .bool(false),
                .whiteBalanceTemperature: .int(5000),
                .brightness: .int(0),
                .contrast: .int(30),
                .saturation: .int(58),
                .sharpness: .int(14),
                .powerLineFrequency: .int(2)
            ]
        ),
        CameraPreset(
            name: "Warm Desk",
            subtitle: "Softer, warmer indoor talking-head preset",
            values: [
                .whiteBalanceAuto: .bool(false),
                .whiteBalanceTemperature: .int(4300),
                .brightness: .int(4),
                .contrast: .int(26),
                .saturation: .int(62),
                .sharpness: .int(10),
                .powerLineFrequency: .int(2)
            ]
        ),
        CameraPreset(
            name: "Low Light",
            subtitle: "Prefer stable exposure and lower harshness",
            values: [
                .exposureAuto: .bool(false),
                .exposureTime: .int(600),
                .gain: .int(96),
                .brightness: .int(8),
                .contrast: .int(22),
                .sharpness: .int(8)
            ]
        ),
        CameraPreset(
            name: "Manual Locked",
            subtitle: "Lock focus, exposure, and white balance after auto settles",
            values: [
                .focusAuto: .bool(false),
                .exposureAuto: .bool(false),
                .whiteBalanceAuto: .bool(false)
            ]
        )
    ]
}
