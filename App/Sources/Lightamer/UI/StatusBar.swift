import SwiftUI

/// 22pt status bar along the bottom of the editor area (UI-SPEC "Status Bar").
///
/// Leading: the D-26 background toast (02-06 — drift / unknown module /
/// cache freed / sidecar write failed; non-blocking, auto-clears). Trailing:
/// Ready / Decoding…. Numeric readouts (FPS, decode time — later phases) use
/// the monospaced design per UI-SPEC Typography.
internal struct StatusBar: View {

    var isDecoding: Bool

    /// D-26 background notice (nil = nothing shown). Leading slot so it
    /// never fights the trailing Ready/Decoding readout.
    var toast: String?

    var body: some View {
        HStack(spacing: 8) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(LightamerColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
                    .accessibilityIdentifier("status_toast")
            }
            Spacer()
            Text(isDecoding ? "status_decoding" : "status_ready")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(
                    isDecoding ? LightamerColors.textSecondary : LightamerColors.textTertiary
                )
                .padding(.horizontal, 12)
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(LightamerColors.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LightamerColors.border)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isDecoding)
        .animation(.easeInOut(duration: 0.2), value: toast)
    }
}
