import Foundation

struct BenchmarkReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class BenchmarkRunner {
    func run() async -> BenchmarkReport {
        let scriptURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return BenchmarkReport(
                generatedAt: Date(),
                text: "Quality benchmark helper not found at \(scriptURL.path)"
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let workspace = DoctorRunner.workspaceRoot()
                let process = Process()
                process.executableURL = scriptURL
                process.arguments = ["--text"]
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
                    continuation.resume(returning: BenchmarkReport(generatedAt: Date(), text: output))
                } catch {
                    continuation.resume(returning: BenchmarkReport(
                        generatedAt: Date(),
                        text: "Failed to run quality benchmark: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func helperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/c1_quality_bench.py")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("Tools/c1_quality_bench.py")
    }
}
