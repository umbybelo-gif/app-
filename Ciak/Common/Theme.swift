import SwiftUI

// MARK: - Palette

/// Tutta l'app vive al buio: nero profondo, superfici stratificate,
/// un solo accento caldo e l'oro del ciak per le riprese buone.
enum Ink {
    static let bg = Color(hex: "08080A")
    static let bgLift = Color(hex: "0F0F13")
    static let surface = Color(hex: "16161C")
    static let surfaceHigh = Color(hex: "212129")
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.16)

    static let text = Color(hex: "F4F2EF")
    static let dim = Color(hex: "8B8B96")
    static let faint = Color(hex: "5A5A64")

    static let accent = Color(hex: "FF5A1F")
    static let accentDeep = Color(hex: "D92E00")
    static let gold = Color(hex: "F5C518")
    static let live = Color(hex: "FF2D4B")
    static let good = Color(hex: "35D07F")

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

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

// MARK: - Tipografia

extension View {
    /// Titoli da locandina: stretti, pesanti, serrati.
    func displayFont(_ size: CGFloat, weight: Font.Weight = .black) -> some View {
        self.font(.system(size: size, weight: weight))
            .fontWidth(.condensed)
            .tracking(-0.4)
    }

    /// Etichette tecniche: monospaziate, maiuscole, spaziate.
    func techFont(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> some View {
        self.font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(0.9)
            .textCase(.uppercase)
    }
}

// MARK: - Superfici

extension View {
    func card(radius: CGFloat = 20, fill: Color = Ink.surface, stroke: Color = Ink.stroke) -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    func screen() -> some View {
        self.background(Ink.bg.ignoresSafeArea())
    }

    /// Barra di navigazione scura e senza separatore chiaro.
    func darkNavigationBar() -> some View {
        self.toolbarBackground(Ink.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Nasconde lo sfondo grigio dei Form di sistema.
    func darkForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Ink.bg.ignoresSafeArea())
            .tint(Ink.accent)
    }
}

// MARK: - Componenti

/// Etichetta tecnica dentro un contorno sottile: risoluzione, fps, codec, durate.
struct TechChip: View {
    let text: String
    var icon: String?
    var tint: Color = Ink.dim
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text).techFont(9.5, weight: .bold)
        }
        .foregroundStyle(filled ? Ink.bg : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            if filled {
                Capsule().fill(tint)
            } else {
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// Intestazione di sezione: filetto + titolo tecnico + eventuale conteggio.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Ink.accent)
                .frame(width: 14, height: 2)
            Text(title).techFont(10, weight: .bold).foregroundStyle(Ink.dim)
            Spacer()
            if let trailing {
                Text(trailing).techFont(10, weight: .bold).foregroundStyle(Ink.faint)
            }
        }
    }
}

/// Pulsante pieno con gradiente d'accento.
struct AccentButtonStyle: ButtonStyle {
    var tint: LinearGradient = Ink.accentGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Ink.accent.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Pulsante secondario: solo contorno.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Ink.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Ink.strokeStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Pulsante tondo da barra strumenti.
struct GlyphButton: View {
    let icon: String
    var active: Bool = false
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(active ? Ink.bg : Ink.text)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(active ? Ink.gold : Ink.surface)
                }
                .overlay(Circle().strokeBorder(active ? .clear : Ink.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Bagliore colorato di sfondo, usato dietro le intestazioni.
struct GlowBackdrop: View {
    var color: Color
    var height: CGFloat = 260

    var body: some View {
        LinearGradient(colors: [color.opacity(0.35), color.opacity(0.06), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .blur(radius: 30)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Velo scuro dal basso: tiene leggibile il testo sopra le miniature.
struct ScrimGradient: View {
    var body: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                       startPoint: .center, endPoint: .bottom)
    }
}

struct ProgressOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Ink.accent)
                Text(text).techFont(10).foregroundStyle(Ink.dim)
            }
            .padding(28)
            .card(radius: 18, fill: Ink.surfaceHigh)
        }
    }
}
