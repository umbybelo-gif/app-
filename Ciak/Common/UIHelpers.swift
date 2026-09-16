import Foundation
import SwiftUI

/// Stato vuoto: icona spenta, titolo stretto, una sola azione forte.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Ink.faint)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Ink.surface))
                .overlay(Circle().strokeBorder(Ink.stroke, lineWidth: 1))

            Text(title).displayFont(22).foregroundStyle(Ink.text)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AccentButtonStyle())
                    .frame(maxWidth: 220)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

/// Campo di testo dentro un alert, per creare o rinominare.
struct NameAlertModifier: ViewModifier {
    let title: String
    let placeholder: String
    @Binding var isPresented: Bool
    @Binding var text: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField(placeholder, text: $text)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { onConfirm() }
        }
    }
}

extension View {
    func nameAlert(_ title: String, placeholder: String,
                   isPresented: Binding<Bool>, text: Binding<String>,
                   onConfirm: @escaping () -> Void) -> some View {
        modifier(NameAlertModifier(title: title, placeholder: placeholder,
                                   isPresented: isPresented, text: text, onConfirm: onConfirm))
    }

    /// Alert di solo testo pilotato da una stringa opzionale.
    func messageAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil },
                                          set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// Campo di ricerca scuro, al posto di `.searchable`.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.faint)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Ink.faint))
                .font(.system(size: 14))
                .foregroundStyle(Ink.text)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.faint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card(radius: 12, fill: Ink.surface)
    }
}

/// Wrapper per presentare il foglio di condivisione con `sheet(item:)`.
struct ExportPayload: Identifiable {
    let url: URL
    var id: String { url.path }
    init(_ url: URL) { self.url = url }
}

extension RecordingTarget: Identifiable {
    var id: String { "\(projectID.uuidString)-\(sketchID.uuidString)" }
}
