import SwiftUI
import FastSharedCore

/// File-type glyph — SwiftUI port of `FileGlyph()` from `design/screens.jsx`.
///
/// A small rounded tile (amber 10% fill, 20% stroke) holding a line-drawn
/// icon for the file kind. Shapes are hand-built with SF Symbols as the
/// pragmatic stand-in; visual parity with the JSX is preserved through
/// the tile's chrome (fill, stroke, amber tint).
struct FileGlyph: View {
    enum Kind: String {
        case photo, film, doc, audio, pdf, generic
    }

    let kind: Kind
    var size: CGFloat = 34

    init(kind: Kind, size: CGFloat = 34) {
        self.kind = kind
        self.size = size
    }

    /// Convenience initializer from a MIME content type string.
    init(contentType: String, size: CGFloat = 34) {
        self.size = size
        if contentType.hasPrefix("image/") { self.kind = .photo }
        else if contentType.hasPrefix("video/") { self.kind = .film }
        else if contentType.hasPrefix("audio/") { self.kind = .audio }
        else if contentType == "application/pdf" { self.kind = .pdf }
        else if contentType.hasPrefix("text/") || contentType.hasPrefix("application/") { self.kind = .doc }
        else { self.kind = .generic }
    }

    var body: some View {
        // Brand accent unified on violet.
        let accent = BrandPalette.accent

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(accent.hot.opacity(0.10))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(accent.hot.opacity(0.20), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.50, weight: .regular))
                    .foregroundStyle(accent.hot)
            )
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch kind {
        case .photo:   return "photo"
        case .film:    return "film"
        case .doc:     return "doc"
        case .audio:   return "waveform"
        case .pdf:     return "doc.richtext"
        case .generic: return "doc"
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        FileGlyph(kind: .photo)
        FileGlyph(kind: .film)
        FileGlyph(kind: .doc)
        FileGlyph(kind: .audio)
        FileGlyph(kind: .pdf)
    }
    .padding(32)
    .background(BrandPalette.ground)
}
