import Foundation

struct VisualProofReport {
    let generatedAt: Date
    let text: String
}

@MainActor
final class VisualProofRunner {
    func run() async -> VisualProofReport {
        guard let executableURL = Bundle.main.executableURL else {
            return VisualProofReport(generatedAt: Date(), text: "Visual proof failed: app executable unavailable")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let workspace = DoctorRunner.workspaceRoot()
                let process = Process()
                process.executableURL = executableURL
                process.currentDirectoryURL = workspace
                process.arguments = ["--visual-proof"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: VisualProofReport(generatedAt: Date(), text: output))
                } catch {
                    continuation.resume(returning: VisualProofReport(
                        generatedAt: Date(),
                        text: "Visual proof failed: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
