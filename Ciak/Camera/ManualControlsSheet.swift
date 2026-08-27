import SwiftUI

/// Controlli manuali: fuoco, esposizione, ISO, otturatore, temperatura colore.
struct ManualControlsSheet: View {
    let camera: CameraController
    @Environment(\.dismiss) private var dismiss

    @State private var manualExposure = false
    @State private var shutter: Double = 60
    @State private var isoValue: Float = 100
    @State private var manualWhiteBalance = false
    @State private var temperature: Float = 5200

    var body: some View {
        NavigationStack {
            Form {
                Section("Messa a fuoco") {
                    Toggle("Fuoco manuale", isOn: Binding(
                        get: { camera.isFocusLocked },
                        set: { camera.setFocusLocked($0) }
                    ))
                    if camera.isFocusLocked {
                        HStack {
                            Image(systemName: "camera.macro")
                            Slider(value: Binding(get: { camera.lensPosition },
                                                  set: { camera.setLensPosition($0) }),
                                   in: 0...1)
                            Image(systemName: "mountain.2")
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Esposizione") {
                    Toggle("Esposizione manuale", isOn: $manualExposure)

                    if manualExposure {
                        VStack(alignment: .leading) {
                            Text("Otturatore 1/\(Int(shutter))").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $shutter, in: 24...2000, step: 1)
                        }
                        VStack(alignment: .leading) {
                            Text("ISO \(Int(isoValue))").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $isoValue, in: camera.minISO...max(camera.maxISO, camera.minISO + 1))
                        }
                    } else {
                        VStack(alignment: .leading) {
                            Text(String(format: "Compensazione %+.1f EV", camera.exposureBias))
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { camera.exposureBias },
                                                  set: { camera.setExposureBias($0) }),
                                   in: camera.minExposureBias...max(camera.maxExposureBias,
                                                                    camera.minExposureBias + 0.1))
                        }
                    }
                }

                Section {
                    Toggle("Bilanciamento del bianco manuale", isOn: $manualWhiteBalance)
                    if manualWhiteBalance {
                        VStack(alignment: .leading) {
                            Text("\(Int(temperature)) K").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $temperature, in: 2500...8000, step: 50)
                        }
                    }
                } footer: {
                    Text("Bloccare esposizione e bianco evita gli sbalzi di luminosità e colore fra un ciak e l'altro.")
                }
            }
            .navigationTitle("Controlli manuali")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutto automatico") {
                        manualExposure = false
                        manualWhiteBalance = false
                        camera.setAutoExposure()
                        camera.setWhiteBalance(temperature: nil)
                        camera.setFocusLocked(false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .onAppear {
                shutter = camera.shutterDenominator
                isoValue = camera.iso
                manualExposure = camera.isExposureLocked
                manualWhiteBalance = camera.isWhiteBalanceLocked
                temperature = camera.colorTemperature
            }
            .onChange(of: manualExposure) { _, on in
                if on { camera.setManualExposure(shutterDenominator: shutter, iso: isoValue) }
                else { camera.setAutoExposure() }
            }
            .onChange(of: shutter) { _, value in
                if manualExposure { camera.setManualExposure(shutterDenominator: value, iso: isoValue) }
            }
            .onChange(of: isoValue) { _, value in
                if manualExposure { camera.setManualExposure(shutterDenominator: shutter, iso: value) }
            }
            .onChange(of: manualWhiteBalance) { _, on in
                camera.setWhiteBalance(temperature: on ? temperature : nil)
            }
            .onChange(of: temperature) { _, value in
                if manualWhiteBalance { camera.setWhiteBalance(temperature: value) }
            }
        }
    }
}
