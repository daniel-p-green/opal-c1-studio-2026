import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: StudioController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let studioController = StudioController()
        controller = studioController
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "C1 Studio 2026"
        window.center()
        window.contentView = studioController.view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        studioController.boot()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopPreview()
    }
}

@MainActor
final class StudioController: NSObject {
    let view = NSView()

    private let session = AVCaptureSession()
    private let previewView = PreviewView()
    private let transport: CameraControlTransport = DescriptorBackedControlTransport()
    private let doctorRunner = DoctorRunner()
    private let visualProofRunner = VisualProofRunner()
    private let reverseLab = ReverseLabRunner()
    private let benchmarkRunner = BenchmarkRunner()
    private let motionBenchRunner = MotionBenchRunner()
    private let qualityCoachRunner = QualityCoachRunner()
    private let visualScoreRunner = VisualScoreRunner()
    private let readinessRunner = ReadinessRunner()
    private let lookStore = LookStateStore()
    private let lookRenderer = LookRenderer()
    private let faceFramingAnalyzer = FaceFramingAnalyzer()

    private let statusLabel = NSTextField(labelWithString: "Status: Starting")
    private let deviceLabel = NSTextField(labelWithString: "Device: Unknown")
    private let modeLabel = NSTextField(labelWithString: "Mode: Preview stopped")
    private let healthLabel = NSTextField(labelWithString: "")
    private let faceProofLabel = NSTextField(labelWithString: FaceFramingStatus.stopped.title)
    private let backendLabel = NSTextField(labelWithString: "Backend: AVFoundation video ready, UVC control helper pending")
    private let selectedControlLabel = NSTextField(labelWithString: "Select a control to inspect its backend.")
    private let lookLabel = NSTextField(labelWithString: "Look: Zoom Natural software tuning")
    private let videoPathLabel = NSTextField(labelWithString: "Video: Opal C1 1080p60 proven locally")
    private let systemEffectsLabel = NSTextField(labelWithString: "Apple Effects: checking C1 support")
    private let controlPathLabel = NSTextField(labelWithString: "Controls: direct UVC access not proven yet")
    private let bridgePathLabel = NSTextField(labelWithString: "Opal bridge: installed shim detected, signed-client gate likely")
    private let irisLabel = NSTextField(labelWithString: "Iris/aperture: hidden until hardware responds; treat C1 aperture as fixed")
    private let productLabel = NSTextField(labelWithString: "Target: a reliable C1 console for Zoom/OBS without launching Composer UI")
    private let doctorVerdictLabel = NSTextField(labelWithString: "Verdict: Run Doctor")
    private let doctorOutput = NSTextView()
    private let labOutput = NSTextView()
    private let benchmarkOutput = NSTextView()
    private let readinessOutput = NSTextView()

    private let tabView = NSTabView()
    private let controlsStack = NSStackView()
    private let presetStack = NSStackView()
    private let lookStack = NSStackView()
    private let lookPresetStack = NSStackView()

    private let runDoctorButton = NSButton(title: "Run Doctor", target: nil, action: nil)
    private let runFullProofButton = NSButton(title: "Run Full Proof", target: nil, action: nil)
    private let runFaceProofButton = NSButton(title: "Run Face Proof", target: nil, action: nil)
    private let buildVisualProofButton = NSButton(title: "Build Visual Proof", target: nil, action: nil)
    private let saveDoctorButton = NSButton(title: "Save Doctor Report", target: nil, action: nil)
    private let openVisualProofButton = NSButton(title: "Open Visual Proof", target: nil, action: nil)
    private let markVisualWinButton = NSButton(title: "Mark C1 Visual Win", target: nil, action: nil)
    private let clearVisualWinButton = NSButton(title: "Clear Visual Win", target: nil, action: nil)
    private let startPreviewButton = NSButton(title: "Start Preview", target: nil, action: nil)
    private let stopPreviewButton = NSButton(title: "Stop Preview", target: nil, action: nil)
    private let goLiveButton = NSButton(title: "Go Live", target: nil, action: nil)
    private let appleEffectsButton = NSButton(title: "Open Apple Video Effects", target: nil, action: nil)
    private let openOBSButton = NSButton(title: "Open OBS", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let snapshotButton = NSButton(title: "Save Tuned Frame", target: nil, action: nil)
    private let outputWindowButton = NSButton(title: "Open OBS Output Window", target: nil, action: nil)
    private let startBridgeButton = NSButton(title: "Start OBS Bridge", target: nil, action: nil)
    private let saveCurrentLookButton = NSButton(title: "Save Current Look", target: nil, action: nil)
    private let applyCoachLookButton = NSButton(title: "Apply Coach Look", target: nil, action: nil)
    private let runLabButton = NSButton(title: "Run Lab Probe", target: nil, action: nil)
    private let runControlProofButton = NSButton(title: "Run Control Proof", target: nil, action: nil)
    private let saveLabButton = NSButton(title: "Save Report", target: nil, action: nil)
    private let copyRootProbeButton = NSButton(title: "Copy Root Probe Command", target: nil, action: nil)
    private let runBenchmarkButton = NSButton(title: "Run C1 vs Studio Bench", target: nil, action: nil)
    private let runMotionBenchButton = NSButton(title: "Run Motion Bench", target: nil, action: nil)
    private let runQualityCoachButton = NSButton(title: "Run Quality Coach", target: nil, action: nil)
    private let calibrateLookButton = NSButton(title: "Calibrate C1 Look", target: nil, action: nil)
    private let saveBenchmarkButton = NSButton(title: "Save Bench Report", target: nil, action: nil)
    private let openCameraPrivacyButton = NSButton(title: "Open Camera Privacy", target: nil, action: nil)
    private let runReadinessButton = NSButton(title: "Run Readiness Check", target: nil, action: nil)
    private let saveReadinessButton = NSButton(title: "Save Readiness", target: nil, action: nil)
    private let lockLookButton = NSButton(title: "Lock Current Look", target: nil, action: nil)
    private let resetAutoButton = NSButton(title: "Reset Auto", target: nil, action: nil)

    private let sampleBufferOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "c1.studio.session")
    private let frameQueue = DispatchQueue(label: "c1.studio.frames")

    private var currentDevice: AVCaptureDevice?
    private var capabilities: [CameraControlCapability] = []
    private var controlRows: [CameraControlKey: ControlRow] = [:]
    private var frameTimer: Timer?
    private var frameCounter = 0
    private var lastFrameCounter = 0
    private var lastLabReport: ReverseLabReport?
    private var lastBenchmarkReport: BenchmarkReport?
    private var lastMotionBenchReport: MotionBenchReport?
    private var lastQualityCoachReport: QualityCoachReport?
    private var lastReadinessReport: ReadinessReport?
    private var lastDoctorReport: DoctorReport?
    private var lastRenderedFrame: CGImage?
    private var outputWindow: NSWindow?
    private var outputPreviewView: PreviewView?
    private var savedLookPresets: [LookSettings] = []

    override init() {
        super.init()
        savedLookPresets = LookPresetStore.load()
        buildUI()
        wireActions()
        let startupLook = LookPresetStore.loadActive() ?? savedLookPresets.first ?? LookPresetCatalog.presets[0]
        applyLookPreset(startupLook, updateRows: true)
        loadControls()
    }

