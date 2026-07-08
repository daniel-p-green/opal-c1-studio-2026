import CoreGraphics
import CoreImage
import Foundation
import Vision

struct LookSettings: Codable, Equatable {
    var name: String
    var exposureEV: Double
    var brightness: Double
    var contrast: Double
    var saturation: Double
    var warmth: Double
    var sharpness: Double
    var vignette: Double
    var portraitLift: Double
    var noiseReduction: Double
    var highlightSoftening: Double
    var backgroundBlur: Double
    var backgroundDim: Double
    var autoFaceBalance: Bool
    var autoStudioGrade: Bool
    var studioGradeAmount: Double
    var studioMatchAmount: Double
    var studioMatchExposureEV: Double
    var studioMatchWarmth: Double
    var studioMatchSaturation: Double
    var studioMatchContrast: Double
    var skinToneProtect: Double
    var mirror: Bool

    init(
        name: String,
        exposureEV: Double,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        warmth: Double,
        sharpness: Double,
        vignette: Double,
        portraitLift: Double,
        noiseReduction: Double,
        highlightSoftening: Double,
        backgroundBlur: Double,
        backgroundDim: Double,
        autoFaceBalance: Bool,
        autoStudioGrade: Bool,
        studioGradeAmount: Double,
        studioMatchAmount: Double,
        studioMatchExposureEV: Double,
        studioMatchWarmth: Double,
        studioMatchSaturation: Double,
        studioMatchContrast: Double,
        skinToneProtect: Double,
        mirror: Bool
    ) {
        self.name = name
        self.exposureEV = exposureEV
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.sharpness = sharpness
        self.vignette = vignette
        self.portraitLift = portraitLift
        self.noiseReduction = noiseReduction
        self.highlightSoftening = highlightSoftening
        self.backgroundBlur = backgroundBlur
        self.backgroundDim = backgroundDim
        self.autoFaceBalance = autoFaceBalance
        self.autoStudioGrade = autoStudioGrade
        self.studioGradeAmount = studioGradeAmount
        self.studioMatchAmount = studioMatchAmount
        self.studioMatchExposureEV = studioMatchExposureEV
        self.studioMatchWarmth = studioMatchWarmth
        self.studioMatchSaturation = studioMatchSaturation
        self.studioMatchContrast = studioMatchContrast
        self.skinToneProtect = skinToneProtect
        self.mirror = mirror
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case exposureEV
        case brightness
        case contrast
        case saturation
        case warmth
        case sharpness
        case vignette
        case portraitLift
        case noiseReduction
        case highlightSoftening
        case backgroundBlur
        case backgroundDim
        case autoFaceBalance
        case autoStudioGrade
        case studioGradeAmount
        case studioMatchAmount
        case studioMatchExposureEV
        case studioMatchWarmth
        case studioMatchSaturation
        case studioMatchContrast
        case skinToneProtect
        case mirror
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        exposureEV = try container.decode(Double.self, forKey: .exposureEV)
        brightness = try container.decode(Double.self, forKey: .brightness)
        contrast = try container.decode(Double.self, forKey: .contrast)
        saturation = try container.decode(Double.self, forKey: .saturation)
        warmth = try container.decode(Double.self, forKey: .warmth)
        sharpness = try container.decode(Double.self, forKey: .sharpness)
        vignette = try container.decode(Double.self, forKey: .vignette)
        portraitLift = try container.decodeIfPresent(Double.self, forKey: .portraitLift) ?? 0
        noiseReduction = try container.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0
        highlightSoftening = try container.decodeIfPresent(Double.self, forKey: .highlightSoftening) ?? 0
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        backgroundDim = try container.decodeIfPresent(Double.self, forKey: .backgroundDim) ?? 0
        autoFaceBalance = try container.decodeIfPresent(Bool.self, forKey: .autoFaceBalance) ?? false
        autoStudioGrade = try container.decodeIfPresent(Bool.self, forKey: .autoStudioGrade) ?? false
        studioGradeAmount = try container.decodeIfPresent(Double.self, forKey: .studioGradeAmount) ?? 0
        studioMatchAmount = try container.decodeIfPresent(Double.self, forKey: .studioMatchAmount) ?? 0
        studioMatchExposureEV = try container.decodeIfPresent(Double.self, forKey: .studioMatchExposureEV) ?? 0
        studioMatchWarmth = try container.decodeIfPresent(Double.self, forKey: .studioMatchWarmth) ?? 0
        studioMatchSaturation = try container.decodeIfPresent(Double.self, forKey: .studioMatchSaturation) ?? 1
        studioMatchContrast = try container.decodeIfPresent(Double.self, forKey: .studioMatchContrast) ?? 1
        skinToneProtect = try container.decodeIfPresent(Double.self, forKey: .skinToneProtect) ?? 0
        mirror = try container.decode(Bool.self, forKey: .mirror)
    }

