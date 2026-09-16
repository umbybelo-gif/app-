import AVFoundation
import Observation
import UIKit

/// Gestisce l'intera sessione di acquisizione: selezione del formato migliore,
/// stabilizzazione, codec, controlli manuali e registrazione su file.
@Observable
final class CameraController: NSObject, AVCaptureFileOutputRecordingDelegate {

    enum Status: Equatable {
        case idle
        case running
        case denied(String)
        case failed(String)
    }

    // MARK: Stato osservabile dalla UI

    var status: Status = .idle
    var isRecording = false
    var recordedDuration: TimeInterval = 0
    private(set) var settings: CaptureSettings = .load()

    var appliedStabilization = "—"
    var appliedCodec = "—"
    var appliedColor = "—"
    var activeLensName = "—"
    var isFrontCamera = false

    var zoom: CGFloat = 1            // fattore mostrato all'utente (es. 0.5×, 1×, 3×)
    var zoomStops: [CGFloat] = [1]
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 1

    var torchOn = false
    var hasTorch = false

    var isFocusLocked = false
    var lensPosition: Float = 0.5
    var isExposureLocked = false
    var exposureBias: Float = 0
    var minExposureBias: Float = -2
    var maxExposureBias: Float = 2
    var iso: Float = 100
    var minISO: Float = 30
    var maxISO: Float = 800
    var shutterDenominator: Double = 60
    var isWhiteBalanceLocked = false
    var colorTemperature: Float = 5200

    var availableResolutions: [Resolution] = []
    var availableFrameRates: [Double] = []
    var supportsProRes = false
    var supportsAppleLog = false
    var supportsHDR = false

    var message: String?
    var isInterrupted = false

    /// Modifica le impostazioni di ripresa, le salva e riapplica il formato.
    func updateSettings(reapply: Bool = true, _ mutate: (inout CaptureSettings) -> Void) {
        mutate(&settings)
        settings.save()
        refreshFrameRates()
        if reapply { applyFormat() }
    }

    /// Chiamata al termine di ogni registrazione, sul main thread.
    @ObservationIgnored var onFinishedRecording: ((URL, CaptureMetadata, Error?) -> Void)?

    // MARK: Interni

    @ObservationIgnored let previewLayer = AVCaptureVideoPreviewLayer()
    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.ciak.session")
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored private var audioInput: AVCaptureDeviceInput?
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var configurationFailed = false
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var captureRotationAngle: CGFloat = 90
    @ObservationIgnored private var durationTimer: Timer?
    @ObservationIgnored private var pendingURL: URL?
    /// Moltiplicatore fra zoom mostrato e zoom reale (2 sui telefoni con ultra-grandangolo).
    @ObservationIgnored private var zoomDisplayBase: CGFloat = 1