    func boot() {
        refreshDeviceState()
        tabView.selectTabViewItem(withIdentifier: "doctor")
        setStatus("Doctor ready. Run diagnosis before choosing C1 over Studio Display.")
        if CommandLine.arguments.contains("--save-look-smoke") {
            saveCurrentLook(named: "Smoke Test Look")
            setStatus("Saved Smoke Test Look")
        }
        if shouldAutostartPreview {
            setStatus("Autostart preview requested")
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.tabView.selectTabViewItem(withIdentifier: "preview")
                    if self?.shouldAutostartBridge == true {
                        self?.startOBSBridge()
                    } else {
                        self?.startPreview()
                    }
                }
            }
        }
    }

    func stopPreview() {
        stopPreviewInternal()
    }

    private func buildUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 12, right: 18)
        header.spacing = 12

        let titleBlock = NSStackView()
        titleBlock.orientation = .vertical
        titleBlock.spacing = 2
        let title = NSTextField(labelWithString: "C1 Studio 2026")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "A 2026 daily-driver console for tuned Opal C1 video, OBS output, and verified hardware controls")
        subtitle.textColor = .secondaryLabelColor
        titleBlock.addArrangedSubview(title)
        titleBlock.addArrangedSubview(subtitle)

        [statusLabel, deviceLabel, modeLabel, healthLabel, backendLabel, selectedControlLabel].forEach {
            $0.maximumNumberOfLines = 3
            $0.lineBreakMode = .byWordWrapping
        }
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        header.addArrangedSubview(titleBlock)
        header.addArrangedSubview(NSView())
        let headerStatus = NSStackView()
        headerStatus.orientation = .vertical
        headerStatus.alignment = .trailing
        headerStatus.spacing = 4
        headerStatus.addArrangedSubview(statusLabel)
        headerStatus.addArrangedSubview(faceProofLabel)
        headerStatus.addArrangedSubview(productLabel)
        productLabel.textColor = .secondaryLabelColor
        productLabel.maximumNumberOfLines = 2
        faceProofLabel.textColor = .secondaryLabelColor
        faceProofLabel.maximumNumberOfLines = 2
        faceProofLabel.lineBreakMode = .byWordWrapping
        faceProofLabel.toolTip = FaceFramingStatus.stopped.detail
        header.addArrangedSubview(headerStatus)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(NSTabViewItem(identifier: "doctor"))
        tabView.tabViewItem(at: 0).label = "Doctor"
        tabView.tabViewItem(at: 0).view = makeDoctorView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "preview"))
        tabView.tabViewItem(at: 1).label = "Studio"
        tabView.tabViewItem(at: 1).view = makePreviewView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "control"))
        tabView.tabViewItem(at: 2).label = "Control"
        tabView.tabViewItem(at: 2).view = makeControlView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "readiness"))
        tabView.tabViewItem(at: 3).label = "Readiness"
        tabView.tabViewItem(at: 3).view = makeReadinessView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "lab"))
        tabView.tabViewItem(at: 4).label = "Lab"
        tabView.tabViewItem(at: 4).view = makeLabView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "benchmark"))
        tabView.tabViewItem(at: 5).label = "Benchmark"
        tabView.tabViewItem(at: 5).view = makeBenchmarkView()

        root.addArrangedSubview(header)
        root.addArrangedSubview(separator())
        root.addArrangedSubview(tabView)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeDoctorView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        let buttons = NSStackView(views: [
            runDoctorButton,
            runFullProofButton,
            runFaceProofButton,
            buildVisualProofButton,
            openVisualProofButton,
            markVisualWinButton,
            clearVisualWinButton,
            saveDoctorButton
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let description = NSTextField(labelWithString: "Doctor is the top-level go/no-go for the C1. It checks C1 visibility, firmware evidence, Apple effects support, hardware-control proof, the latest visual proof, and whether Studio Display should remain the daily camera.")
        description.maximumNumberOfLines = 3
        description.lineBreakMode = .byWordWrapping
        description.textColor = .secondaryLabelColor

        doctorVerdictLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        doctorVerdictLabel.maximumNumberOfLines = 3
        doctorVerdictLabel.lineBreakMode = .byWordWrapping
        doctorVerdictLabel.textColor = .systemOrange

        doctorOutput.isEditable = false
        doctorOutput.isRichText = false
        doctorOutput.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        doctorOutput.string = "Run Doctor for the current daily-camera diagnosis."
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = doctorOutput

        root.addArrangedSubview(description)
        root.addArrangedSubview(doctorVerdictLabel)
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])
        return container
    }

    private func makeControlView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        controlsStack.orientation = .vertical
        controlsStack.alignment = .leading
        controlsStack.spacing = 10

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = controlsStack
        scroll.borderType = .noBorder

        let side = NSStackView()
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 12

        let info = NSTextField(labelWithString: "Control Mode keeps preview off so Zoom, Meet, or OBS can use Opal C1 while this app manages settings.")
        info.maximumNumberOfLines = 4
        info.lineBreakMode = .byWordWrapping
        info.textColor = .secondaryLabelColor

        presetStack.orientation = .vertical
        presetStack.alignment = .leading
        presetStack.spacing = 8

        let actionRow = NSStackView(views: [lockLookButton, resetAutoButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        side.addArrangedSubview(makeConsolePanel())
        side.addArrangedSubview(info)
        side.addArrangedSubview(label("Presets"))
        side.addArrangedSubview(presetStack)
        side.addArrangedSubview(separator(width: 320))
        side.addArrangedSubview(actionRow)
        side.addArrangedSubview(selectedControlLabel)
        side.addArrangedSubview(NSView())

        root.addArrangedSubview(scroll)
        root.addArrangedSubview(side)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: 360),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 720)
        ])
        return container
    }

    private func makeReadinessView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        let buttons = NSStackView(views: [runReadinessButton, startBridgeButton, saveReadinessButton, openCameraPrivacyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let description = NSTextField(labelWithString: "Readiness checks whether the C1 Studio stack is useful for a call right now: C1 visibility, OBS Virtual Camera, benchmark evidence, hardware-control proof, root-probe promotion, and app camera permission.")
        description.maximumNumberOfLines = 3
        description.lineBreakMode = .byWordWrapping
        description.textColor = .secondaryLabelColor

        readinessOutput.isEditable = false
        readinessOutput.isRichText = false
        readinessOutput.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        readinessOutput.string = "Run Readiness Check for a current C1 Studio go/no-go."
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = readinessOutput

        root.addArrangedSubview(description)
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])
        return container
    }

    private func makePreviewView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor

        let side = NSStackView()
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 14

        goLiveButton.bezelStyle = .rounded
        goLiveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            goLiveButton,
            appleEffectsButton,
            startPreviewButton,
            stopPreviewButton,
            outputWindowButton,
            openOBSButton,
            snapshotButton,
            saveCurrentLookButton,
            applyCoachLookButton,
            refreshButton
        ])
        buttons.orientation = .vertical
        buttons.alignment = .leading
        buttons.spacing = 8

        let warning = NSTextField(labelWithString: "Go Live starts the tuned C1 preview and opens the output window for OBS Window Capture. Use Control Mode when another app should own raw camera video.")
        warning.maximumNumberOfLines = 4
        warning.lineBreakMode = .byWordWrapping
        warning.textColor = .secondaryLabelColor

        lookStack.orientation = .vertical
        lookStack.alignment = .leading
        lookStack.spacing = 8

        lookPresetStack.orientation = .vertical
        lookPresetStack.alignment = .leading
        lookPresetStack.spacing = 8
        rebuildLookPresetButtons()
        rebuildLookRows()

        side.addArrangedSubview(modeLabel)
        side.addArrangedSubview(healthLabel)
        side.addArrangedSubview(lookLabel)
        side.addArrangedSubview(systemEffectsLabel)
        side.addArrangedSubview(warning)
        side.addArrangedSubview(buttons)
        side.addArrangedSubview(separator(width: 300))
        side.addArrangedSubview(label("Look Presets"))
        side.addArrangedSubview(lookPresetStack)
        side.addArrangedSubview(separator(width: 300))
        side.addArrangedSubview(label("Live Look"))
        side.addArrangedSubview(lookStack)
        side.addArrangedSubview(NSView())

        root.addArrangedSubview(previewView)
        root.addArrangedSubview(side)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: 340),
            previewView.widthAnchor.constraint(greaterThanOrEqualToConstant: 780),
            previewView.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])
        return container
    }

    private func makeLabView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        let buttons = NSStackView(views: [runLabButton, runControlProofButton, saveLabButton, copyRootProbeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let description = NSTextField(labelWithString: "Lab Mode runs safe probes: USB descriptors, UVC GET_* control reads, Opal symbols, bridge status, system extension state, and active Opal processes. It does not flash firmware or modify system extensions.")
        description.maximumNumberOfLines = 3
        description.lineBreakMode = .byWordWrapping
        description.textColor = .secondaryLabelColor

        labOutput.isEditable = false
        labOutput.isRichText = false
        labOutput.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        labOutput.string = "Run Lab Probe to generate a fresh report."
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = labOutput

        root.addArrangedSubview(description)
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])
        return container
    }

    private func makeBenchmarkView() -> NSView {
        let container = NSView()
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.addSubview(root)

        let buttons = NSStackView(views: [runBenchmarkButton, runMotionBenchButton, runQualityCoachButton, calibrateLookButton, saveBenchmarkButton, openCameraPrivacyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let description = NSTextField(labelWithString: "Benchmark captures matched C1 and Studio Display still frames through ffmpeg, computes brightness, contrast, sharpness, saturation, and fine texture, then gives an evidence-based verdict for the current room.")
        description.maximumNumberOfLines = 3
        description.lineBreakMode = .byWordWrapping
        description.textColor = .secondaryLabelColor

        benchmarkOutput.isEditable = false
        benchmarkOutput.isRichText = false
        benchmarkOutput.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        benchmarkOutput.string = "Run C1 vs Studio Bench to capture current-lighting evidence."
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = benchmarkOutput

        root.addArrangedSubview(description)
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])
        return container
    }

    private func wireActions() {
        runDoctorButton.target = self
        runDoctorButton.action = #selector(runDoctorTapped)
        runFullProofButton.target = self
        runFullProofButton.action = #selector(runFullProofTapped)
        runFaceProofButton.target = self
        runFaceProofButton.action = #selector(runFaceProofTapped)
        buildVisualProofButton.target = self
        buildVisualProofButton.action = #selector(buildVisualProofTapped)
        saveDoctorButton.target = self
        saveDoctorButton.action = #selector(saveDoctorTapped)
        openVisualProofButton.target = self
        openVisualProofButton.action = #selector(openVisualProofTapped)
        markVisualWinButton.target = self
        markVisualWinButton.action = #selector(markVisualWinTapped)
        clearVisualWinButton.target = self
        clearVisualWinButton.action = #selector(clearVisualWinTapped)
        startPreviewButton.target = self
        startPreviewButton.action = #selector(startPreviewTapped)
        stopPreviewButton.target = self
        stopPreviewButton.action = #selector(stopPreviewTapped)
        goLiveButton.target = self
        goLiveButton.action = #selector(goLiveTapped)
        appleEffectsButton.target = self
        appleEffectsButton.action = #selector(openAppleEffectsTapped)
        openOBSButton.target = self
        openOBSButton.action = #selector(openOBSTapped)
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        snapshotButton.target = self
        snapshotButton.action = #selector(snapshotTapped)
        saveCurrentLookButton.target = self
        saveCurrentLookButton.action = #selector(saveCurrentLookTapped)
        applyCoachLookButton.target = self
        applyCoachLookButton.action = #selector(applyCoachLookTapped)
        outputWindowButton.target = self
        outputWindowButton.action = #selector(outputWindowTapped)
        startBridgeButton.target = self
        startBridgeButton.action = #selector(startBridgeTapped)
        runLabButton.target = self
        runLabButton.action = #selector(runLabTapped)
        runControlProofButton.target = self
        runControlProofButton.action = #selector(runControlProofTapped)
        saveLabButton.target = self
        saveLabButton.action = #selector(saveLabTapped)
        copyRootProbeButton.target = self
        copyRootProbeButton.action = #selector(copyRootProbeTapped)
        runBenchmarkButton.target = self
        runBenchmarkButton.action = #selector(runBenchmarkTapped)
        runMotionBenchButton.target = self
        runMotionBenchButton.action = #selector(runMotionBenchTapped)
        runQualityCoachButton.target = self
        runQualityCoachButton.action = #selector(runQualityCoachTapped)
        calibrateLookButton.target = self
        calibrateLookButton.action = #selector(calibrateLookTapped)
        saveBenchmarkButton.target = self
        saveBenchmarkButton.action = #selector(saveBenchmarkTapped)
        openCameraPrivacyButton.target = self
        openCameraPrivacyButton.action = #selector(openCameraPrivacyTapped)
        runReadinessButton.target = self
        runReadinessButton.action = #selector(runReadinessTapped)
        saveReadinessButton.target = self
        saveReadinessButton.action = #selector(saveReadinessTapped)
        lockLookButton.target = self
        lockLookButton.action = #selector(lockLookTapped)
        resetAutoButton.target = self
        resetAutoButton.action = #selector(resetAutoTapped)
    }

    private func loadControls() {
        capabilities = transport.readCapabilities()
        controlsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        controlRows.removeAll()

        for capability in capabilities where capability.key != .irisAbsolute || capability.lastError == nil {
            let row = ControlRow(capability: capability)
            row.onChange = { [weak self] key, value in
                self?.writeControl(key, value: value)
            }
            row.onSelect = { [weak self] capability in
                self?.selectedControlLabel.stringValue = self?.detailText(for: capability) ?? ""
            }
            controlsStack.addArrangedSubview(row)
            controlRows[capability.key] = row
        }

        presetStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for preset in C1PresetCatalog.presets {
            let button = NSButton(title: preset.name, target: self, action: #selector(presetTapped(_:)))
            button.bezelStyle = .rounded
            button.toolTip = preset.subtitle
            button.identifier = NSUserInterfaceItemIdentifier(preset.name)
            presetStack.addArrangedSubview(button)
        }
    }

    private func refreshDeviceState() {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
        if let opal = discovery.devices.first(where: { $0.localizedName.lowercased().contains("opal") || $0.uniqueID.lowercased().contains("f63b") }) {
            deviceLabel.stringValue = "Device: \(opal.localizedName)"
            videoPathLabel.stringValue = "Video: \(bestFormatSummary(for: opal))"
            systemEffectsLabel.stringValue = systemEffectsSummary(for: opal)
        } else {
            deviceLabel.stringValue = "Device: Opal C1 not found"
            videoPathLabel.stringValue = "Video: Opal C1 not discovered by AVFoundation"
            systemEffectsLabel.stringValue = "Apple Effects: C1 not discovered"
        }
    }

    private func writeControl(_ key: CameraControlKey, value: CameraControlValue) {
        let result = transport.writeValue(key, value: value)
        switch result {
        case .success:
            setStatus("\(key.title) updated")
        case .failure(let error):
            setStatus("\(key.title): \(error.description)")
        }
    }

    private func detailText(for capability: CameraControlCapability) -> String {
        let range = if let min = capability.minimum, let max = capability.maximum {
            "\(min)...\(max)"
        } else {
            "unknown"
        }
        let entity = capability.entity.map(String.init) ?? "?"
        let selector = capability.selector.map(String.init) ?? "?"
        return "\(capability.key.title)\nEntity \(entity), selector \(selector), range \(range)\n\(capability.status)"
    }

    private func startPreview() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startPreviewInternal()
        case .notDetermined:
            setStatus("Waiting for macOS camera permission")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    granted ? self?.startPreviewInternal() : self?.setStatus("Camera access denied")
                }
            }
        default:
            setStatus("Camera access not authorized in System Settings")
        }
    }

    private func startPreviewInternal() {
        setStatus("Starting preview")
        do {
            try configureSession()
            sessionQueue.async { [weak session] in
                session?.startRunning()
            }
            startHealthTimer()
            updateFaceFramingStatus(FaceFramingStatus(
                ready: false,
                title: "Face Proof: scanning",
                detail: "Keep your face centered while preview starts."
            ))
            setStatus("Preview running")
        } catch {
            setStatus("Preview failed: \(error.localizedDescription)")
        }
    }

    private func stopPreviewInternal() {
        sessionQueue.async { [weak session] in
            session?.stopRunning()
        }
        stopHealthTimer()
        faceFramingAnalyzer.reset()
        updateFaceFramingStatus(.stopped)
        modeLabel.stringValue = "Mode: Preview stopped"
        setStatus("Preview stopped")
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        let device = try findOpalDevice()
        currentDevice = device
        try configureBestFormat(for: device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        sampleBufferOutput.alwaysDiscardsLateVideoFrames = true
        sampleBufferOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        sampleBufferOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(sampleBufferOutput) {
            session.addOutput(sampleBufferOutput)
        }
        session.sessionPreset = .high
        deviceLabel.stringValue = "Device: \(device.localizedName)"
        modeLabel.stringValue = "Mode: \(modeDescription(for: device))"
        systemEffectsLabel.stringValue = systemEffectsSummary(for: device)
    }

    private func findOpalDevice() throws -> AVCaptureDevice {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
        if let opal = discovery.devices.first(where: { device in
            device.localizedName.lowercased().contains("opal") || device.uniqueID.lowercased().contains("f63b")
        }) {
            return opal
        }
        throw CameraError.opalNotFound(discovery.devices.map(\.localizedName).joined(separator: ", "))
    }

    private func configureBestFormat(for device: AVCaptureDevice) throws {
        let candidates = device.formats.compactMap { format -> FormatCandidate? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let bestRange = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else {
                return nil
            }
            return FormatCandidate(format: format, width: Int(dimensions.width), height: Int(dimensions.height), maxFrameRate: bestRange.maxFrameRate)
        }

        let selected = candidates
            .filter { $0.width == 1920 && $0.height == 1080 && $0.maxFrameRate >= 59 }
            .max(by: { $0.maxFrameRate < $1.maxFrameRate })
            ?? candidates
                .filter { $0.width >= 1920 && $0.height >= 1080 }
                .max(by: {
                    $0.maxFrameRate == $1.maxFrameRate
                    ? $0.width * $0.height < $1.width * $1.height
                    : $0.maxFrameRate < $1.maxFrameRate
                })
            ?? candidates.max(by: { $0.width * $0.height < $1.width * $1.height })

        guard let selected else {
            throw CameraError.noUsableFormat
        }

        try device.lockForConfiguration()
        device.activeFormat = selected.format
        let fps = min(selected.maxFrameRate, 60.000240)
        let duration = CMTime(value: 1_000_000, timescale: CMTimeScale(fps * 1_000_000))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    private func modeDescription(for device: AVCaptureDevice) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let fps = 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        return "\(dimensions.width)x\(dimensions.height) @ \(String(format: "%.2f", fps)) fps"
    }

    private func startHealthTimer() {
        frameTimer?.invalidate()
        lastFrameCounter = frameCounter
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let delta = self.frameCounter - self.lastFrameCounter
                self.lastFrameCounter = self.frameCounter
                self.healthLabel.stringValue = "Frames: \(delta)/sec"
                self.healthLabel.textColor = delta > 0 ? .secondaryLabelColor : .systemRed
            }
        }
    }

    private func stopHealthTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
        healthLabel.stringValue = ""
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = "Status: \(text)"
    }

    private func setDoctorVerdict(_ text: String, color: NSColor) {
        doctorVerdictLabel.stringValue = text
        doctorVerdictLabel.textColor = color
    }

    private func updateFaceFramingStatus(_ status: FaceFramingStatus) {
        faceProofLabel.stringValue = status.title
        faceProofLabel.toolTip = status.detail
        faceProofLabel.textColor = status.ready ? .systemGreen : .systemOrange
    }

    private func updateDoctorVerdict(from reportText: String) {
        let lines = reportText.components(separatedBy: .newlines)
        guard let diagnosisIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "## Diagnosis"
        }) else {
            setDoctorVerdict("Verdict: Diagnosis unavailable", color: .systemOrange)
            return
        }

        let diagnosis = lines[(diagnosisIndex + 1)...]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Diagnosis unavailable"

        if diagnosis.hasPrefix("Use Studio Display") {
            setDoctorVerdict("Verdict: \(diagnosis)", color: .systemRed)
        } else if diagnosis.hasPrefix("C1 allowed") {
            setDoctorVerdict("Verdict: \(diagnosis)", color: .systemGreen)
        } else {
            setDoctorVerdict("Verdict: \(diagnosis)", color: .systemOrange)
        }
    }

    private var shouldAutostartPreview: Bool {
        ProcessInfo.processInfo.environment["C1_STUDIO_AUTOSTART_PREVIEW"] == "1"
            || CommandLine.arguments.contains("--autostart-preview")
            || shouldAutostartBridge
    }

    private var shouldAutostartBridge: Bool {
        ProcessInfo.processInfo.environment["C1_STUDIO_AUTOSTART_BRIDGE"] == "1"
            || CommandLine.arguments.contains("--autostart-bridge")
    }

    @objc private func startPreviewTapped() {
        startPreview()
    }

    @objc private func goLiveTapped() {
        startOBSBridge()
        openOBSIfAvailable()
    }

    @objc private func openAppleEffectsTapped() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
        refreshDeviceState()
        setStatus("Opened Apple Video Effects. Portrait/Studio Light remain user-controlled by macOS.")
    }

    @objc private func openOBSTapped() {
        openOBSIfAvailable()
    }

    @objc private func stopPreviewTapped() {
        stopPreviewInternal()
    }

    @objc private func refreshTapped() {
        refreshDeviceState()
        stopPreviewInternal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.startPreview()
        }
    }

    @objc private func snapshotTapped() {
        guard let image = lastRenderedFrame else {
            setStatus("Start Preview and wait for a tuned frame before saving")
            return
        }
        saveRenderedFrame(image)
    }

    @objc private func outputWindowTapped() {
        if let outputWindow {
            outputWindow.close()
            self.outputWindow = nil
            outputPreviewView = nil
            outputWindowButton.title = "Open OBS Output Window"
            setStatus("OBS Output Window closed")
            return
        }

        openOutputWindow()
    }

    @objc private func startBridgeTapped() {
        tabView.selectTabViewItem(withIdentifier: "preview")
        startOBSBridge()
    }

    private func startOBSBridge() {
        if !session.isRunning {
            startPreview()
        }
        if outputWindow == nil {
            openOutputWindow()
        }
        setStatus("OBS Bridge starting: capture C1 Studio Output in OBS")
    }

    private func openOBSIfAvailable() {
        if let obsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.obsproject.obs-studio") {
            NSWorkspace.shared.openApplication(
                at: obsURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.setStatus("OBS launch failed: \(error.localizedDescription)")
                    } else {
                        self?.setStatus("OBS opened. Add Window Capture for C1 Studio Output, then start OBS Virtual Camera.")
                    }
                }
            }
            return
        }
        setStatus("OBS not found in Applications")
    }

    private func openOutputWindow() {
        let outputView = PreviewView()
        outputView.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        outputView.autoresizingMask = [.width, .height]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "C1 Studio Output"
        window.contentView = outputView
        window.delegate = self
        window.aspectRatio = NSSize(width: 16, height: 9)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if let lastRenderedFrame {
            outputView.display(lastRenderedFrame)
        }
        outputWindow = window
        outputPreviewView = outputView
        outputWindowButton.title = "Close OBS Output Window"
        setStatus("OBS Output Window ready for OBS Window Capture")
    }

    @objc private func runDoctorTapped() {
        doctorOutput.string = "Running C1 Studio Doctor..."
        setDoctorVerdict("Verdict: Running Doctor...", color: .systemOrange)
        setStatus("Running Doctor")
        Task {
            let report = await doctorRunner.run()
            lastDoctorReport = report
            doctorOutput.string = report.text
            updateDoctorVerdict(from: report.text)
            setStatus("Doctor complete")
        }
    }

    @objc private func runFullProofTapped() {
        doctorOutput.string = "Running full proof...\n\n1. Capturing C1 and Studio Display benchmark frames..."
        setDoctorVerdict("Verdict: Running full proof...", color: .systemOrange)
        setStatus("Running full proof")
        Task {
            let benchmark = await benchmarkRunner.run()
            lastBenchmarkReport = benchmark
            doctorOutput.string = benchmark.text + "\n\n2. Running Motion Bench..."

            let motion = await motionBenchRunner.run()
            lastMotionBenchReport = motion
            doctorOutput.string += "\n\n" + motion.text + "\n\n3. Building visual proof sheet..."

            let firstVisualProof = await visualProofRunner.run()
            doctorOutput.string += "\n\n" + firstVisualProof.text + "\n\n4. Running Quality Coach..."

            let coach = await qualityCoachRunner.run()
            lastQualityCoachReport = coach
            doctorOutput.string += "\n\n" + coach.text + "\n\n5. Rebuilding visual proof with coached look..."

            let visualProof = await visualProofRunner.run()
            doctorOutput.string += "\n\n" + visualProof.text + "\n\n6. Scoring processed visual variants..."

            let visualScore = await visualScoreRunner.run()
            doctorOutput.string += "\n\n" + visualScore.text + "\n\n7. Running Doctor..."

            let doctor = await doctorRunner.run()
            lastDoctorReport = doctor
            doctorOutput.string += "\n\n" + doctor.text
            updateDoctorVerdict(from: doctor.text)
            setStatus("Full proof complete")
        }
    }

    @objc private func runFaceProofTapped() {
        let framingStatus = faceFramingAnalyzer.snapshot()
        guard framingStatus.ready else {
            doctorOutput.string = """
            # Face Proof Not Ready

            \(framingStatus.title)

            \(framingStatus.detail)

            ## What To Do
            - Start preview or Go Live if it is not already running.
            - Sit centered with your full face visible.
            - Wait for the header to say `Face Proof: ready`.
            - Run Face Proof again.
            """
            setDoctorVerdict("Verdict: Face proof not ready", color: .systemOrange)
            updateFaceFramingStatus(framingStatus)
            if !session.isRunning {
                startPreview()
            }
            setStatus("Face proof blocked until live framing is ready")
            return
        }

        doctorOutput.string = """
        Running face proof...

        Sit centered in the frame and keep your face visible until the proof finishes.

        1. Capturing matched Studio Display and C1 frames...
        """
        setDoctorVerdict("Verdict: Running face proof...", color: .systemOrange)
        setStatus("Running face proof")
        Task {
            let benchmark = await benchmarkRunner.run()
            lastBenchmarkReport = benchmark
            doctorOutput.string += "\n\n" + benchmark.text + "\n\n2. Building face-gated visual proof..."

            let firstVisualProof = await visualProofRunner.run()
            doctorOutput.string += "\n\n" + firstVisualProof.text + "\n\n3. Running Quality Coach..."

            let coach = await qualityCoachRunner.run()
            lastQualityCoachReport = coach
            doctorOutput.string += "\n\n" + coach.text + "\n\n4. Rebuilding face-gated visual proof with coached look..."

            let visualProof = await visualProofRunner.run()
            doctorOutput.string += "\n\n" + visualProof.text + "\n\n5. Scoring processed visual variants..."

            let visualScore = await visualScoreRunner.run()
            doctorOutput.string += "\n\n" + visualScore.text

            let gateText = latestVisualProofGateText()
            if !gateText.isEmpty {
                doctorOutput.string += "\n\n" + gateText
            }

            let doctor = await doctorRunner.run()
            lastDoctorReport = doctor
            doctorOutput.string += "\n\n6. Doctor verdict...\n\n" + doctor.text
            updateDoctorVerdict(from: doctor.text)

            if latestVisualProofGateIsValid() {
                setStatus("Face proof valid; inspect sheet before marking a C1 win")
            } else {
                doctorOutput.string += "\n\n" + faceProofRecaptureInstructions()
                setDoctorVerdict("Verdict: Face proof invalid; recapture centered", color: .systemRed)
                setStatus("Face proof invalid; recapture with a centered face")
            }
        }
    }

    @objc private func buildVisualProofTapped() {
        doctorOutput.string = "Building visual proof sheet from latest benchmark captures..."
        setDoctorVerdict("Verdict: Visual proof pending review", color: .systemOrange)
        setStatus("Building visual proof")
        Task {
            let report = await visualProofRunner.run()
            doctorOutput.string = report.text
            setStatus("Visual proof complete")
        }
    }

    @objc private func saveDoctorTapped() {
        guard let report = lastDoctorReport else {
            setStatus("Run Doctor before saving")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-doctor-\(formatter.string(from: report.generatedAt)).md")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            setStatus("Saved \(url.path)")
        } catch {
            setStatus("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func openVisualProofTapped() {
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-latest.jpg")
        guard FileManager.default.fileExists(atPath: url.path) else {
            setStatus("Visual proof missing; run Benchmark, then visual-proof")
            return
        }
        NSWorkspace.shared.open(url)
        setStatus("Opened visual proof sheet")
    }

    @objc private func markVisualWinTapped() {
        let alert = NSAlert()
        alert.messageText = "Mark C1 as a visual win?"
        alert.informativeText = "Only do this after inspecting a fresh face-in-frame visual proof and deciding C1 Coach Tuned or C1 Signature clearly beats Studio Display."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Mark Win")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            setStatus("Visual win unchanged")
            return
        }

        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-win.txt")
        guard latestVisualProofGateIsValid() else {
            setDoctorVerdict("Verdict: Latest proof is not face-valid", color: .systemRed)
            setStatus("Visual win blocked: recapture a face-valid proof first")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "Marked by C1 Studio 2026 after visual proof review: \(Date())\n".write(to: url, atomically: true, encoding: .utf8)
            setDoctorVerdict("Verdict: C1 visual win marked; rerun Doctor", color: .systemGreen)
            setStatus("Marked C1 visual win; rerun Doctor")
        } catch {
            setStatus("Could not mark visual win: \(error.localizedDescription)")
        }
    }

    private func latestVisualProofGateIsValid() -> Bool {
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-latest.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valid = object["valid"] as? Bool else {
            return false
        }
        return valid
    }

    private func latestVisualProofGateText() -> String {
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-latest.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func faceProofRecaptureInstructions() -> String {
        """
        ## Face Proof Recapture Steps
        - Sit centered and keep your face fully visible.
        - Avoid standing up, looking down at the phone, or leaving the chair during capture.
        - Keep the same room lighting for Studio Display and C1.
        - Run Face Proof again before marking a C1 visual win.
        """
    }

    @objc private func clearVisualWinTapped() {
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-visual-proof-win.txt")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                setDoctorVerdict("Verdict: Visual win cleared; rerun Doctor", color: .systemOrange)
                setStatus("Cleared visual win; rerun Doctor")
            } catch {
                setStatus("Could not clear visual win: \(error.localizedDescription)")
            }
        } else {
            setStatus("No visual win marker exists")
        }
    }

    @objc private func runLabTapped() {
        labOutput.string = "Running read-only Lab Probe..."
        setStatus("Running Lab Probe")
        Task {
            let report = await reverseLab.run()
            lastLabReport = report
            labOutput.string = report.text
            updateBackendSummary(from: report.text)
            setStatus("Lab Probe complete")
        }
    }

    @objc private func runControlProofTapped() {
        labOutput.string = "Running hardware control proof..."
        setStatus("Running Control Proof")
        Task {
            let report = await reverseLab.runControlProof()
            lastLabReport = report
            labOutput.string = report.text
            updateBackendSummary(from: report.text)
            setStatus("Control Proof complete")
        }
    }

    @objc private func saveLabTapped() {
        guard let report = lastLabReport else {
            setStatus("Run Lab Probe before saving")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work")
            .appendingPathComponent("c1-reverse-lab-\(formatter.string(from: report.generatedAt)).md")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            setStatus("Saved \(url.path)")
        } catch {
            setStatus("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func copyRootProbeTapped() {
        let command = reverseLab.rootProbeCommand()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        setStatus("Copied reversible root probe command")
    }

    @objc private func runBenchmarkTapped() {
        benchmarkOutput.string = "Running C1 vs Studio Display quality bench..."
        setStatus("Running quality bench")
        Task {
            let report = await benchmarkRunner.run()
            lastBenchmarkReport = report
            benchmarkOutput.string = report.text
            setStatus("Quality bench complete")
        }
    }

    @objc private func runMotionBenchTapped() {
        benchmarkOutput.string = "Running short C1 vs Studio Display motion bench..."
        setStatus("Running motion bench")
        Task {
            let report = await motionBenchRunner.run()
            lastMotionBenchReport = report
            benchmarkOutput.string = report.text
            setStatus("Motion bench complete")
        }
    }

    @objc private func runQualityCoachTapped() {
        benchmarkOutput.string = "Running quality coach from latest benchmark captures..."
        setStatus("Running quality coach")
        Task {
            let report = await qualityCoachRunner.run()
            lastQualityCoachReport = report
            benchmarkOutput.string = report.text
            setStatus("Quality coach complete")
        }
    }

    @objc private func calibrateLookTapped() {
        benchmarkOutput.string = """
        Running C1 look calibration...

        1. Capturing matched Studio Display and C1 frames...
        """
        setStatus("Calibrating C1 look")
        Task {
            let benchmark = await benchmarkRunner.run()
            lastBenchmarkReport = benchmark
            benchmarkOutput.string += "\n\n" + benchmark.text + "\n\n2. Building initial visual proof gate..."

            let firstProof = await visualProofRunner.run()
            benchmarkOutput.string += "\n\n" + firstProof.text + "\n\n3. Learning Coach Tuned look from paired captures..."

            let coach = await qualityCoachRunner.run()
            lastQualityCoachReport = coach
            benchmarkOutput.string += "\n\n" + coach.text + "\n\n4. Applying learned look..."

            do {
                var look = try loadCoachLook()
                look.name = "Coach Tuned"
                savedLookPresets = LookPresetStore.append(look, to: savedLookPresets)
                rebuildLookPresetButtons()
                applyLookPreset(look, updateRows: true)
                benchmarkOutput.string += "\n\nApplied Coach Tuned look with Studio Match \(String(format: "%.2f", look.studioMatchAmount))."
                setStatus("Applied calibrated Coach Tuned look")
            } catch {
                benchmarkOutput.string += "\n\nCoach look apply failed: \(error.localizedDescription)"
                setStatus("Calibration failed: coach look unavailable")
                return
            }

            benchmarkOutput.string += "\n\n5. Rebuilding visual proof with calibrated look..."
            let proof = await visualProofRunner.run()
            benchmarkOutput.string += "\n\n" + proof.text + "\n\n6. Scoring processed variants..."

            let visualScore = await visualScoreRunner.run()
            benchmarkOutput.string += "\n\n" + visualScore.text

            if latestVisualProofGateIsValid() {
                setStatus("Calibration complete; inspect visual proof before marking any C1 win")
            } else {
                benchmarkOutput.string += "\n\nFace gate is still invalid, so calibration is applied for preview only and cannot justify daily-camera status."
                setStatus("Calibration applied; face proof still invalid")
            }
        }
    }

    @objc private func runReadinessTapped() {
        readinessOutput.string = "Running C1 Studio readiness check..."
        setStatus("Running readiness check")
        Task {
            let report = await readinessRunner.run()
            lastReadinessReport = report
            readinessOutput.string = report.text
            setStatus("Readiness check complete")
        }
    }

    @objc private func saveReadinessTapped() {
        guard let report = lastReadinessReport else {
            setStatus("Run readiness before saving")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work")
            .appendingPathComponent("c1-readiness-\(formatter.string(from: report.generatedAt)).md")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            setStatus("Saved \(url.path)")
        } catch {
            setStatus("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func saveBenchmarkTapped() {
        guard let report = lastBenchmarkReport else {
            setStatus("Run quality bench before saving")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work")
            .appendingPathComponent("c1-quality-bench-\(formatter.string(from: report.generatedAt)).md")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            setStatus("Saved \(url.path)")
        } catch {
            setStatus("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func openCameraPrivacyTapped() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            setStatus("Could not open Camera privacy settings")
            return
        }
        NSWorkspace.shared.open(url)
        setStatus("Opened Camera privacy settings")
    }

    @objc private func lockLookTapped() {
        saveCurrentLook(named: lockedLookName())
        setStatus("Saved current software look; hardware locks still need Control Proof")
    }

    @objc private func resetAutoTapped() {
        let results = transport.resetToAuto()
        summarize(results: results, label: "Reset Auto")
    }

    @objc private func presetTapped(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let preset = C1PresetCatalog.presets.first(where: { $0.name == name }) else {
            return
        }
        applyPreset(preset)
    }

    @objc private func lookPresetTapped(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let preset = allLookPresets().first(where: { $0.name == name }) else {
            return
        }
        applyLookPreset(preset, updateRows: true)
        setStatus("\(preset.name) look applied")
    }

    @objc private func saveCurrentLookTapped() {
        saveCurrentLook(named: lockedLookName())
        setStatus("Saved current look")
    }

    @objc private func applyCoachLookTapped() {
        setStatus("Running Quality Coach for software look")
        Task {
            let report = await qualityCoachRunner.run()
            lastQualityCoachReport = report
            let verdictBlocked = report.text.contains("Quality coach blocked")
            do {
                var look = try loadCoachLook()
                look.name = "Coach Tuned"
                savedLookPresets = LookPresetStore.append(look, to: savedLookPresets)
                rebuildLookPresetButtons()
                applyLookPreset(look, updateRows: true)
                setStatus(verdictBlocked ? "Applied Coach Tuned for preview; verdict still blocked" : "Applied Coach Tuned look from latest benchmark")
            } catch {
                setStatus("Coach look failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyPreset(_ preset: CameraPreset) {
        let results = transport.applyPreset(preset)
        summarize(results: results, label: preset.name)
    }

    private func summarize(results: [CameraControlKey: Result<Void, CameraControlTransportError>], label: String) {
        let failures = results.compactMap { key, result -> String? in
            if case .failure(let error) = result {
                return "\(key.title): \(error.description)"
            }
            return nil
        }
        if failures.isEmpty {
            setStatus("\(label) applied")
        } else {
            setStatus("\(label): \(failures.first ?? "blocked")")
        }
    }

    private func updateBackendSummary(from text: String) {
        if text.contains("USB: Opal C1 present") {
            controlPathLabel.stringValue = text.contains("Direct UVC: blocked")
                ? "Controls: UVC reachable as descriptors, blocked by user-session USB permissions"
                : "Controls: UVC probe returned data; inspect report before enabling writes"
        }
        if text.contains("Opal shim: running") {
            bridgePathLabel.stringValue = "Opal bridge: running, but authorization appears Opal-signed-client only"
        }
        backendLabel.stringValue = text.contains("controls report writable")
            ? "Backend: direct UVC controls appear writable in this probe"
            : "Backend: AVFoundation video ready, direct controls need helper proof"
    }

    private func applyLookPreset(_ preset: LookSettings, updateRows: Bool) {
        lookStore.replace(with: preset)
        LookPresetStore.saveActive(preset)
        lookLabel.stringValue = "Look: \(preset.name) software tuning"
        if updateRows {
            rebuildLookRows()
        }
    }

    private func loadCoachLook() throws -> LookSettings {
        let url = DoctorRunner.workspaceRoot()
            .appendingPathComponent("work")
            .appendingPathComponent("c1-coach-look-latest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LookSettings.self, from: data)
    }

    private func allLookPresets() -> [LookSettings] {
        LookPresetCatalog.presets + savedLookPresets
    }

    private func rebuildLookPresetButtons() {
        lookPresetStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for preset in LookPresetCatalog.presets {
            addLookPresetButton(preset, suffix: nil)
        }
        if !savedLookPresets.isEmpty {
            let divider = label("Saved Looks")
            divider.textColor = .secondaryLabelColor
            lookPresetStack.addArrangedSubview(divider)
        }
        for preset in savedLookPresets {
            addLookPresetButton(preset, suffix: "saved")
        }
    }

    private func addLookPresetButton(_ preset: LookSettings, suffix: String?) {
        let title = if let suffix {
            "\(preset.name) (\(suffix))"
        } else {
            preset.name
        }
        let button = NSButton(title: title, target: self, action: #selector(lookPresetTapped(_:)))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(preset.name)
        lookPresetStack.addArrangedSubview(button)
    }

    private func saveCurrentLook(named name: String) {
        var current = lookStore.snapshot()
        current.name = name
        savedLookPresets = LookPresetStore.append(current, to: savedLookPresets)
        rebuildLookPresetButtons()
        applyLookPreset(current, updateRows: true)
    }

    private func lockedLookName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return "Locked \(formatter.string(from: Date()))"
    }

    private func rebuildLookRows() {
        let settings = lookStore.snapshot()
        lookStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        lookStack.addArrangedSubview(LookControlRow(
            title: "Exposure",
            value: settings.exposureEV,
            range: -1.0...1.0,
            display: { String(format: "%+.2f EV", $0) },
            onChange: { [weak self] value in self?.updateLook(\.exposureEV, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Brightness",
            value: settings.brightness,
            range: -0.12...0.12,
            display: { String(format: "%+.3f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.brightness, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Contrast",
            value: settings.contrast,
            range: 0.75...1.35,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.contrast, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Saturation",
            value: settings.saturation,
            range: 0.65...1.35,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.saturation, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Warmth",
            value: settings.warmth,
            range: -1.0...1.0,
            display: { String(format: "%+.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.warmth, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Sharpness",
            value: settings.sharpness,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.sharpness, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Clean",
            value: settings.noiseReduction,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.noiseReduction, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Soft Highlights",
            value: settings.highlightSoftening,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.highlightSoftening, value: value) }
        ))
        let autoFaceBalance = NSButton(checkboxWithTitle: "Auto face balance", target: self, action: #selector(autoFaceBalanceChanged(_:)))
        autoFaceBalance.state = settings.autoFaceBalance ? .on : .off
        autoFaceBalance.toolTip = "Samples the face window and gently corrects exposure, warmth, and hot saturation in the software output."
        lookStack.addArrangedSubview(autoFaceBalance)
        let autoStudioGrade = NSButton(checkboxWithTitle: "Studio grade", target: self, action: #selector(autoStudioGradeChanged(_:)))
        autoStudioGrade.state = settings.autoStudioGrade ? .on : .off
        autoStudioGrade.toolTip = "Continuously adapts exposure, tint, shadows, and highlight recovery for the current scene."
        lookStack.addArrangedSubview(autoStudioGrade)
        lookStack.addArrangedSubview(LookControlRow(
            title: "Grade Strength",
            value: settings.studioGradeAmount,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.studioGradeAmount, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Studio Match",
            value: settings.studioMatchAmount,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.studioMatchAmount, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Skin Protect",
            value: settings.skinToneProtect,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.skinToneProtect, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Vignette",
            value: settings.vignette,
            range: 0...0.8,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.vignette, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Portrait Light",
            value: settings.portraitLift,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.portraitLift, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Background Blur",
            value: settings.backgroundBlur,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.backgroundBlur, value: value) }
        ))
        lookStack.addArrangedSubview(LookControlRow(
            title: "Background Dim",
            value: settings.backgroundDim,
            range: 0...1,
            display: { String(format: "%.2f", $0) },
            onChange: { [weak self] value in self?.updateLook(\.backgroundDim, value: value) }
        ))
        let mirror = NSButton(checkboxWithTitle: "Mirror preview", target: self, action: #selector(mirrorChanged(_:)))
        mirror.state = settings.mirror ? .on : .off
        lookStack.addArrangedSubview(mirror)
    }

    private func updateLook(_ keyPath: WritableKeyPath<LookSettings, Double>, value: Double) {
        let settings = lookStore.update { current in
            current.name = "Custom"
            current[keyPath: keyPath] = value
        }
        LookPresetStore.saveActive(settings)
        lookLabel.stringValue = "Look: \(settings.name) software tuning"
    }

    @objc private func autoFaceBalanceChanged(_ sender: NSButton) {
        let settings = lookStore.update { current in
            current.name = "Custom"
            current.autoFaceBalance = sender.state == .on
        }
        LookPresetStore.saveActive(settings)
        lookLabel.stringValue = "Look: \(settings.name) software tuning"
        setStatus(settings.autoFaceBalance ? "Auto face balance enabled" : "Auto face balance disabled")
    }

    @objc private func autoStudioGradeChanged(_ sender: NSButton) {
        let settings = lookStore.update { current in
            current.name = "Custom"
            current.autoStudioGrade = sender.state == .on
        }
        LookPresetStore.saveActive(settings)
        lookLabel.stringValue = "Look: \(settings.name) software tuning"
        setStatus(settings.autoStudioGrade ? "Studio grade enabled" : "Studio grade disabled")
    }

    @objc private func mirrorChanged(_ sender: NSButton) {
        let settings = lookStore.update { current in
            current.name = "Custom"
            current.mirror = sender.state == .on
        }
        LookPresetStore.saveActive(settings)
        lookLabel.stringValue = "Look: \(settings.name) software tuning"
    }

    private func displayRenderedFrame(_ image: CGImage) {
        lastRenderedFrame = image
        previewView.display(image)
        outputPreviewView?.display(image)
    }

    private func saveRenderedFrame(_ image: CGImage) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Pictures")
            .appendingPathComponent("C1Studio-Tuned-\(Int(Date().timeIntervalSince1970)).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            setStatus("Tuned frame save failed: could not create destination")
            return
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        if CGImageDestinationFinalize(destination) {
            setStatus("Tuned frame saved: \(url.path)")
        } else {
            setStatus("Tuned frame save failed")
        }
    }

    private func bestFormatSummary(for device: AVCaptureDevice) -> String {
        let candidates = device.formats.compactMap { format -> FormatCandidate? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let bestRange = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else {
                return nil
            }
            return FormatCandidate(format: format, width: Int(dimensions.width), height: Int(dimensions.height), maxFrameRate: bestRange.maxFrameRate)
        }
        if candidates.contains(where: { $0.width == 1920 && $0.height == 1080 && $0.maxFrameRate >= 59 }) {
            return "\(device.localizedName) can run 1080p60-class video"
        }
        if let best = candidates.max(by: {
            $0.width * $0.height == $1.width * $1.height
            ? $0.maxFrameRate < $1.maxFrameRate
            : $0.width * $0.height < $1.width * $1.height
        }) {
            return "\(device.localizedName) best visible mode \(best.width)x\(best.height) @ \(String(format: "%.0f", best.maxFrameRate)) fps"
        }
        return "\(device.localizedName) found, no formats reported"
    }

    private func systemEffectsSummary(for device: AVCaptureDevice) -> String {
        let portraitFormats = device.formats.filter { $0.isPortraitEffectSupported }.count
        let centerStageFormats = device.formats.filter { $0.isCenterStageSupported }.count
        let studioLightFormats: Int
        if #available(macOS 13.0, *) {
            studioLightFormats = device.formats.filter { $0.isStudioLightSupported }.count
        } else {
            studioLightFormats = 0
        }

        var active = [
            "Portrait \(device.isPortraitEffectActive ? "active" : (AVCaptureDevice.isPortraitEffectEnabled ? "enabled" : "off"))",
            "Center Stage \(device.isCenterStageActive ? "active" : (AVCaptureDevice.isCenterStageEnabled ? "enabled" : "off"))"
        ]
        if #available(macOS 13.0, *) {
            active.append("Studio Light \(device.isStudioLightActive ? "active" : (AVCaptureDevice.isStudioLightEnabled ? "enabled" : "off"))")
        }

        return "Apple Effects: \(portraitFormats) portrait, \(studioLightFormats) studio-light, \(centerStageFormats) center-stage formats. \(active.joined(separator: ", "))."
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        return field
    }

    private func makeConsolePanel() -> NSView {
        let panel = NSBox()
        panel.boxType = .custom
        panel.cornerRadius = 8
        panel.borderWidth = 1
        panel.borderColor = .separatorColor
        panel.contentViewMargins = NSSize(width: 12, height: 12)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = label("C1 Console")
        [deviceLabel, videoPathLabel, backendLabel, controlPathLabel, bridgePathLabel, irisLabel].forEach {
            $0.maximumNumberOfLines = 3
            $0.lineBreakMode = .byWordWrapping
            $0.textColor = .secondaryLabelColor
            stack.addArrangedSubview($0)
        }
        stack.insertArrangedSubview(title, at: 0)

        panel.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: 340)
        ])
        return panel
    }

    private func separator(width: CGFloat? = nil) -> NSView {
        let line = NSBox()
        line.boxType = .separator
        if let width {
            line.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return line
    }
}

@MainActor
extension StudioController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === outputWindow else {
            return
        }
        outputWindow = nil
        outputPreviewView = nil
        outputWindowButton.title = "Open OBS Output Window"
        setStatus("OBS Output Window closed")
    }
}

extension StudioController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let faceStatus = faceFramingAnalyzer.analyze(pixelBuffer: pixelBuffer)
        let settings = lookStore.snapshot()
        guard let image = lookRenderer.render(pixelBuffer: pixelBuffer, settings: settings) else {
            return
        }
        Task { @MainActor [image, faceStatus] in
            self.frameCounter += 1
            if let faceStatus {
                self.updateFaceFramingStatus(faceStatus)
            }
            self.displayRenderedFrame(image)
        }
    }
}

final class ControlRow: NSView {
    var onChange: ((CameraControlKey, CameraControlValue) -> Void)?
    var onSelect: ((CameraControlCapability) -> Void)?

    private let capability: CameraControlCapability
    private let valueField = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let checkbox: NSButton?

    init(capability: CameraControlCapability) {
        self.capability = capability
        let min = Double(capability.minimum ?? 0)
        let max = Double(capability.maximum ?? 1)
        self.slider = NSSlider(value: Double(capability.defaultIntValue), minValue: min, maxValue: max, target: nil, action: nil)
        if case .bool(let current) = capability.currentValue {
            self.checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            self.checkbox?.state = current ? .on : .off
        } else {
            self.checkbox = nil
        }
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func build() {
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.alignment = .centerY
        root.spacing = 10
        addSubview(root)

        let title = NSTextField(labelWithString: capability.key.title)
        title.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let entity = capability.entity.map(String.init) ?? "?"
        let selector = capability.selector.map(String.init) ?? "?"
        let meta = NSTextField(labelWithString: "E\(entity) S\(selector)")
        meta.textColor = .tertiaryLabelColor
        meta.widthAnchor.constraint(equalToConstant: 58).isActive = true

        valueField.stringValue = capability.currentValue.displayValue
        valueField.widthAnchor.constraint(equalToConstant: 86).isActive = true

        root.addArrangedSubview(title)
        root.addArrangedSubview(meta)

        if let checkbox {
            checkbox.isEnabled = capability.writable
            checkbox.target = self
            checkbox.action = #selector(checkChanged)
            root.addArrangedSubview(checkbox)
        } else {
            slider.isEnabled = capability.writable
            slider.target = self
            slider.action = #selector(sliderChanged)
            slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
            root.addArrangedSubview(slider)
        }

        root.addArrangedSubview(valueField)

        let info = NSButton(title: "Inspect", target: self, action: #selector(inspectTapped))
        root.addArrangedSubview(info)

        toolTip = capability.status
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 650)
        ])
    }

    @objc private func sliderChanged() {
        let value = Int(slider.doubleValue.rounded())
        valueField.stringValue = "\(value)"
        onChange?(capability.key, .int(value))
    }

    @objc private func checkChanged() {
        let value = checkbox?.state == .on
        valueField.stringValue = value ? "On" : "Off"
        onChange?(capability.key, .bool(value))
    }

    @objc private func inspectTapped() {
        onSelect?(capability)
    }
}

private extension CameraControlCapability {
    var defaultIntValue: Int {
        if case .int(let value) = defaultValue {
            return value
        }
        return 0
    }
}

final class PreviewView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspectFill
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
    }

    required init?(coder: NSCoder) {
        nil
    }

    func display(_ image: CGImage) {
        layer?.contents = image
    }
}

final class LookControlRow: NSView {
    private let valueField = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let display: (Double) -> String
    private let onChange: (Double) -> Void

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        display: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) {
        self.slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.display = display
        self.onChange = onChange
        super.init(frame: .zero)

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.alignment = .centerY
        root.spacing = 8
        addSubview(root)

        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 104).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 136).isActive = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        valueField.stringValue = display(value)
        valueField.widthAnchor.constraint(equalToConstant: 68).isActive = true

        root.addArrangedSubview(label)
        root.addArrangedSubview(slider)
        root.addArrangedSubview(valueField)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            widthAnchor.constraint(equalToConstant: 300)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func sliderChanged() {
        let value = slider.doubleValue
        valueField.stringValue = display(value)
        onChange(value)
    }
}

