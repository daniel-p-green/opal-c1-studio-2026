import AVFoundation
import Foundation

struct ReadinessReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class ReadinessRunner {
    func run() async -> ReadinessReport {
        let scriptURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return ReadinessReport(
                generatedAt: Date(),
                text: "Readiness helper not found at \(scriptURL.path)"
            )
        }
        let permission = cameraPermissionDescription()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = scriptURL
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "C1_STUDIO_WORKSPACE": FileManager.default.currentDirectoryPath
                ]) { _, new in new }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let combined = Self.withCameraPermission(output, permission: permission)
                    continuation.resume(returning: ReadinessReport(generatedAt: Date(), text: combined))
                } catch {
                    continuation.resume(returning: ReadinessReport(
                        generatedAt: Date(),
                        text: "Failed to run readiness helper: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func cameraPermissionDescription() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return switch status {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not determined"
        @unknown default: "unknown"
        }
    }

    nonisolated private static func withCameraPermission(_ report: String, permission: String) -> String {
        report + "\n\n## App Permission\n- Camera permission: \(permission)\n"
    }

    private func helperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/c1_readiness.py")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("Tools/c1_readiness.py")
    }
}