    static let neutral = LookSettings(
        name: "Neutral",
        exposureEV: 0,
        brightness: 0,
        contrast: 1.04,
        saturation: 1.02,
        warmth: 0,
        sharpness: 0.14,
        vignette: 0,
        portraitLift: 0.10,
        noiseReduction: 0.28,
        highlightSoftening: 0.24,
        backgroundBlur: 0,
        backgroundDim: 0,
        autoFaceBalance: false,
        autoStudioGrade: false,
        studioGradeAmount: 0,
        studioMatchAmount: 0,
        studioMatchExposureEV: 0,
        studioMatchWarmth: 0,
        studioMatchSaturation: 1,
        studioMatchContrast: 1,
        skinToneProtect: 0,
        mirror: true
    )
}

enum LookPresetCatalog {
    static let presets: [LookSettings] = [
        LookSettings(
            name: "C1 Signature",
            exposureEV: -0.02,
            brightness: 0.004,
            contrast: 1.03,
            saturation: 1.03,
            warmth: 0.06,
            sharpness: 0.08,
            vignette: 0.04,
            portraitLift: 0.16,
            noiseReduction: 0.42,
            highlightSoftening: 0.34,
            backgroundBlur: 0.22,
            backgroundDim: 0.06,
            autoFaceBalance: true,
            autoStudioGrade: true,
            studioGradeAmount: 0.72,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.42,
            mirror: true
        ),
        LookSettings(
            name: "Studio Display Match",
            exposureEV: -0.02,
            brightness: 0.005,
            contrast: 0.98,
            saturation: 1.00,
            warmth: 0.02,
            sharpness: 0.10,
            vignette: 0,
            portraitLift: 0.12,
            noiseReduction: 0.36,
            highlightSoftening: 0.30,
            backgroundBlur: 0,
            backgroundDim: 0,
            autoFaceBalance: false,
            autoStudioGrade: true,
            studioGradeAmount: 0.34,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.12,
            mirror: true
        ),
        LookSettings(
            name: "Zoom Natural",
            exposureEV: 0.04,
            brightness: 0.01,
            contrast: 1.01,
            saturation: 1.02,
            warmth: 0.04,
            sharpness: 0.18,
            vignette: 0.04,
            portraitLift: 0.18,
            noiseReduction: 0.24,
            highlightSoftening: 0.22,
            backgroundBlur: 0.18,
            backgroundDim: 0.06,
            autoFaceBalance: true,
            autoStudioGrade: true,
            studioGradeAmount: 0.58,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.36,
            mirror: true
        ),
        LookSettings(
            name: "Warm Desk",
            exposureEV: 0.18,
            brightness: 0.015,
            contrast: 0.98,
            saturation: 1.08,
            warmth: 0.16,
            sharpness: 0.18,
            vignette: 0.08,
            portraitLift: 0.24,
            noiseReduction: 0.28,
            highlightSoftening: 0.24,
            backgroundBlur: 0.32,
            backgroundDim: 0.10,
            autoFaceBalance: true,
            autoStudioGrade: true,
            studioGradeAmount: 0.62,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.44,
            mirror: true
        ),
        LookSettings(
            name: "Low Light Clean",
            exposureEV: 0.12,
            brightness: 0.012,
            contrast: 0.96,
            saturation: 0.98,
            warmth: 0.08,
            sharpness: 0.02,
            vignette: 0,
            portraitLift: 0.18,
            noiseReduction: 0.52,
            highlightSoftening: 0.42,
            backgroundBlur: 0.18,
            backgroundDim: 0.08,
            autoFaceBalance: true,
            autoStudioGrade: true,
            studioGradeAmount: 0.82,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.52,
            mirror: true
        ),
        LookSettings(
            name: "Crisp Creator",
            exposureEV: 0.04,
            brightness: 0,
            contrast: 1.12,
            saturation: 1.10,
            warmth: 0.02,
            sharpness: 0.55,
            vignette: 0.08,
            portraitLift: 0.12,
            noiseReduction: 0.08,
            highlightSoftening: 0.12,
            backgroundBlur: 0.10,
            backgroundDim: 0.04,
            autoFaceBalance: false,
            autoStudioGrade: false,
            studioGradeAmount: 0,
            studioMatchAmount: 0,
            studioMatchExposureEV: 0,
            studioMatchWarmth: 0,
            studioMatchSaturation: 1,
            studioMatchContrast: 1,
            skinToneProtect: 0.08,
            mirror: true
        )
    ]
}