private struct FormatCandidate {
    let format: AVCaptureDevice.Format
    let width: Int
    let height: Int
    let maxFrameRate: Double
}

private enum CameraError: LocalizedError {
    case opalNotFound(String)
    case cannotAddInput
    case noUsableFormat

    var errorDescription: String? {
        switch self {
        case .opalNotFound(let devices):
            if devices.isEmpty {
                return "Opal C1 not found. No external cameras were discovered."
            }
            return "Opal C1 not found. External cameras: \(devices)"
        case .cannotAddInput:
            return "Could not add Opal C1 as a capture input."
        case .noUsableFormat:
            return "No usable Opal C1 video format was reported by AVFoundation."
        }
    }
}

if CommandLine.arguments.contains("--look-render-smoke") {
    exit(LookSmoke.run())
} else if CommandLine.arguments.contains("--coach-look-smoke") {
    let url = DoctorRunner.workspaceRoot()
        .appendingPathComponent("work")
        .appendingPathComponent("c1-coach-look-latest.json")
    exit(LookSmoke.run(settingsURL: url))
} else if CommandLine.arguments.contains("--active-look-smoke") {
    exit(LookSmoke.runActivePersistenceSmoke())
} else if CommandLine.arguments.contains("--visual-proof") {
    exit(VisualProof.run())
} else if CommandLine.arguments.contains("--apple-effects-probe") {
    AppleEffectsProbe.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    _ = delegate
}
