import SwiftUI

/// Segmented "Translate | IPA" button.
///
/// - Left segment  → executes translation with the current IPA setting.
/// - Right segment → toggles IPA (phonetic transcription) mode.
///   The waveform icon turns yellow when IPA is active.
struct TranslateButton: View {
    @AppStorage(requestIpaKey) private var ipa: Bool = false
    let onTranslate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Left — execute translation
            Button(action: onTranslate) {
                Text(NSLocalizedString(
                    "label.translate",
                    value: "Translate",
                    comment: "Translate button"
                ))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            // MARK: Divider
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1, height: 18)

            // MARK: Right — IPA toggle
            Button {
                ipa.toggle()
            } label: {
                Text("/a/")
                    .font(.system(.footnote, design: .monospaced).bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(ipa ? Color.white.opacity(0.25) : Color.clear)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ipa ? Color.white : Color.white.opacity(0.55))
            .help(NSLocalizedString(
                "label.ipa.toggle",
                value: "Toggle phonetic transcription (IPA)",
                comment: "IPA toggle button tooltip"
            ))
        }
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    HStack {
        TranslateButton { }
    }
    .padding()
}


