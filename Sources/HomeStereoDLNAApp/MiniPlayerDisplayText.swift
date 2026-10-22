import SwiftUI

/// A single fixed-width display window. The text pauses, moves left, then resets without animating backwards.
struct MiniPlayerDisplayText: View {
    let text: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var windowWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var singleLine: String { text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    private var font: Font { MiniPlayerAssets.font(fontSize) }
    private var request: Request {
        Request(text: singleLine, textWidth: textWidth, windowWidth: windowWidth,
                active: scenePhase == .active && !reduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            Text(singleLine)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { measure in
                        Color.clear.preference(key: MiniPlayerDisplayWidthKey.self, value: measure.size.width)
                    }
                }
                .offset(x: offset)
                .frame(width: proxy.size.width, height: lineHeight, alignment: .leading)
                .onChange(of: proxy.size.width, initial: true) { _, width in windowWidth = width }
        }
        .frame(height: lineHeight)
        .clipped()
        .onPreferenceChange(MiniPlayerDisplayWidthKey.self) { textWidth = $0 }
        .task(id: request) { await scroll() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(singleLine)
    }

    @MainActor private func scroll() async {
        reset()
        let distance = max(0, textWidth - windowWidth)
        guard request.active, windowWidth > 0, distance > 1 else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1.8))
                try Task.checkCancellation()
                let duration = max(1, Double(distance) / 16)
                withAnimation(.linear(duration: duration)) { offset = -distance }
                try await Task.sleep(for: .seconds(duration + 1))
                try Task.checkCancellation()
                reset()
            } catch { return }
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
    }

    private struct Request: Hashable {
        let text: String
        let textWidth: CGFloat
        let windowWidth: CGFloat
        let active: Bool
    }
}

private struct MiniPlayerDisplayWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
