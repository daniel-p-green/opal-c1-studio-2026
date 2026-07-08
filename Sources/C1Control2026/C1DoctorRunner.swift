import Foundation

struct DoctorReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class DoctorRunner {
    func run() async -> DoctorReport {
        let doctorURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: doctorURL.path) else {
            return DoctorReport(
                generatedAt: Date(),
                text: "Doctor helper not found at \(doctorURL.path)"
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let workspace = Self.workspaceRoot()
                let workURL = workspace.appendingPathComponent("work")
                try? FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

                Self.refreshAppleEffectsOutput(workURL: workURL)

                let process = Process()
                process.executableURL = doctorURL
                process.arguments = [
                    "--output",
                    workURL.appendingPathComponent("c1-doctor-latest.md").path
                ]
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "C1_STUDIO_WORKSPACE": workspace.path
                ]) { _, new in new }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: DoctorReport(generatedAt: Date(), text: output))
                } catch {
                    continuation.resume(returning: DoctorReport(
                        generatedAt: Date(),
                        text: "Failed to run doctor helper: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    nonisolated static func workspaceRoot() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Package.swift").path) {
            return cwd
        }

        var candidate = Bundle.main.bundleURL
        for _ in 0..<5 {
            candidate.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
        }

        return cwd
    }

    nonisolated private static func refreshAppleEffectsOutput(workURL: URL) {
        guard let executableURL = Bundle.main.executableURL else {
            return
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--apple-effects-probe"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try data.write(to: workURL.appendingPathComponent("c1-apple-effects-latest.txt"))
        } catch {
            // The doctor can still run and report missing/stale Apple effects evidence.
        }
    }

    private func helperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/c1_doctor.py")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        return Self.workspaceRoot().appendingPathComponent("Tools/c1_doctor.py")
    }
}
