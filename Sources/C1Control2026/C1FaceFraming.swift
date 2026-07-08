import CoreVideo
import Foundation
import Vision

struct FaceFramingStatus: Sendable {
    let ready: Bool
    let title: String
    let detail: String

    static let stopped = FaceFramingStatus(
        ready: false,
        title: "Face Proof: preview stopped",
        detail: "Start preview for live face-framing guidance."
    )
}

final class FaceFramingAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private var frameIndex = 0
    private var lastStatus = FaceFramingStatus.stopped

    func reset() {
        lock.lock()
        frameIndex = 0
        lastStatus = .stopped
        lock.unlock()
    }

    func snapshot() -> FaceFramingStatus {
        lock.lock()
        defer { lock.unlock() }
        return lastStatus
    }

    func analyze(pixelBuffer: CVPixelBuffer) -> FaceFramingStatus? {
        lock.lock()
        frameIndex += 1
        let shouldAnalyze = frameIndex == 1 || frameIndex % 12 == 0
        lock.unlock()
        guard shouldAnalyze else {
            return nil
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let status: FaceFramingStatus
        if (try? handler.perform([request])) == nil {
            status = FaceFramingStatus(
                ready: false,
                title: "Face Proof: scanner unavailable",
                detail: "Vision face detection failed on the current frame."
            )
        } else {
            status = Self.status(from: request.results ?? [])
        }

        lock.lock()
        lastStatus = status
        lock.unlock()
        return status
    }

    private static func status(from faces: [VNFaceObservation]) -> FaceFramingStatus {
        guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return FaceFramingStatus(
                ready: false,
                title: "Face Proof: no face",
                detail: "Sit centered with your full face visible before running Face Proof."
            )
        }

        if faces.count > 1 {
            return FaceFramingStatus(
                ready: false,
                title: "Face Proof: multiple faces",
                detail: "Use a single-person frame for the C1 vs Studio Display decision."
            )
        }

        let area = Double(face.boundingBox.width * face.boundingBox.height)
        let centerX = Double(face.boundingBox.midX)
        let centerY = Double(face.boundingBox.midY)

        if area < 0.018 {
            return FaceFramingStatus(
                ready: false,
                title: "Face Proof: move closer",
                detail: String(format: "Face is too small for a fair proof. Area %.3f.", area)
            )
        }
        if area > 0.32 {
            return FaceFramingStatus(
                ready: false,
                title: "Face Proof: move back",
                detail: String(format: "Face is too large for a fair proof. Area %.3f.", area)
            )
        }
        if centerX < 0.32 || centerX > 0.68 || centerY < 0.28 || centerY > 0.76 {
            return FaceFramingStatus(
                ready: false,
                title: "Face Proof: center face",
                detail: String(format: "Keep face near center. Position %.2f, %.2f.", centerX, centerY)
            )
        }

        return FaceFramingStatus(
            ready: true,
            title: "Face Proof: ready",
            detail: String(format: "Centered single face detected. Area %.3f.", area)
        )
    }
}
