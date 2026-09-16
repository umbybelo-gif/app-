import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CameraScreen: View {
    let target: RecordingTarget

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    @State private var focusPoint: CGPoint?
    @State private var focusToken = 0
    @State private var pinchStartZoom: CGFloat = 1
    @State private var showSettings = false
    @State private var showManualControls = false
    @State private var savingClip = false
    @State private var errorMessage: String?
    @State private var showPhotoImport = false
    @State private var showFileImport = false

    private var sketch: Sketch? { store.sketch(target) }
    private var project: Project? { store.project(target.projectID) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            preview
                .ignoresSafeArea()

            if camera.settings.showGrid { GridOverlay().ignoresSafeArea() }

            if let focusPoint {
                FocusIndicator(point: focusPoint)
                    .id(focusToken)
                    .transition(.opacity)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 16)

            switch camera.status {
            case .denied(let reason):
                unavailableOverlay(reason, showSettingsButton: true)
            case .failed(let reason):
                unavailableOverlay(reason, showSettingsButton: false)
            default:
                EmptyView()
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            camera.onFinishedRecording = handleFinishedRecording
            camera.requestPermissionsAndStart()
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showSettings) {
            CaptureSettingsSheet(camera: camera)
        }
        .sheet(isPresented: $showManualControls) {
            ManualControlsSheet(camera: camera)
                .presentationDetents([.height(340)])
        }
        .alert("Attenzione", isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: camera.message) { _, new in
            if let new { errorMessage = new; camera.message = nil }
        }
        .videoImporter(target: target, showPhotos: $showPhotoImport, showFiles: $showFileImport) { imported in
            if imported > 0 { dismiss() }
        }
    }

    // MARK: Anteprima e gesti

    private var preview: some View {
        GeometryReader { geo in
            CameraPreview(controller: camera)
                .contentShape(Rectangle())
                .onTapGesture { (location: CGPoint) in
                    camera.focusAndExpose(atPreviewPoint: location)
                    focusPoint = location
                    focusToken += 1
                    let token = focusToken
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if token == focusToken { withAnimation { focusPoint = nil } }
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            camera.setZoom(pinchStartZoom * value.magnification, animated: false)
                        }
                        .onEnded { _ in pinchStartZoom = camera.zoom }
                )
                .onAppear { pinchStartZoom = camera.zoom }
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Barra superiore

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                Button {
                    if camera.isRecording { camera.stopRecording() }
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.3 : 1)

                Spacer()

                VStack(spacing: 1) {
                    Text(project?.name ?? "—")
                        .techFont(8)
                        .foregroundStyle(Ink.accent)
                    Text(sketch?.title ?? "—")
                        .font(.system(size: 14, weight: .bold))
                        .fontWidth(.condensed)
                        .lineLimit(1)
                    Text("Ciak \(sketch?.nextTake ?? 1)")
                        .techFont(8)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.3 : 1)
            }

            if camera.isRecording {
                recordingBadge
            } else {
                formatChips
            }

            if camera.isInterrupted {
                Label("Fotocamera interrotta dal sistema", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.orange.opacity(0.85), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var recordingBadge: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Ink.live)
                .frame(width: 9, height: 9)
                .shadow(color: Ink.live, radius: 6)
                .opacity(camera.recordedDuration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.2)
            Text(Formatters.timecode(camera.recordedDuration))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.live.opacity(0.5), lineWidth: 1))
    }

    private var formatChips: some View {
        HStack(spacing: 5) {
            camChip(camera.settings.resolutionLabel, tint: .white)
            camChip("\(Int(camera.settings.fps.rounded())) fps", tint: .white)
            camChip(camera.appliedCodec, tint: .white)
            if camera.settings.color != .sdr { camChip(camera.settings.color.label, tint: Ink.accent) }
            camChip(camera.appliedStabilization,
                    tint: camera.appliedStabilization == "Off" ? Color.white.opacity(0.4) : Ink.good)
        }
    }

    private func camChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .techFont(9, weight: .bold)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }

    // MARK: Barra inferiore

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if !camera.isRecording && camera.zoomStops.count > 1 {
                zoomStops
            }

            HStack {
                leftAccessory
                Spacer()
                recordButton
                Spacer()
                rightAccessory
            }
        }
        .padding(.bottom, 18)
    }

    private var zoomStops: some View {
        HStack(spacing: 6) {
            ForEach(camera.zoomStops, id: \.self) { stop in
                let selected = abs(camera.zoom - stop) < 0.06
                Button {
                    camera.setZoom(stop)
                    pinchStartZoom = stop
                } label: {
                    Text(zoomLabel(stop))
                        .font(.system(size: selected ? 12 : 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? Ink.bg : .white)
                        .frame(width: selected ? 44 : 34, height: selected ? 44 : 34)
                        .background(selected ? Color.white : Color.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(selected ? 0 : 0.15), lineWidth: 1))
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: camera.zoom)
    }

    private func zoomLabel(_ value: CGFloat) -> String {
        value < 1 ? String(format: "%.1f×", value) : "\(Int(value.rounded()))×"
    }

    private var leftAccessory: some View {
        VStack(spacing: 14) {
            if camera.hasTorch {
                circleButton(camera.torchOn ? "bolt.fill" : "bolt.slash",
                             active: camera.torchOn) { camera.toggleTorch() }
            }
            circleButton("dial.medium", active: camera.isFocusLocked || camera.isExposureLocked) {
                showManualControls = true
            }
        }
        .frame(width: 60)
    }

    private var rightAccessory: some View {
        VStack(spacing: 14) {
            circleButton("arrow.triangle.2.circlepath.camera") { camera.switchCamera() }
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.3 : 1)
            if let count = sketch?.clips.count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.3)))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 60)
    }

    private func circleButton(_ systemName: String, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 46, height: 46)
                .background(active ? Ink.gold : Color.black.opacity(0.5), in: Circle())
                .foregroundStyle(active ? Ink.bg : .white)
                .overlay(Circle().strokeBorder(.white.opacity(active ? 0 : 0.14), lineWidth: 1))
        }
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(Ink.live.opacity(camera.isRecording ? 0.6 : 0), lineWidth: 3)
                    .frame(width: 92, height: 92)
                    .blur(radius: 6)
                RoundedRectangle(cornerRadius: camera.isRecording ? 7 : 33, style: .continuous)
                    .fill(Ink.live)
                    .frame(width: camera.isRecording ? 32 : 66,
                           height: camera.isRecording ? 32 : 66)
                    .shadow(color: Ink.live.opacity(0.5), radius: 12)
            }
        }
        .disabled(savingClip)
        .animation(.snappy(duration: 0.2), value: camera.isRecording)
        .sensoryFeedback(.impact(weight: .heavy), trigger: camera.isRecording)
    }

    // MARK: Azioni

    private func toggleRecording() {
        if camera.isRecording {
            camera.stopRecording()
        } else {
            guard LibraryStore.availableBytes > 500_000_000 else {
                errorMessage = "Spazio quasi esaurito sul dispositivo. Libera spazio prima di registrare."
                return
            }
            camera.startRecording(to: store.newRecordingURL())
        }
    }

    private func handleFinishedRecording(url: URL, metadata: CaptureMetadata, error: Error?) {
        if let error {
            errorMessage = "Registrazione non riuscita: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: url)
            return
        }
        savingClip = true
        Task {
            await store.addClip(fileURL: url, to: target, metadata: metadata)
            savingClip = false
        }
    }

    /// Mostrata quando la fotocamera non è utilizzabile: permesso negato
    /// oppure hardware assente (è il caso del Simulatore).
    private func unavailableOverlay(_ reason: String, showSettingsButton: Bool) -> some View {
        VStack(spacing: 18) {
            Image(systemName: showSettingsButton ? "camera.metering.unknown" : "iphone.gen3.slash")
                .font(.system(size: 42, weight: .light))

            Text(showSettingsButton ? "Accesso alla fotocamera" : "Fotocamera non disponibile")
                .displayFont(24)

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(spacing: 10) {
                if showSettingsButton {
                    Button("Apri Impostazioni") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                } else {
                    Button {
                        showPhotoImport = true
                    } label: {
                        Label("Importa da Foto", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(AccentButtonStyle())

                    Button {
                        showFileImport = true
                    } label: {
                        Label("Importa da File", systemImage: "folder")
                    }
                    .buttonStyle(OutlineButtonStyle())
                }

                Button("Chiudi") { dismiss() }
                    .padding(.top, 4)
            }
            .frame(maxWidth: 320)
        }
        .padding(32)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .ignoresSafeArea()
    }
}
