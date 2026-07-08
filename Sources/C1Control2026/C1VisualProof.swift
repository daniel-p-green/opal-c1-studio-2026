import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum VisualProof {
    static func run() -> Int32 {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let benchDir = root.appendingPathComponent("work/quality-bench")
        guard let opalURL = latestImage(in: benchDir, prefix: "opal-c1-"),
              let studioURL = latestImage(in: benchDir, prefix: "studio-display-") else {
            print("Visual proof failed: run ./script/build_and_run.sh --benchmark first")
            return 1
        }

        guard let opalImage = loadImage(opalURL),
              let studioImage = loadImage(studioURL),
              let opalBuffer = pixelBuffer(from: opalImage) else {
            print("Visual proof failed: could not load latest benchmark images")
            return 1
        }
        let studioFace = detectLargestFace(in: studioImage)
        let opalFace = detectLargestFace(in: opalImage)

        let renderer = LookRenderer()
        let signature = LookPresetCatalog.presets.first { $0.name == "C1 Signature" } ?? .neutral
        let lowLight = LookPresetCatalog.presets.first { $0.name == "Low Light Clean" } ?? .neutral
        let matched = LookPresetCatalog.presets.first { $0.name == "Studio Display Match" } ?? .neutral
        let coach = loadCoachLook(root: root)

        let signatureImage = renderer.render(pixelBuffer: opalBuffer, settings: signature) ?? opalImage
        let matchedImage = renderer.render(pixelBuffer: opalBuffer, settings: matched) ?? opalImage
        let lowLightImage = renderer.render(pixelBuffer: opalBuffer, settings: lowLight) ?? opalImage
        let coachImage = coach.flatMap { renderer.render(pixelBuffer: opalBuffer, settings: $0) }

        var items = [
            ProofItem(role: "studio_display", title: "Studio Display", subtitle: studioURL.lastPathComponent, image: studioImage),
            ProofItem(role: "c1_raw", title: "C1 Raw", subtitle: opalURL.lastPathComponent, image: opalImage),
            ProofItem(role: "c1_signature", title: "C1 Signature", subtitle: "face-gated relight + background blur", image: signatureImage),
            ProofItem(role: "c1_low_light_clean", title: "C1 Low Light Clean", subtitle: "max cleanup, softer detail", image: lowLightImage),
            ProofItem(role: "c1_studio_match", title: "C1 Studio Match", subtitle: "conservative baseline", image: matchedImage)
        ]
        if let coachImage {
            items.append(ProofItem(role: "c1_coach_tuned", title: "C1 Coach Tuned", subtitle: "generated from Quality Coach", image: coachImage))
        }

        let variants = saveVariants(items: items, root: root)
        let gate = VisualProofGate(
            studioImage: studioURL.lastPathComponent,
            opalImage: opalURL.lastPathComponent,
            studioFace: studioFace,
            opalFace: opalFace,
            variants: variants
        )

        guard let sheet = makeSheet(items: items, gate: gate) else {
            print("Visual proof failed: could not render contact sheet")
            return 1
        }

        let output = root
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-latest.jpg")
        let gateTextURL = root.appendingPathComponent("work").appendingPathComponent("c1-visual-proof-latest.md")
        let gateJSONURL = root.appendingPathComponent("work").appendingPathComponent("c1-visual-proof-latest.json")
        writeGate(gate, markdownURL: gateTextURL, jsonURL: gateJSONURL)
        if saveJPEG(sheet, to: output) {
            print("Visual proof saved: \(output.path)")
            print("Face gate: \(gate.verdict)")
            print("Verdict gate: if C1 Coach Tuned or C1 Signature is not visibly better than Studio Display, use Studio Display.")
            return 0
        }
        print("Visual proof failed: could not save sheet")
        return 1
    }

    private static func loadCoachLook(root: URL) -> LookSettings? {
        let url = root
            .appendingPathComponent("work")
            .appendingPathComponent("c1-coach-look-latest.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(LookSettings.self, from: data)
    }

    private static func latestImage(in directory: URL, prefix: String) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension.lowercased() == "jpg" }
            .max { lhs, rhs in
                modificationDate(lhs) < modificationDate(rhs)
            }
    }

    private static func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixelBuffer
    }

    private static func makeSheet(items: [ProofItem], gate: VisualProofGate) -> CGImage? {
        let panelWidth = 560
        let imageHeight = 315
        let labelHeight = 64
        let gap = 16
        let columns = 2
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let width = columns * panelWidth + (columns + 1) * gap
        let bannerHeight = gate.valid ? 0 : 58
        let height = rows * (imageHeight + labelHeight) + (rows + 1) * gap + bannerHeight

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        if !gate.valid {
            let bannerRect = NSRect(x: gap, y: height - bannerHeight - gap, width: width - gap * 2, height: bannerHeight)
            NSColor.systemRed.withAlphaComponent(0.13).setFill()
            bannerRect.fill()
            let warning = NSMutableAttributedString(
                string: "Face gate failed\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: NSColor.systemRed
                ]
            )
            warning.append(NSAttributedString(
                string: gate.verdict,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.labelColor
                ]
            ))
            warning.draw(in: bannerRect.insetBy(dx: 12, dy: 9))
        }

        for (index, item) in items.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = gap + column * (panelWidth + gap)
            let y = height - gap - bannerHeight - (row + 1) * (imageHeight + labelHeight)
            let imageRect = NSRect(x: x, y: y + labelHeight, width: panelWidth, height: imageHeight)
            let labelRect = NSRect(x: x, y: y, width: panelWidth, height: labelHeight)

            NSColor.black.setFill()
            imageRect.fill()
            NSGraphicsContext.current?.cgContext.interpolationQuality = .high
            NSImage(cgImage: item.image, size: .zero).draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)

            let title = NSMutableAttributedString(
                string: "\(item.title)\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            title.append(NSAttributedString(
                string: item.subtitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
            title.draw(in: labelRect.insetBy(dx: 2, dy: 8))
        }

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.cgImage
    }

    private static func saveJPEG(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func saveVariants(items: [ProofItem], root: URL) -> [ProofVariant] {
        let directory = root.appendingPathComponent("work").appendingPathComponent("visual-proof")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return items.compactMap { item in
            let url = directory.appendingPathComponent("\(item.role)-latest.jpg")
            guard saveJPEG(item.image, to: url) else {
                return nil
            }
            return ProofVariant(
                role: item.role,
                title: item.title,
                path: url.path,
                width: item.image.width,
                height: item.image.height
            )
        }
    }

    private static func detectLargestFace(in image: CGImage) -> FaceDetectionResult {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil else {
            return FaceDetectionResult(count: 0, largestArea: 0)
        }
        let observations = request.results ?? []
        let largestArea = observations
            .map { Double($0.boundingBox.width * $0.boundingBox.height) }
            .max() ?? 0
        return FaceDetectionResult(count: observations.count, largestArea: largestArea)
    }

    private static func writeGate(_ gate: VisualProofGate, markdownURL: URL, jsonURL: URL) {
        try? FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let markdown = """
        # C1 Visual Proof Gate

        ## Verdict
        \(gate.verdict)

        ## Checks
        - Studio image: `\(gate.studioImage)`
        - C1 image: `\(gate.opalImage)`
        - Studio faces: \(gate.studioFace.count), largest normalized area: \(String(format: "%.4f", gate.studioFace.largestArea))
        - C1 faces: \(gate.opalFace.count), largest normalized area: \(String(format: "%.4f", gate.opalFace.largestArea))
        - Face-valid proof: \(gate.valid ? "pass" : "fail")

        ## Saved Variants
        \(gate.variants.map { "- \($0.title): `\($0.path)`" }.joined(separator: "\n"))

        ## Policy
        Do not mark a C1 visual win from this proof unless Face-valid proof is pass and C1 Coach Tuned or C1 Signature clearly beats Studio Display by eye.
        """
        try? markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(gate) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }
}

