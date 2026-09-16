import Foundation
import SwiftUI

/// Schermata di sblocco: biometria se disponibile, altrimenti password.
struct LockView: View {
    @Environment(AuthManager.self) private var auth
    @State private var password = ""
    @State private var shake = 0
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            RadialGradient(colors: [Ink.accent.opacity(0.28), .clear],
                           center: .init(x: 0.5, y: 0.22), startRadius: 10, endRadius: 320)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 6) {
                    ClapperMark(size: 56)
                    Text("Ciak").displayFont(52).foregroundStyle(Ink.text)
                    Text("archivio riservato").techFont(10).foregroundStyle(Ink.faint)
                }

                Spacer()

                VStack(spacing: 12) {
                    if auth.biometricsAvailable && auth.biometricsEnabled {
                        Button {
                            Task { await auth.unlockWithBiometrics() }
                        } label: {
                            Label("Sblocca con \(auth.biometryLabel)", systemImage: auth.biometryIcon)
                        }
                        .buttonStyle(AccentButtonStyle())
                    }

                    HStack(spacing: 10) {
                        SecureField("", text: $password,
                                    prompt: Text("Password").foregroundColor(Ink.faint))
                            .textContentType(.password)
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.text)
                            .focused($passwordFocused)
                            .submitLabel(.go)
                            .onSubmit(attemptUnlock)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .card(radius: 14)

                        Button(action: attemptUnlock) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(password.isEmpty ? Ink.faint : .white)
                                .frame(width: 50, height: 50)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(password.isEmpty ? AnyShapeStyle(Ink.surface) : AnyShapeStyle(Ink.accentGradient))
                                }
                        }
                        .disabled(password.isEmpty)
                    }
                    .offset(x: shakeOffset)

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.live)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                Text("Nessun dato lascia questo iPhone")
                    .techFont(9)
                    .foregroundStyle(Ink.faint.opacity(0.7))
                    .padding(.bottom, 18)
            }
        }
        .animation(.snappy, value: auth.errorMessage)
        .task { await auth.unlockWithBiometrics() }
    }

    /// Piccola oscillazione dopo una password sbagliata.
    private var shakeOffset: CGFloat {
        shake == 0 ? 0 : sin(CGFloat(shake) * .pi * 4) * 8
    }

    private func attemptUnlock() {
        if auth.unlock(withPassword: password) {
            password = ""
        } else {
            password = ""
            passwordFocused = true
            withAnimation(.easeInOut(duration: 0.4)) { shake += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { shake = 0 }
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
            Ink.bg.ignoresSafeArea()
            RadialGradient(colors: [Ink.accent.opacity(0.25), .clear],
                           center: .init(x: 0.5, y: 0.15), startRadius: 10, endRadius: 340)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        ClapperMark(size: 52)
                        Text("Proteggi l'archivio").displayFont(32).foregroundStyle(Ink.text)
                        Text("Scegli una password di almeno 6 caratteri. Aprirà l'app; se il tuo iPhone ha \(auth.biometricsAvailable ? auth.biometryLabel : "la biometria"), potrai usare anche quello.")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.dim)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .padding(.top, 70)

                    VStack(spacing: 10) {
                        SecureField("", text: $password,
                                    prompt: Text("Password").foregroundColor(Ink.faint))
                            .textContentType(.newPassword)
                            .padding(14)
                            .card(radius: 14)
                        SecureField("", text: $confirmation,
                                    prompt: Text("Ripeti la password").foregroundColor(Ink.faint))
                            .textContentType(.newPassword)
                            .padding(14)
                            .card(radius: 14)
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.text)

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.live)
                            .multilineTextAlignment(.center)
                    }

                    Button("Continua") {
                        error = auth.createPassword(password, confirmation: confirmation)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(password.count < 6 || confirmation.isEmpty)
                    .opacity(password.count < 6 || confirmation.isEmpty ? 0.45 : 1)

                    Text("La password non viene salvata: sul portachiavi finisce solo la sua impronta crittografica. Se la dimentichi, l'unico modo per rientrare è reinstallare l'app, perdendo i video.")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.faint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Il simbolo dell'app: una claquette stilizzata, disegnata a codice.
struct ClapperMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Ink.surfaceHigh)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Ink.strokeStrong, lineWidth: 1)
                )

            // Le strisce diagonali della tavoletta.
            HStack(spacing: size * 0.09) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Ink.accent)
                        .frame(width: size * 0.09)
                }
            }
            .rotationEffect(.degrees(18))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
        .frame(width: size, height: size)
        .shadow(color: Ink.accent.opacity(0.35), radius: 18, y: 8)
    }
}

/// Copre i contenuti nel selettore app.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ClapperMark(size: 54)
        }
    }
}
