import Foundation

struct ReverseLabReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class ReverseLabRunner {
    func rootProbeCommand() -> String {
        let scriptURL = helperScriptURL()
        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work")
            .appendingPathComponent("c1-root-probe.json")
        return "sudo \(shellQuoted(scriptURL.path)) --json --output \(shellQuoted(outputURL.path))"
    }

    func run() async -> ReverseLabReport {
        await run(arguments: ["--text"])
    }

    func runControlProof() async -> ReverseLabReport {
        await run(arguments: ["--control-proof"])
    }

    private func run(arguments: [String]) async -> ReverseLabReport {
        let scriptURL = helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return ReverseLabReport(
                generatedAt: Date(),
                text: "Reverse-lab helper not found at \(scriptURL.path)"
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = scriptURL
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: ReverseLabReport(generatedAt: Date(), text: output))
                } catch {
                    continuation.resume(returning: ReverseLabReport(
                        generatedAt: Date(),
                        text: "Failed to run reverse-lab helper: \(error.localizedDescription)"
                    ))
                }
            }
        }
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

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