private struct ProofItem {
    let role: String
    let title: String
    let subtitle: String
    let image: CGImage
}

private struct ProofVariant: Codable {
    let role: String
    let title: String
    let path: String
    let width: Int
    let height: Int
}

private struct FaceDetectionResult: Codable {
    let count: Int
    let largestArea: Double
}

private struct VisualProofGate: Codable {
    let generatedAt: String
    let studioImage: String
    let opalImage: String
    let studioFace: FaceDetectionResult
    let opalFace: FaceDetectionResult
    let variants: [ProofVariant]
    let valid: Bool
    let verdict: String

    init(studioImage: String, opalImage: String, studioFace: FaceDetectionResult, opalFace: FaceDetectionResult, variants: [ProofVariant]) {
        self.generatedAt = ISO8601DateFormatter().string(from: Date())
        self.studioImage = studioImage
        self.opalImage = opalImage
        self.studioFace = studioFace
        self.opalFace = opalFace
        self.variants = variants
        self.valid = studioFace.count > 0 && opalFace.count > 0
        if self.valid {
            self.verdict = "Face-valid proof: Studio Display and C1 both contain a detectable face."
        } else if studioFace.count == 0 && opalFace.count == 0 {
            self.verdict = "Face-invalid proof: no detectable face in either benchmark image."
        } else if studioFace.count == 0 {
            self.verdict = "Face-invalid proof: no detectable face in the Studio Display image."
        } else {
            self.verdict = "Face-invalid proof: no detectable face in the C1 image."
        }
    }
}