    private var device: AVCaptureDevice? { videoInput?.device }

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        registerForNotifications()
    }

    deinit {
        rotationObservers.forEach { $0.invalidate() }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Permessi

    func requestPermissionsAndStart() {
        // Sul Simulatore non c'è nulla da autorizzare: evitiamo un permesso inutile
        // e diciamo subito come stanno le cose.
        if Self.isSimulator {
            status = .failed(Self.noCameraReason)
            return
        }
        Task {
            let video = await Self.ensureAuthorization(for: .video)
            guard video else {
                await MainActor.run {
                    self.status = .denied("Serve l'accesso alla fotocamera. Aprilo da Impostazioni › Ciak.")
                }
                return
            }
            _ = await Self.ensureAuthorization(for: .audio)
            self.start()
        }
    }

    private static func ensureAuthorization(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        default: return false
        }
    }

    // MARK: Avvio / arresto

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured {
                configureSession()
                isConfigured = true
            }
            // Senza fotocamera la sessione partirebbe comunque, a vuoto:
            // meglio lasciare visibile l'errore già registrato.
            guard !configurationFailed else { return }
            if !session.isRunning { session.startRunning() }
            let running = session.isRunning
            DispatchQueue.main.async {
                if running { self.status = .running }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Configurazione della sessione

    private func configureSession() {
        session.beginConfiguration()
        // inputPriority lascia decidere al formato del dispositivo, non a un preset generico:
        // è l'unico modo per ottenere davvero 4K60, HDR o ProRes.
        session.sessionPreset = .inputPriority
        session.automaticallyConfiguresApplicationAudioSession = false

        guard let camera = Self.bestCamera(front: false) else {
            session.commitConfiguration()
            configurationFailed = true
            DispatchQueue.main.async { self.status = .failed(Self.noCameraReason) }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
            videoInput = input
        } catch {
            session.commitConfiguration()
            configurationFailed = true
            DispatchQueue.main.async {
                self.status = .failed("Fotocamera non disponibile: \(error.localizedDescription)")
            }
            return
        }

        configureAudioSession()
        attachAudioInput()

        movieOutput.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        session.commitConfiguration()

        applyFormat()
        refreshCapabilities()
        setUpRotationCoordinator()
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording,
                                         options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            DispatchQueue.main.async { self.message = "Audio non configurabile: \(error.localizedDescription)" }
        }
    }

    private func attachAudioInput() {
        if let existing = audioInput {
            session.removeInput(existing)
            audioInput = nil
        }
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        audioInput = input
        applyAudioEnhancements(input, device: audioDevice)
    }

    /// Audio stereo e riduzione del rumore del vento: disponibili solo su alcune versioni di iOS.
    /// Vengono impostati in modo dinamico così l'app resta compilabile e sicura ovunque.
    private func applyAudioEnhancements(_ input: AVCaptureDeviceInput, device: AVCaptureDevice) {
        let stereoValue = NSNumber(value: 2) // AVCaptureMultichannelAudioMode.stereo
        let setterSelector = NSSelectorFromString("setMultichannelAudioMode:")
        let supportedGetter = NSSelectorFromString("supportedMultichannelAudioModes")
        if settings.stereoAudio,
           input.responds(to: setterSelector),
           device.activeFormat.responds(to: supportedGetter),
           let modes = device.activeFormat.value(forKey: "supportedMultichannelAudioModes") as? [NSNumber],
           modes.contains(stereoValue) {
            input.setValue(stereoValue, forKey: "multichannelAudioMode")
        }

        let windSupported = NSSelectorFromString("isWindNoiseRemovalSupported")
        let windSetter = NSSelectorFromString("setWindNoiseRemovalEnabled:")
        if input.responds(to: windSupported), input.responds(to: windSetter),
           (input.value(forKey: "isWindNoiseRemovalSupported") as? Bool) == true {
            input.setValue(settings.windNoiseRemoval, forKey: "windNoiseRemovalEnabled")
        }
    }

    /// Sul Simulatore non esiste hardware di acquisizione: va detto chiaramente
    /// invece di lasciare uno schermo nero.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var noCameraReason: String {
        isSimulator
            ? "Il Simulatore di iOS non ha una fotocamera: per provare la ripresa serve un iPhone vero. Tutto il resto dell'app funziona, e qui puoi aggiungere video importandoli."
            : "Nessuna fotocamera disponibile su questo dispositivo."
    }

    // MARK: Scelta della fotocamera

    private static func bestCamera(front: Bool) -> AVCaptureDevice? {
        // I dispositivi "virtuali" (triplo / doppio) permettono lo zoom continuo fra le lenti.
        let types: [AVCaptureDevice.DeviceType] = front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types,
                                                         mediaType: .video,
                                                         position: front ? .front : .back)
        return discovery.devices.first
    }

    // MARK: Formato, codec, stabilizzazione

    /// Sceglie il formato del sensore che meglio soddisfa le impostazioni richieste
    /// e applica codec e stabilizzazione coerenti.
    func applyFormat() {
        sessionQueue.async { [self] in
            guard let device else { return }
            let desired = settings

            guard let format = Self.selectFormat(device: device, settings: desired) else {
                DispatchQueue.main.async { self.message = "Nessun formato compatibile con queste impostazioni." }
                return
            }

            session.beginConfiguration()
            do {
                try device.lockForConfiguration()

                device.activeFormat = format

                let fps = format.supports(fps: desired.fps) ? desired.fps : format.maxFrameRate
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration

                switch desired.color {
                case .appleLog:
                    if #available(iOS 17.0, *), format.supportedColorSpaces.contains(.appleLog) {
                        device.activeColorSpace = .appleLog
                    }
                case .hdr:
                    if format.isVideoHDRSupported {
                        device.automaticallyAdjustsVideoHDREnabled = false
                        device.isVideoHDREnabled = true
                    }
                    if format.supportedColorSpaces.contains(.HLG_BT2020) {
                        device.activeColorSpace = .HLG_BT2020
                    }
                case .sdr:
                    device.automaticallyAdjustsVideoHDREnabled = true
                    if format.supportedColorSpaces.contains(.sRGB) {
                        device.activeColorSpace = .sRGB
                    }
                }

                if device.isSubjectAreaChangeMonitoringEnabled == false {
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }

                device.unlockForConfiguration()
            } catch {
                session.commitConfiguration()
                DispatchQueue.main.async { self.message = "Formato non applicabile: \(error.localizedDescription)" }
                return
            }
            session.commitConfiguration()

            let stabilization = applyStabilization(format: format, preference: desired.stabilization)
            let codec = applyCodec(desired.codec)
            let dims = format.dimensions
            let realFPS = format.supports(fps: desired.fps) ? desired.fps : format.maxFrameRate
            let colorLabel = desired.color.label

            DispatchQueue.main.async {
                self.appliedStabilization = stabilization
                self.appliedCodec = codec
                self.appliedColor = colorLabel
                // Allinea le impostazioni a ciò che il sensore ha davvero accettato.
                var corrected = false
                if Int(dims.width) != self.settings.width || Int(dims.height) != self.settings.height {
                    self.settings.width = Int(dims.width)
                    self.settings.height = Int(dims.height)
                    corrected = true
                }
                if abs(realFPS - self.settings.fps) > 0.01 {
                    self.settings.fps = realFPS
                    corrected = true
                }
                if corrected { self.settings.save() }
                self.refreshFrameRates()
                self.refreshManualControlRanges()
            }
        }
    }

    private static func selectFormat(device: AVCaptureDevice, settings: CaptureSettings) -> AVCaptureDevice.Format? {
        var candidates = device.formats.filter { $0.mediaType == .video }

        // I formati ProRes registrano *sempre* in ProRes: vanno usati solo se richiesto.
        candidates = candidates.filter { settings.codec == .proRes ? $0.isProResFormat : !$0.isProResFormat }

        switch settings.color {
        case .appleLog: candidates = candidates.filter(\.supportsAppleLog)
        case .hdr: candidates = candidates.filter(\.isTenBit)
        case .sdr: break
        }

        let withFPS = candidates.filter { $0.supports(fps: settings.fps) }
        if !withFPS.isEmpty { candidates = withFPS }
        guard !candidates.isEmpty else { return nil }

        let targetPixels = settings.width * settings.height
        let preferredModes = settings.stabilization.candidates

        func score(_ format: AVCaptureDevice.Format) -> Double {
            let dims = format.dimensions
            let pixels = Int(dims.width) * Int(dims.height)
            // Penalizza la distanza dalla risoluzione richiesta, senza scartare nulla a priori.
            var value = -abs(Double(pixels - targetPixels))
            if pixels == targetPixels { value += 1_000_000_000 }
            if preferredModes.contains(where: { format.isVideoStabilizationModeSupported($0) }) {
                value += 500_000_000
            }
            if settings.color != .sdr && format.isTenBit { value += 250_000_000 }
            if !format.isVideoBinned { value += 100_000_000 }
            value += format.maxFrameRate * 1_000
            return value
        }

        return candidates.max { score($0) < score($1) }
    }

    private func applyStabilization(format: AVCaptureDevice.Format,
                                    preference: StabilizationPreference) -> String {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoStabilizationSupported
        else { return "Non supportata" }

        if preference == .off {
            connection.preferredVideoStabilizationMode = .off
            return "Off"
        }

        for mode in preference.candidates where format.isVideoStabilizationModeSupported(mode) {
            connection.preferredVideoStabilizationMode = mode
            return mode.label
        }
        connection.preferredVideoStabilizationMode = .auto
        return "Auto"
    }

    private func applyCodec(_ preference: CodecPreference) -> String {
        guard let connection = movieOutput.connection(with: .video) else { return "—" }
        let available = movieOutput.availableVideoCodecTypes

        let wanted: [AVVideoCodecType]
        switch preference {
        case .hevc: wanted = [.hevc]
        case .h264: wanted = [.h264]
        case .proRes: wanted = [.proRes422HQ, .proRes422, .proRes4444, .proRes422LT]
        }

        for codec in wanted where available.contains(codec) {
            movieOutput.setOutputSettings([AVVideoCodecKey: codec], for: connection)
            return codec.displayLabel
        }
        return available.first?.displayLabel ?? "—"
    }

    // MARK: Capacità del dispositivo

    private func refreshCapabilities() {
        guard let device else { return }
        let formats = device.formats.filter { $0.mediaType == .video }

        let proRes = formats.contains(where: \.isProResFormat)
        let log = formats.contains(where: \.supportsAppleLog)
        let hdr = formats.contains { $0.isTenBit && !$0.isProResFormat }

        var seen = Set<String>()
        var resolutions: [Resolution] = []
        for format in formats {
            let resolution = Resolution(format.dimensions)
            if seen.insert(resolution.id).inserted { resolutions.append(resolution) }
        }
        resolutions.sort { $0.pixels > $1.pixels }

        let torch = device.hasTorch
        let front = device.position == .front
        let lens = device.localizedName

        DispatchQueue.main.async {
            self.supportsProRes = proRes
            self.supportsAppleLog = log
            self.supportsHDR = hdr
            self.availableResolutions = resolutions
            self.hasTorch = torch
            self.isFrontCamera = front
            self.activeLensName = lens
            self.refreshFrameRates()
            self.refreshZoomRange()
            self.refreshManualControlRanges()
        }
    }

    /// Frame rate realmente disponibili per la risoluzione attualmente scelta.
    func refreshFrameRates() {
        guard let device else { return }
        let target = settings
        var rates = Set<Double>()
        for format in device.formats where format.mediaType == .video {
            guard target.codec == .proRes ? format.isProResFormat : !format.isProResFormat else { continue }
            let d = format.dimensions
            guard Int(d.width) == target.width, Int(d.height) == target.height else { continue }
            if target.color == .appleLog && !format.supportsAppleLog { continue }
            if target.color == .hdr && !format.isTenBit { continue }
            for candidate in [24.0, 25.0, 30.0, 50.0, 60.0, 100.0, 120.0, 240.0]
            where format.supports(fps: candidate) {
                rates.insert(candidate)
            }
        }
        availableFrameRates = rates.sorted()
    }

    private func refreshZoomRange() {
        guard let device else { return }
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        zoomDisplayBase = hasUltraWide ? 2.0 : 1.0

        minZoom = device.minAvailableVideoZoomFactor / zoomDisplayBase
        maxZoom = min(device.maxAvailableVideoZoomFactor / zoomDisplayBase, 15)

        // Fermate rapide sui punti di passaggio fra le lenti reali.
        var stops: [CGFloat] = [minZoom, 1]
        for value in device.virtualDeviceSwitchOverVideoZoomFactors {
            stops.append(CGFloat(truncating: value) / zoomDisplayBase)
        }
        stops.append(contentsOf: [2, 5].map { CGFloat($0) })
        zoomStops = Array(Set(stops.map { ($0 * 10).rounded() / 10 }))
            .filter { $0 >= minZoom - 0.01 && $0 <= maxZoom }
            .sorted()
        zoom = device.videoZoomFactor / zoomDisplayBase
    }

    private func refreshManualControlRanges() {
        guard let device else { return }
        let format = device.activeFormat
        minISO = format.minISO
        maxISO = format.maxISO
        iso = min(max(device.iso, minISO), maxISO)
        minExposureBias = device.minExposureTargetBias
        maxExposureBias = device.maxExposureTargetBias
        exposureBias = device.exposureTargetBias
        lensPosition = device.lensPosition
        let seconds = CMTimeGetSeconds(device.exposureDuration)
        if seconds > 0 { shutterDenominator = (1 / seconds).rounded() }
    }

    // MARK: Rotazione

    private func setUpRotationCoordinator() {
        guard let device else { return }
        DispatchQueue.main.async { [self] in
            rotationObservers.forEach { $0.invalidate() }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator

            let previewObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                       options: [.initial, .new]) { [weak self] coordinator, _ in
                guard let self else { return }
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                if let connection = self.previewLayer.connection,
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }

            let captureObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                       options: [.initial, .new]) { [weak self] coordinator, _ in
                guard let self else { return }
                self.captureRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            }

            rotationObservers = [previewObserver, captureObserver]
        }
    }

    // MARK: Registrazione

    func startRecording(to url: URL) {
        sessionQueue.async { [self] in
            guard !movieOutput.isRecording else { return }

            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(captureRotationAngle) {
                    connection.videoRotationAngle = captureRotationAngle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isFrontCamera && settings.mirrorFrontCamera
                }
            }

            pendingURL = url
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [self] in
            guard movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { [self] in
            isRecording = true
            recordedDuration = 0
            UIApplication.shared.isIdleTimerDisabled = true
            durationTimer?.invalidate()
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.recordedDuration = CMTimeGetSeconds(output.recordedDuration)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        let metadata = CaptureMetadata(codec: appliedCodec,
                                       colorMode: appliedColor,
                                       stabilization: appliedStabilization,
                                       lens: activeLensName,
                                       fps: settings.fps)
        DispatchQueue.main.async { [self] in
            isRecording = false
            durationTimer?.invalidate()
            durationTimer = nil
            recordedDuration = 0
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
            pendingURL = nil

            // Un errore "interrotto ma registrato" produce comunque un file valido.
            let recoverable = (error as NSError?)?
                .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            onFinishedRecording?(outputFileURL, metadata, recoverable ? nil : error)
        }
    }

    // MARK: Controlli manuali

    func switchCamera() {
        sessionQueue.async { [self] in
            guard let current = videoInput else { return }
            let wantFront = current.device.position != .front
            guard let newDevice = Self.bestCamera(front: wantFront),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice)
            else { return }

            session.beginConfiguration()
            session.removeInput(current)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoInput = newInput
            } else {
                session.addInput(current)
            }
            session.commitConfiguration()

            applyFormat()
            refreshCapabilities()
            setUpRotationCoordinator()
        }
    }

    func setZoom(_ displayFactor: CGFloat, animated: Bool = true) {
        sessionQueue.async { [self] in
            guard let device else { return }
            let raw = min(max(displayFactor * zoomDisplayBase, device.minAvailableVideoZoomFactor),
                          device.maxAvailableVideoZoomFactor)
            do {
                try device.lockForConfiguration()
                if animated {
                    device.ramp(toVideoZoomFactor: raw, withRate: 8)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = raw
                }
                device.unlockForConfiguration()
            } catch { return }
            let shown = raw / zoomDisplayBase
            DispatchQueue.main.async { self.zoom = shown }
        }
    }

    func toggleTorch() {
        sessionQueue.async { [self] in
            guard let device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if device.torchMode == .on {
                    device.torchMode = .off
                } else {
                    try? device.setTorchModeOn(level: 1.0)
                }
                let on = device.torchMode == .on
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = on }
            } catch { return }
        }
    }

    /// Messa a fuoco ed esposizione sul punto toccato nell'anteprima.
    func focusAndExpose(atPreviewPoint point: CGPoint) {
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async {
                self.isFocusLocked = false
                self.isExposureLocked = false
            }
        }
    }

    func setFocusLocked(_ locked: Bool) {
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if locked, device.isFocusModeSupported(.locked) {
                    device.setFocusModeLocked(lensPosition: device.lensPosition, completionHandler: nil)
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async { self.isFocusLocked = locked }
        }
    }

    func setLensPosition(_ position: Float) {
        sessionQueue.async { [self] in
            guard let device, device.isFocusModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: min(max(position, 0), 1), completionHandler: nil)
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async {
                self.lensPosition = position
                self.isFocusLocked = true
            }
        }
    }

    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [self] in
            guard let device else { return }
            let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async { self.exposureBias = clamped }
        }
    }

    /// Esposizione manuale: otturatore espresso come denominatore (1/50, 1/60…).
    func setManualExposure(shutterDenominator: Double, iso: Float) {
        sessionQueue.async { [self] in
            guard let device, device.isExposureModeSupported(.custom) else { return }
            let format = device.activeFormat
            let duration = CMTime(seconds: 1 / max(shutterDenominator, 1), preferredTimescale: 1_000_000)
            let clampedDuration = CMTimeClampToRange(duration,
                                                     range: CMTimeRange(start: format.minExposureDuration,
                                                                        duration: CMTimeSubtract(format.maxExposureDuration,
                                                                                                 format.minExposureDuration)))
            let clampedISO = min(max(iso, format.minISO), format.maxISO)
            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async {
                self.isExposureLocked = true
                self.iso = clampedISO
                self.shutterDenominator = shutterDenominator
            }
        }
    }

    func setAutoExposure() {
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async { self.isExposureLocked = false }
        }
    }

    func setWhiteBalance(temperature: Float?) {
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if let temperature, device.isWhiteBalanceModeSupported(.locked) {
                    let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
                    var gains = device.deviceWhiteBalanceGains(for: values)
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = min(max(gains.redGain, 1), maxGain)
                    gains.greenGain = min(max(gains.greenGain, 1), maxGain)
                    gains.blueGain = min(max(gains.blueGain, 1), maxGain)
                    device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async {
                self.isWhiteBalanceLocked = temperature != nil
                if let temperature { self.colorTemperature = temperature }
            }
        }
    }

    // MARK: Notifiche di sistema

    private func registerForNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                           object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self.message = "Errore di acquisizione: \(error?.localizedDescription ?? "sconosciuto")"
            // Un errore in ripresa è quasi sempre recuperabile riavviando la sessione.
            self.start()
        }
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                           object: session, queue: .main) { [weak self] _ in
            self?.isInterrupted = true
        }
        center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                           object: session, queue: .main) { [weak self] _ in
            self?.isInterrupted = false
        }
        center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isFocusLocked, !self.isExposureLocked else { return }
            self.resetFocusAndExposureToAuto()
        }
    }

    private func resetFocusAndExposureToAuto() {
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { return }
        }
    }
}

enum CameraError: Error { case cannotAddInput }

extension AVVideoCodecType {
    var displayLabel: String {
        switch self {
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        case .proRes422: return "ProRes 422"
        case .proRes422HQ: return "ProRes 422 HQ"
        case .proRes422LT: return "ProRes 422 LT"
        case .proRes4444: return "ProRes 4444"
        default: return rawValue
        }
    }
}
