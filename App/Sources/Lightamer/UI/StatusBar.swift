import SwiftUI

/// 22pt status bar along the bottom of the editor area (UI-SPEC "Status Bar").
///
/// Phase 1: leading/center empty; trailing shows Ready / Decoding…. Numeric
/// readouts (FPS, decode time — later phases) use the monospaced design per
/// UI-SPEC Typography.
internal struct StatusBar: View {

    var isDecoding: Bool

    var body: some View {
        HStack(spacing: 8) {
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
    }
}
