import SwiftUI

enum HomeStereoTheme: String, CaseIterable, Identifiable {
    static let storageKey = "appearance.theme"

    case system
    case simpleDark = "simple-dark"
    case livingAurora = "living-aurora"
    case pulseNeon = "pulse-neon"
    case blueCosmos = "blue-cosmos"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "システム"
        case .simpleDark: "シンプルダーク"
        case .livingAurora: "Living Aurora"
        case .pulseNeon: "Pulse Neon"
        case .blueCosmos: "Blue Cosmos"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Macの外観とアクセントカラーを使用"
        case .simpleDark: "装飾を抑え、音楽とアートワークを主役に"
        case .livingAurora: "紫の拡散光とシアンの反射"
        case .pulseNeon: "黒い光学面と細い信号線"
        case .blueCosmos: "紺の奥行きと静かな星空"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .simpleDark: "moon.fill"
        case .livingAurora: "sparkles"
        case .pulseNeon: "waveform.path"
        case .blueCosmos: "moon.stars"
        }
    }

    var preferredColorScheme: ColorScheme? {
        self == .system ? nil : .dark
    }

    var accent: Color {
        switch self {
        case .system, .simpleDark: .accentColor
        case .livingAurora: Color(red: 0.333, green: 0.867, blue: 0.878) // #55DDE0
        case .pulseNeon: Color(red: 0.271, green: 0.941, blue: 0.937) // #45F0EF
        case .blueCosmos: Color(red: 0.412, green: 0.655, blue: 1.000) // #69A7FF
        }
    }

    fileprivate var base: Color {
        switch self {
        case .system: Color(nsColor: .windowBackgroundColor)
        case .simpleDark: .black
        case .livingAurora: Color(red: 0.020, green: 0.027, blue: 0.047) // #05070C
        case .pulseNeon: Color(red: 0.012, green: 0.024, blue: 0.027) // #030607
        case .blueCosmos: Color(red: 0.008, green: 0.024, blue: 0.067) // #020611
        }
    }

    fileprivate var surface: Color {
        switch self {
        case .system: Color(nsColor: .controlBackgroundColor)
        case .simpleDark: Color(red: 0.110, green: 0.110, blue: 0.118)
        case .livingAurora: Color(red: 0.051, green: 0.071, blue: 0.125) // #0D1220
        case .pulseNeon: Color(red: 0.027, green: 0.063, blue: 0.086) // rgb(7 16 22)
        case .blueCosmos: Color(red: 0.027, green: 0.059, blue: 0.133) // rgb(7 15 34)
        }
    }

    fileprivate var light: Color {
        switch self {
        case .system, .simpleDark: .clear
        case .livingAurora: Color(red: 0.545, green: 0.424, blue: 1.000) // #8B6CFF
        case .pulseNeon: Color(red: 0.263, green: 0.533, blue: 1.000) // #4388FF
        case .blueCosmos: Color(red: 0.710, green: 0.863, blue: 1.000) // #B5DCFF
        }
    }
}

struct HomeStereoThemeRoot<Content: View>: View {
    let theme: HomeStereoTheme
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            HomeStereoThemeBackground(theme: theme)
            content
        }
        .environment(\.homeStereoTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.preferredColorScheme)
    }
}

private struct HomeStereoThemeBackground: View {
    let theme: HomeStereoTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.base
                if theme != .system && theme != .simpleDark && !reduceTransparency && contrast != .increased {
                    RadialGradient(
                        colors: [theme.light.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.05, y: 0),
                        startRadius: 0,
                        endRadius: min(proxy.size.width * 0.9, proxy.size.height * 0.7)
                    )
                    RadialGradient(
                        colors: [theme.accent.opacity(0.08), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.65
                    )
                    atmosphere(in: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func atmosphere(in size: CGSize) -> some View {
        switch theme {
        case .livingAurora:
            LinearGradient(
                colors: [.clear, theme.light.opacity(0.10), theme.accent.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pulseNeon:
            Canvas { context, _ in
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.58, y: 0))
                path.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.38))
                path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height))
                context.stroke(path, with: .color(theme.accent.opacity(0.22)), lineWidth: 0.8)
            }
        case .blueCosmos:
            Canvas { context, _ in
                let count = min(90, max(24, Int(size.width * size.height / 12_000)))
                for index in 0..<count {
                    let x = CGFloat((index * 73) % 997) / 997 * size.width
                    let y = CGFloat((index * 193 + 47) % 991) / 991 * size.height
                    let diameter = index.isMultiple(of: 17) ? 1.8 : 0.8
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                        with: .color(theme.accent.opacity(index.isMultiple(of: 17) ? 0.65 : 0.24))
                    )
                }
            }
        case .system, .simpleDark:
            EmptyView()
        }
    }
}

struct HomeStereoThemeSettingsView: View {
    @AppStorage(HomeStereoTheme.storageKey) private var storedTheme = HomeStereoTheme.system.rawValue

    private var selection: Binding<HomeStereoTheme> {
        Binding(
            get: { HomeStereoTheme(rawValue: storedTheme) ?? .system },
            set: { storedTheme = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("テーマ") {
                ForEach(HomeStereoTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 440)
    }

    private func themeButton(_ theme: HomeStereoTheme) -> some View {
        Button {
            selection.wrappedValue = theme
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.surface)
                    Image(systemName: theme.symbol)
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 48, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title).font(.headline)
                    Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selection.wrappedValue == theme {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.wrappedValue == theme ? .isSelected : [])
    }
}

private struct HomeStereoThemeKey: EnvironmentKey {
    static let defaultValue = HomeStereoTheme.system
}

extension EnvironmentValues {
    var homeStereoTheme: HomeStereoTheme {
        get { self[HomeStereoThemeKey.self] }
        set { self[HomeStereoThemeKey.self] = newValue }
    }
}
