import AppKit
import CoreText
import SwiftUI

enum MiniPlayerStyle: String, CaseIterable, Identifiable {
    static let storageKey = "appearance.mini-player-style"
    case smoke, blueMetal
    var id: String { rawValue }
    var title: String { self == .smoke ? "スモーク" : "ブルーメタル" }
    var bodyColors: [Color] {
        self == .smoke
            ? [Color(red: 0.30, green: 0.37, blue: 0.42), Color(red: 0.04, green: 0.09, blue: 0.13), Color(red: 0.16, green: 0.25, blue: 0.31)]
            : [Color(red: 0.40, green: 0.77, blue: 0.94), Color(red: 0.02, green: 0.31, blue: 0.50), Color(red: 0.01, green: 0.17, blue: 0.31), Color(red: 0.18, green: 0.46, blue: 0.64)]
    }
}

struct MiniPlayerStylePicker: View {
    @AppStorage(MiniPlayerStyle.storageKey) private var style = MiniPlayerStyle.smoke.rawValue
    var body: some View {
        Picker("小型プレイヤーの外観", selection: $style) {
            ForEach(MiniPlayerStyle.allCases) { Text($0.title).tag($0.rawValue) }
        }
    }
}

@MainActor
enum MiniPlayerAssets {
    static let display = Color(red: 0.73, green: 0.91, blue: 0.96)
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
    static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
    static let silver: NSImage? = url("StickSilver", "jpg").flatMap(NSImage.init(contentsOf:))
    static let fontRegistered: Bool = {
        guard let url = url("DotGothic16-Regular", "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func font(_ size: CGFloat) -> Font {
        _ = fontRegistered
        return .custom("DotGothic16-Regular", fixedSize: size)
    }
}

struct MiniPlayerMetal: View {
    let style: MiniPlayerStyle
    var body: some View {
        ZStack {
            Color(white: 0.65)
            if let image = MiniPlayerAssets.silver {
                Image(nsImage: image).resizable().scaledToFill()
            }
            LinearGradient(colors: [.white.opacity(0.55), .black.opacity(0.18), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if style == .smoke { Color(red: 0.05, green: 0.13, blue: 0.19).opacity(0.65) }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct MiniPlayerShell: View {
    let style: MiniPlayerStyle
    let reducedEffects: Bool
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: reducedEffects ? [style.bodyColors[1]] : style.bodyColors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), Color(white: 0.45), Color(white: 0.15), Color(white: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 5)
            }
            .overlay { Capsule().inset(by: 5).strokeBorder(.black.opacity(0.7), lineWidth: 1) }
            .shadow(color: .black.opacity(0.5), radius: reducedEffects ? 0 : 1, y: 3)
            .shadow(color: .black.opacity(0.3), radius: reducedEffects ? 0 : 8, y: 9)
    }
}

struct MiniPlayerCeramicButtonStyle: ButtonStyle {
    var diameter: CGFloat = 30
    var active = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter > 32 ? 14 : 12, weight: .semibold))
            .foregroundStyle(active ? MiniPlayerAssets.display : Color(white: 0.86))
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(RadialGradient(colors: [Color(white: configuration.isPressed ? 0.15 : 0.4), Color(red: 0.10, green: 0.15, blue: 0.19), Color(white: 0.04)], center: .topLeading, startRadius: 0, endRadius: diameter))
                    .overlay { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .black, .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.6), radius: configuration.isPressed ? 0 : 1, y: configuration.isPressed ? 0 : 2)
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(enabled ? 1 : 0.4)
    }
}
