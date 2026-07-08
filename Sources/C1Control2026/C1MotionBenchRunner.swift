import Foundation

struct MotionBenchReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class MotionBenchRunner {
    func run() async -> MotionBenchReport {
        let scriptURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return MotionBenchReport(
                generatedAt: Date(),
                text: "Motion bench helper not found at \(scriptURL.path)"
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let workspace = DoctorRunner.workspaceRoot()
                let outputURL = workspace
                    .appendingPathComponent("work")
                    .appendingPathComponent("c1-motion-bench-latest.md")
                let process = Process()
                process.executableURL = scriptURL
                process.arguments = ["--output", outputURL.path]
                process.currentDirectoryURL = workspace
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
                    continuation.resume(returning: MotionBenchReport(generatedAt: Date(), text: output))
                } catch {
                    continuation.resume(returning: MotionBenchReport(
                        generatedAt: Date(),
                        text: "Failed to run motion bench: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func helperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/c1_motion_bench.py")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        return DoctorRunner.workspaceRoot().appendingPathComponent("Tools/c1_motion_bench.py")
    }
}
