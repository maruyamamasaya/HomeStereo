import AppKit
import SwiftUI

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat
    var cornerRadius: CGFloat = 7

    private var image: NSImage? {
        data.flatMap(NSImage.init(data:))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.36, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
