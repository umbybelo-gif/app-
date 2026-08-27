import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showChangePassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var cleanupResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sicurezza") {
                    if auth.biometricsAvailable {
                        Toggle(isOn: Binding(get: { auth.biometricsEnabled },
                                             set: { auth.setBiometricsEnabled($0) })) {
                            Label("Sblocca con \(auth.biometryLabel)", systemImage: auth.biometryIcon)
                        }
                    } else {
                        Label("Biometria non disponibile su questo dispositivo",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Blocco automatico", selection: Binding(get: { auth.autoLockSeconds },
                                                                   set: { auth.setAutoLockSeconds($0) })) {
                        Text("Subito").tag(0)
                        Text("Dopo 1 minuto").tag(60)
                        Text("Dopo 5 minuti").tag(300)
                        Text("Dopo 15 minuti").tag(900)
                    }

                    Button("Cambia password") { showChangePassword = true }
                    Button("Blocca adesso") {
                        auth.lock()
                        dismiss()
                    }
                }

                Section {
                    LabeledContent("Progetti", value: "\(store.projects.count)")
                    LabeledContent("Clip", value: "\(store.totalClips)")
                    LabeledContent("Spazio usato", value: Formatters.bytes(store.usedBytes))
                    LabeledContent("Spazio libero", value: Formatters.bytes(LibraryStore.availableBytes))
                } header: {
                    Text("Archivio")
                } footer: {
                    Text("I video restano solo su questo iPhone, dentro l'app. Puoi prelevarli anche via cavo da Finder › File condivisi.")
                }

                Section {
                    Button("Verifica e ripulisci l'archivio") {
                        let result = store.reconcile()
                        cleanupResult = "Voci rimosse: \(result.removedEntries) · File orfani eliminati: \(result.removedFiles)"
                    }
                    if let cleanupResult {
                        Text(cleanupResult).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Rimuove i riferimenti a video non più presenti e cancella i file rimasti senza scheda.")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
            .alert("Cambia password", isPresented: $showChangePassword) {
                SecureField("Password attuale", text: $currentPassword)
                SecureField("Nuova password", text: $newPassword)
                SecureField("Conferma nuova password", text: $confirmPassword)
                Button("Annulla", role: .cancel) { clearPasswordFields() }
                Button("Salva") {
                    message = auth.changePassword(current: currentPassword,
                                                  new: newPassword,
                                                  confirmation: confirmPassword)
                        ?? "Password aggiornata."
                    clearPasswordFields()
                }
            }
            .alert("Ciak", isPresented: Binding(get: { message != nil },
                                                set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func clearPasswordFields() {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
    }
}