enum LookPresetStore {
    private static let key = "c1Studio.savedLooks.v1"
    private static let activeKey = "c1Studio.activeLook.v1"

    static func load() -> [LookSettings] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([LookSettings].self, from: data)) ?? []
    }

    static func save(_ presets: [LookSettings]) {
        guard let data = try? JSONEncoder().encode(presets) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func loadActive() -> LookSettings? {
        guard let data = UserDefaults.standard.data(forKey: activeKey) else {
            return nil
        }
        return try? JSONDecoder().decode(LookSettings.self, from: data)
    }

    static func saveActive(_ preset: LookSettings) {
        guard let data = try? JSONEncoder().encode(preset) else {
            return
        }
        UserDefaults.standard.set(data, forKey: activeKey)
    }

    static func clearActive() {
        UserDefaults.standard.removeObject(forKey: activeKey)
    }

    static func append(_ preset: LookSettings, to presets: [LookSettings]) -> [LookSettings] {
        var next = presets.filter { $0.name != preset.name }
        next.insert(preset, at: 0)
        if next.count > 12 {
            next = Array(next.prefix(12))
        }
        save(next)
        return next
    }
}

final class LookStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = LookSettings.neutral

    func snapshot() -> LookSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(_ transform: (inout LookSettings) -> Void) -> LookSettings {
        lock.lock()
        defer { lock.unlock() }
        transform(&settings)
        return settings
    }

    func replace(with newSettings: LookSettings) {
        lock.lock()
        settings = newSettings
        lock.unlock()
    }
}

final class LookRenderer: @unchecked Sendable {
    private let context = CIContext(options: [
        .cacheIntermediates: false
    ])
    private let faceLock = NSLock()
    private var frameIndex = 0
    private var faceCenter: CGPoint?
    private var faceRect: CGRect?
    private var lastFaceFrameIndex = -10_000
    private var personMask: CIImage?
    private var personMaskExtent = CGRect.zero
    private var adaptiveExposureEV = 0.0
    private var adaptiveWarmth = 0.0
    private var adaptiveTint = 0.0
    private var adaptiveSaturationScale = 1.0
    private var adaptiveShadowLift = 0.0
    private var adaptiveHighlightRecovery = 0.0

    func render(pixelBuffer: CVPixelBuffer, settings: LookSettings) -> CGImage? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let originalExtent = image.extent

        if settings.mirror {
            image = image
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                .transformed(by: CGAffineTransform(translationX: originalExtent.width, y: 0))
        }

        updateFaceCenterIfNeeded(in: image, extent: originalExtent)
        if hasRecentFace(), settings.backgroundBlur > 0 || settings.backgroundDim > 0 {
            updatePersonMaskIfNeeded(in: image, extent: originalExtent)
        }
        if settings.autoFaceBalance || settings.autoStudioGrade {
            updateAdaptiveCorrectionIfNeeded(in: image, extent: originalExtent, settings: settings)
        }

        let adaptive = (settings.autoFaceBalance || settings.autoStudioGrade)
            ? currentAdaptiveCorrection()
            : (exposureEV: 0.0, warmth: 0.0, tint: 0.0, saturationScale: 1.0, shadowLift: 0.0, highlightRecovery: 0.0)
        let studioMatchAmount = clamp(settings.studioMatchAmount, min: 0, max: 1)
        let matchContrastScale = 1.0 + (settings.studioMatchContrast - 1.0) * studioMatchAmount
        let matchSaturationScale = 1.0 + (settings.studioMatchSaturation - 1.0) * studioMatchAmount

