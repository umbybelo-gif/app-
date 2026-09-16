import CommonCrypto
import Foundation
import Security

/// La password non viene mai salvata: si conserva solo un hash PBKDF2-SHA256 con sale casuale.
struct StoredCredential: Codable {
    var salt: Data
    var hash: Data
    var iterations: Int
}

enum PasswordHasher {
    static let defaultIterations = 210_000

    static func makeSalt(length: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            for i in 0..<length { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    static func hash(password: String, salt: Data, iterations: Int) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordLength = password.utf8.count

        let status = salt.withUnsafeBytes { (saltBuffer: UnsafeRawBufferPointer) -> Int32 in
            guard let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, passwordLength,
                saltBase, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { return Data() }
        return Data(derived)
    }

    static func makeCredential(password: String) -> StoredCredential {
        let salt = makeSalt()
        let iterations = defaultIterations
        return StoredCredential(salt: salt,
                                hash: hash(password: password, salt: salt, iterations: iterations),
                                iterations: iterations)
    }

    /// Confronto a tempo costante, per non far trapelare informazioni dai tempi di risposta.
    static func verify(password: String, against credential: StoredCredential) -> Bool {
        let candidate = hash(password: password, salt: credential.salt, iterations: credential.iterations)
        guard candidate.count == credential.hash.count, !candidate.isEmpty else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, credential.hash) { difference |= a ^ b }
        return difference == 0
    }
}
