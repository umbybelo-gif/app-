import Foundation
import SwiftUI

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    static func project(_ index: Int) -> Color { Color(hex: ProjectPalette.hex(index)) }
}

/// Stato vuoto riutilizzabile.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Campo di testo dentro un alert per creare o rinominare.
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
}

/// Etichetta compatta con icona, usata nelle intestazioni.
struct StatLabel: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
