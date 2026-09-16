import AVFoundation
import SwiftUI

/// Impostazioni di ripresa. Ogni scelta viene verificata contro ciò che
/// il sensore supporta davvero, e il risultato applicato è sempre mostrato.
struct CaptureSettingsSheet: View {
    let camera: CameraController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Risoluzione") {
                    Picker("Risoluzione", selection: resolutionBinding) {
                        ForEach(camera.availableResolutions) { resolution in
                            Text(resolution.label).tag(resolution.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Frame al secondo", selection: fpsBinding) {
                        ForEach(camera.availableFrameRates, id: \.self) { rate in
                            Text("\(Int(rate)) fps").tag(rate)
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("25 fps per la TV europea, 30 fps per i social, 50/60 fps per rallentare in montaggio.")
                }

                Section {
                    Picker("Codec", selection: codecBinding) {
                        ForEach(CodecPreference.allCases) { codec in
                            Text(codec.label).tag(codec)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Codec")
                } footer: {
                    Text(camera.settings.codec.detail +
                         (camera.settings.codec == .proRes && !camera.supportsProRes
                          ? "\n\nQuesto iPhone non registra in ProRes: verrà usato HEVC." : ""))
                }

                Section {
                    Picker("Colore", selection: colorBinding) {
                        ForEach(availableColorModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Profilo colore")
                } footer: {
                    Text(camera.settings.color.detail)
                }

                Section {
                    Picker("Stabilizzazione", selection: stabilizationBinding) {
                        ForEach(StabilizationPreference.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Stabilizzazione")
                } footer: {
                    Text("\(camera.settings.stabilization.detail)\n\nApplicata ora: \(camera.appliedStabilization).")
                }

                Section("Audio") {
                    Toggle("Audio stereo", isOn: plainBinding(\.stereoAudio))
                    Toggle("Riduzione rumore del vento", isOn: plainBinding(\.windNoiseRemoval))
                }

                Section("Inquadratura") {
                    Toggle("Griglia dei terzi", isOn: plainBinding(\.showGrid))
                    Toggle("Specchia la fotocamera frontale", isOn: plainBinding(\.mirrorFrontCamera))
                    Toggle("Tieni acceso lo schermo", isOn: plainBinding(\.keepScreenAwake))
                }

                Section("Questo iPhone") {
                    capabilityRow("ProRes", camera.supportsProRes)
                    capabilityRow("HDR 10 bit", camera.supportsHDR)
                    capabilityRow("Apple Log", camera.supportsAppleLog)
                    LabeledContent("Obiettivo", value: camera.activeLensName)
                    LabeledContent("Spazio libero", value: Formatters.bytes(LibraryStore.availableBytes))
                }
            }
            .darkForm()
            .navigationTitle("Ripresa")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .tint(Ink.accent)
    }

    private var availableColorModes: [ColorPreference] {
        ColorPreference.allCases.filter { mode in
            switch mode {
            case .sdr: return true
            case .hdr: return camera.supportsHDR
            case .appleLog: return camera.supportsAppleLog
            }
        }
    }

    private func capabilityRow(_ title: String, _ available: Bool) -> some View {
        LabeledContent(title) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }

    // MARK: Binding che riapplicano il formato

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { "\(camera.settings.width)x\(camera.settings.height)" },
            set: { newValue in
                let parts = newValue.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                camera.updateSettings(reapply: false) {
                    $0.width = parts[0]
                    $0.height = parts[1]
                }
                // Se il frame rate scelto non esiste a questa risoluzione, si ripiega
                // sul valore più alto sensato invece di lasciare un'impostazione impossibile.
                if !camera.availableFrameRates.contains(camera.settings.fps) {
                    let fallback = camera.availableFrameRates.last(where: { $0 <= 60 })
                        ?? camera.availableFrameRates.first
                    if let fallback { camera.updateSettings(reapply: false) { $0.fps = fallback } }
                }
                camera.applyFormat()
            }
        )
    }

    private var fpsBinding: Binding<Double> {
        Binding(get: { camera.settings.fps },
                set: { value in camera.updateSettings { $0.fps = value } })
    }

    private var codecBinding: Binding<CodecPreference> {
        Binding(get: { camera.settings.codec },
                set: { value in camera.updateSettings { $0.codec = value } })
    }

    private var colorBinding: Binding<ColorPreference> {
        Binding(get: { camera.settings.color },
                set: { value in camera.updateSettings { $0.color = value } })
    }

    private var stabilizationBinding: Binding<StabilizationPreference> {
        Binding(get: { camera.settings.stabilization },
                set: { value in camera.updateSettings { $0.stabilization = value } })
    }

    private func plainBinding(_ keyPath: WritableKeyPath<CaptureSettings, Bool>) -> Binding<Bool> {
        Binding(get: { camera.settings[keyPath: keyPath] },
                set: { value in camera.updateSettings(reapply: false) { $0[keyPath: keyPath] = value } })
    }
}