        let totalExposureEV = settings.exposureEV + settings.studioMatchExposureEV * studioMatchAmount + adaptive.exposureEV
        if totalExposureEV != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: totalExposureEV
            ])
        }

        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: settings.brightness,
            kCIInputContrastKey: settings.contrast * matchContrastScale,
            kCIInputSaturationKey: settings.saturation * matchSaturationScale * adaptive.saturationScale
        ])

        let totalWarmth = settings.warmth + settings.studioMatchWarmth * studioMatchAmount + adaptive.warmth
        if totalWarmth != 0 || adaptive.tint != 0 {
            let targetTemperature = clamp(6500 - totalWarmth * 1800, min: 3200, max: 8200)
            let targetTint = clamp(totalWarmth * 12 + adaptive.tint * 28, min: -28, max: 28)
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: targetTemperature, y: targetTint)
            ])
        }

        let totalShadowLift = clamp(settings.highlightSoftening * 0.18 + adaptive.shadowLift, min: 0, max: 0.42)
        let totalHighlightRecovery = clamp(settings.highlightSoftening * 0.42 + adaptive.highlightRecovery, min: 0, max: 0.55)
        if totalShadowLift > 0 || totalHighlightRecovery > 0 {
            let amount = clamp(settings.highlightSoftening, min: 0, max: 1)
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1.0 - totalHighlightRecovery,
                "inputShadowAmount": totalShadowLift + amount * 0.02
            ])
        }

        if settings.noiseReduction > 0 {
            let amount = clamp(settings.noiseReduction, min: 0, max: 1)
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": 0.015 + amount * 0.065,
                "inputSharpness": max(0.02, 0.32 - amount * 0.20)
            ])
        }

        if hasRecentFace(), settings.backgroundBlur > 0 || settings.backgroundDim > 0 {
            image = applyBackgroundTreatment(to: image, extent: originalExtent, settings: settings)
        }

        if settings.sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: settings.sharpness
            ])
        }

        if settings.portraitLift > 0 {
            image = applyPortraitLift(to: image, extent: originalExtent, amount: settings.portraitLift, center: currentLightCenter(in: originalExtent))
        }

        if settings.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: settings.vignette,
                kCIInputRadiusKey: max(originalExtent.width, originalExtent.height) * 0.95
            ])
        }

        return context.createCGImage(image, from: originalExtent)
    }

    private func updateFaceCenterIfNeeded(in image: CIImage, extent: CGRect) {
        frameIndex += 1
        guard frameIndex == 1 || frameIndex % 18 == 0 else {
            return
        }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return
        }

        let target = CGPoint(
            x: extent.minX + face.boundingBox.midX * extent.width,
            y: extent.minY + face.boundingBox.midY * extent.height
        )
        let detectedFaceRect = CGRect(
            x: extent.minX + face.boundingBox.minX * extent.width,
            y: extent.minY + face.boundingBox.minY * extent.height,
            width: face.boundingBox.width * extent.width,
            height: face.boundingBox.height * extent.height
        )
        .insetBy(dx: -extent.width * 0.035, dy: -extent.height * 0.045)
        .intersection(extent)

        faceLock.lock()
        if let current = faceCenter {
            faceCenter = CGPoint(
                x: current.x * 0.78 + target.x * 0.22,
                y: current.y * 0.78 + target.y * 0.22
            )
        } else {
            faceCenter = target
        }
        faceRect = detectedFaceRect.isNull ? nil : detectedFaceRect
        lastFaceFrameIndex = frameIndex
        faceLock.unlock()
    }

    private func hasRecentFace() -> Bool {
        faceLock.lock()
        let recent = frameIndex - lastFaceFrameIndex <= 45
        faceLock.unlock()
        return recent
    }

    private func updatePersonMaskIfNeeded(in image: CIImage, extent: CGRect) {
        guard frameIndex == 1 || frameIndex % 10 == 0 || personMask == nil || personMaskExtent != extent else {
            return
        }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let pixelBuffer = request.results?.first?.pixelBuffer else {
            return
        }

        var mask = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = extent.width / max(mask.extent.width, 1)
        let scaleY = extent.height / max(mask.extent.height, 1)
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: extent)
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 3.0
            ])
            .cropped(to: extent)

        faceLock.lock()
        personMask = mask
        personMaskExtent = extent
        faceLock.unlock()
    }

    private func currentPersonMask(for extent: CGRect) -> CIImage? {
        faceLock.lock()
        let mask = personMaskExtent == extent ? personMask : nil
        faceLock.unlock()
        return mask
    }

    private func currentLightCenter(in extent: CGRect) -> CGPoint {
        faceLock.lock()
        let center = faceCenter
        faceLock.unlock()
        return center ?? CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.10)
    }

    private func updateAdaptiveCorrectionIfNeeded(in image: CIImage, extent: CGRect, settings: LookSettings) {
        guard frameIndex == 1 || frameIndex % 12 == 0 else {
            return
        }
        let gradeAmount = settings.autoStudioGrade ? clamp(settings.studioGradeAmount, min: 0, max: 1) : 0
        let sampleRect = currentFaceRect(for: extent) ?? centerSampleRect(in: extent)
        guard (hasRecentFace() || settings.autoStudioGrade), let sample = averageColor(in: image, rect: sampleRect) else {
            smoothAdaptiveCorrection(toward: (0, 0, 0, 1, 0, 0))
            return
        }

        let luminance = sample.red * 0.2126 + sample.green * 0.7152 + sample.blue * 0.0722
        let targetLuminance = hasRecentFace() ? 0.52 : 0.50
        let exposure = clamp((targetLuminance - luminance) * (0.72 + gradeAmount * 0.56), min: -0.30, max: 0.22)

        let warmth = clamp((sample.blue - sample.red) * (0.34 + gradeAmount * 0.26), min: -0.14, max: 0.20)
        let tint = clamp(((sample.red + sample.blue) * 0.5 - sample.green) * gradeAmount * 0.36, min: -0.10, max: 0.10)
        let chromaSpread = max(sample.red, sample.green, sample.blue) - min(sample.red, sample.green, sample.blue)
        let protect = clamp(settings.skinToneProtect, min: 0, max: 1)
        let saturationScale = clamp(1.0 - max(0, chromaSpread - 0.24) * protect * 0.85, min: 0.88, max: 1.04)
        let shadowLift = clamp((0.48 - luminance) * gradeAmount * 0.42, min: 0, max: 0.16)
        let highlightRecovery = clamp((luminance - 0.58) * gradeAmount * 0.50, min: 0, max: 0.18)

        smoothAdaptiveCorrection(toward: (exposure, warmth, tint, saturationScale, shadowLift, highlightRecovery))
    }

    private func currentFaceRect(for extent: CGRect) -> CGRect? {
        faceLock.lock()
        let rect = faceRect?.intersection(extent)
        faceLock.unlock()
        guard let rect, !rect.isNull, rect.width >= 16, rect.height >= 16 else {
            return nil
        }
        return rect
    }

    private func currentAdaptiveCorrection() -> (exposureEV: Double, warmth: Double, tint: Double, saturationScale: Double, shadowLift: Double, highlightRecovery: Double) {
        faceLock.lock()
        let correction = (adaptiveExposureEV, adaptiveWarmth, adaptiveTint, adaptiveSaturationScale, adaptiveShadowLift, adaptiveHighlightRecovery)
        faceLock.unlock()
        return correction
    }

    private func smoothAdaptiveCorrection(toward target: (Double, Double, Double, Double, Double, Double)) {
        faceLock.lock()
        adaptiveExposureEV = adaptiveExposureEV * 0.82 + target.0 * 0.18
        adaptiveWarmth = adaptiveWarmth * 0.82 + target.1 * 0.18
        adaptiveTint = adaptiveTint * 0.82 + target.2 * 0.18
        adaptiveSaturationScale = adaptiveSaturationScale * 0.82 + target.3 * 0.18
        adaptiveShadowLift = adaptiveShadowLift * 0.82 + target.4 * 0.18
        adaptiveHighlightRecovery = adaptiveHighlightRecovery * 0.82 + target.5 * 0.18
        faceLock.unlock()
    }

    private func centerSampleRect(in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + extent.width * 0.30,
            y: extent.minY + extent.height * 0.20,
            width: extent.width * 0.40,
            height: extent.height * 0.50
        ).intersection(extent)
    }

    private func averageColor(in image: CIImage, rect: CGRect) -> (red: Double, green: Double, blue: Double)? {
        let sampleRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.20)
        let boundedRect = (sampleRect.isNull ? rect : sampleRect).intersection(image.extent)
        guard !boundedRect.isNull,
              let output = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: image.cropped(to: boundedRect),
                    kCIInputExtentKey: CIVector(cgRect: boundedRect)
                ]
              )?.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        return (
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
    }

    private func applyPortraitLift(to image: CIImage, extent: CGRect, amount: Double, center: CGPoint) -> CIImage {
        let clamped = clamp(amount, min: 0, max: 1)
        let lifted = image.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: clamped * 0.55
        ])
        guard let mask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: center.x, y: center.y),
                "inputRadius0": max(extent.width, extent.height) * 0.10,
                "inputRadius1": max(extent.width, extent.height) * 0.48,
                "inputColor0": CIColor(red: clamped, green: clamped, blue: clamped, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
        )?.outputImage?.cropped(to: extent) else {
            return image
        }
        return lifted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ])
    }

    private func applyBackgroundTreatment(to image: CIImage, extent: CGRect, settings: LookSettings) -> CIImage {
        guard let mask = currentPersonMask(for: extent) else {
            return image
        }

        var background = image
        if settings.backgroundBlur > 0 {
            background = background
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: clamp(settings.backgroundBlur, min: 0, max: 1) * 22
                ])
                .cropped(to: extent)
        }
        if settings.backgroundDim > 0 {
            let amount = clamp(settings.backgroundDim, min: 0, max: 1)
            background = background.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.18 * amount,
                kCIInputContrastKey: 1.0 - 0.10 * amount,
                kCIInputSaturationKey: 1.0 - 0.16 * amount
            ])
        }

        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
