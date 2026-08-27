import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@Observable
final class AuthManager {

    enum Phase: Equatable {
        case needsSetup      // primo avvio: bisogna scegliere una password
        case locked
        case unlocked
    }

    private(set) var phase: Phase = .needsSetup
    var isUnlocked: Bool { phase == .unlocked }

    /// Copre lo schermo quando l'app va in multitasking, per non mostrare i video nell'anteprima.
    var isObscured = false
    var errorMessage: String?
    private(set) var failedAttempts = 0

    /// Tipo di biometria disponibile sul dispositivo (Face ID / Touch ID).
    private(set) var biometryType: LABiometryType = .none

    private(set) var biometricsEnabled: Bool

    /// Dopo quanti secondi in background l'app si richiude a chiave. 0 = subito.
    private(set) var autoLockSeconds: Int

    func setBiometricsEnabled(_ enabled: Bool) {
        biometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.biometricsEnabled)
    }

    func setAutoLockSeconds(_ seconds: Int) {
        autoLockSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: Keys.autoLock)
    }

    private var backgroundedAt: Date?
    private static let credentialAccount = "app-password"

    private enum Keys {
        static let biometricsEnabled = "auth.biometricsEnabled"
        static let autoLock = "auth.autoLockSeconds"
    }

    init() {
        let defaults = UserDefaults.standard
        biometricsEnabled = defaults.object(forKey: Keys.biometricsEnabled) as? Bool ?? true
        autoLockSeconds = defaults.object(forKey: Keys.autoLock) as? Int ?? 60

        refreshBiometryType()
        phase = hasCredential ? .locked : .needsSetup
    }

    // MARK: Stato credenziale

    var hasCredential: Bool { storedCredential != nil }

    private var storedCredential: StoredCredential? {
        guard let data = Keychain.get(account: Self.credentialAccount) else { return nil }
        return try? JSONDecoder().decode(StoredCredential.self, from: data)
    }

    private func store(_ credential: StoredCredential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        Keychain.set(data, account: Self.credentialAccount)
    }

    private func refreshBiometryType() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometryType = context.biometryType
        } else {
            biometryType = .none
        }
    }

    var biometryLabel: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometria"
        }
    }

    var biometryIcon: String {
        switch biometryType {
        case .faceID, .opticID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }

    var biometricsAvailable: Bool { biometryType != .none }

    // MARK: Configurazione iniziale

    /// Restituisce nil se ok, altrimenti il motivo del rifiuto.
    func createPassword(_ password: String, confirmation: String) -> String? {
        guard password.count >= 6 else { return "La password deve avere almeno 6 caratteri." }
        guard password == confirmation else { return "Le due password non coincidono." }
        store(PasswordHasher.makeCredential(password: password))
        failedAttempts = 0
        errorMessage = nil
        phase = .unlocked
        return nil
    }

    func changePassword(current: String, new: String, confirmation: String) -> String? {
        guard let credential = storedCredential else { return "Nessuna password impostata." }
        guard PasswordHasher.verify(password: current, against: credential) else {
            return "Password attuale errata."
        }
        guard new.count >= 6 else { return "La nuova password deve avere almeno 6 caratteri." }
        guard new == confirmation else { return "Le due password non coincidono." }
        store(PasswordHasher.makeCredential(password: new))
        return nil
    }

    // MARK: Sblocco

    @discardableResult
    func unlock(withPassword password: String) -> Bool {
        guard let credential = storedCredential else { return false }
        if PasswordHasher.verify(password: password, against: credential) {
            failedAttempts = 0
            errorMessage = nil
            phase = .unlocked
            return true
        }
        failedAttempts += 1
        errorMessage = "Password errata. Tentativi falliti: \(failedAttempts)."
        return false
    }

    @MainActor
    func unlockWithBiometrics() async {
        guard biometricsEnabled, biometricsAvailable else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Usa la password"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "Sblocca il tuo archivio video")
            if ok {
                failedAttempts = 0
                errorMessage = nil
                phase = .unlocked
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                break // l'utente userà la password: nessun messaggio d'errore
            case .biometryLockout:
                errorMessage = "\(biometryLabel) bloccato. Inserisci la password."
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lock() {
        guard hasCredential else { return }
        phase = .locked
        errorMessage = nil
    }

    // MARK: Blocco automatico

    func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            isObscured = false
            if let since = backgroundedAt, isUnlocked {
                let elapsed = Date().timeIntervalSince(since)
                if elapsed >= Double(autoLockSeconds) { lock() }
            }
            backgroundedAt = nil
        case .inactive:
            isObscured = isUnlocked
        case .background:
            isObscured = isUnlocked
            if backgroundedAt == nil { backgroundedAt = Date() }
        @unknown default:
            break
        }
    }

    /// Non si blocca mentre è in corso una registrazione: si perderebbe la ripresa.
    func suspendAutoLock(_ suspended: Bool) {
        if suspended { backgroundedAt = nil }
    }
}
