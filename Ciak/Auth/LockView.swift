import SwiftUI

/// Schermata di sblocco: biometria se disponibile, altrimenti password.
struct LockView: View {
    @Environment(AuthManager.self) private var auth
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "141414"), Color(hex: "232323")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color(hex: "FF6B35"))
                    Text("Ciak").font(.largeTitle.weight(.bold))
                    Text("Il tuo archivio video, sotto chiave.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }

                if auth.biometricsAvailable && auth.biometricsEnabled {
                    Button {
                        Task { await auth.unlockWithBiometrics() }
                    } label: {
                        Label("Sblocca con \(auth.biometryLabel)", systemImage: auth.biometryIcon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "FF6B35"))
                }

                VStack(spacing: 12) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .focused($passwordFocused)
                        .submitLabel(.go)
                        .onSubmit(attemptUnlock)

                    Button("Entra", action: attemptUnlock)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(password.isEmpty)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()
                Text("Nessun dato lascia questo iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .task {
            // Al primo apparire propone subito Face ID: un tocco in meno.
            await auth.unlockWithBiometrics()
        }
    }

    private func attemptUnlock() {
        if auth.unlock(withPassword: password) {
            password = ""
        } else {
            password = ""
            passwordFocused = true
        }
    }
}

/// Primo avvio: creazione della password dell'app.
struct PasswordSetupView: View {
    @Environment(AuthManager.self) private var auth
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "141414"), Color(hex: "232323")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color(hex: "FF6B35"))
                        Text("Proteggi il tuo archivio").font(.title2.weight(.bold))
                        Text("Scegli una password di almeno 6 caratteri. Servirà per aprire l'app; se il tuo iPhone ha \(auth.biometricsAvailable ? auth.biometryLabel : "la biometria"), potrai usare anche quello.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)

                    VStack(spacing: 12) {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Ripeti la password", text: $confirmation)
                            .textContentType(.newPassword)
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        error = auth.createPassword(password, confirmation: confirmation)
                    } label: {
                        Text("Continua")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "FF6B35"))
                    .disabled(password.count < 6 || confirmation.isEmpty)

                    Text("La password non viene salvata: sul portachiavi finisce solo la sua impronta crittografica. Se la dimentichi, l'unico modo per rientrare è reinstallare l'app, perdendo i video.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .foregroundStyle(.white)
            }
        }
    }
}

/// Copre i contenuti nel selettore app.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}
