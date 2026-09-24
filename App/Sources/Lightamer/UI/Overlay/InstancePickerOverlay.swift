import CoreGraphics
import LightamerCore
import SwiftUI

/// Popover-presentation identity (stable across selection changes — the
/// instance set IS the session identity; no re-presentation churn).
extension AIInstanceCatalog: Identifiable {
    public var id: Int {
        instances.reduce(0) { $0 &+ $1 &+ 0x5eed_1234 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// InstancePickerOverlay (Plan 07-3 T1.2) — the layer-A multi-subject
// checkbox floater: one checkbox per detected instance, a live PREVIEW of
// the combined selection (the label-composite plane tinted yellow, the same
// tint the display overlay uses), and the confirm action that bakes the
// subset into the selected layer's mask slot.
//
// The preview recomputes through `AIMaskService.subjectMask(from:selection:)`
// — the CPU label read (cheap, deterministic); NO extra inference happens
// after the single stage-1 detection.
// ─────────────────────────────────────────────────────────────────────────────

internal struct InstancePickerOverlay: View {

    let catalog: AIInstanceCatalog
    /// The confirmed subset → the toolbar's commit path.
    let onConfirm: (AIMaskPlane) -> Void
    let onCancel: () -> Void

    @State private var selection: Set<Int> = []

    private var combinedPlane: AIMaskPlane? {
        try? AIMaskService.subjectMask(
            from: catalog, selection: .subset(selection.isEmpty ? Set(catalog.instances) : selection))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ai_picker_title")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(catalog.instances, id: \.self) { instance in
                        Toggle(isOn: Binding(
                            get: { selection.contains(instance) },
                            set: { checked in
                                if checked { selection.insert(instance) }
                                else { selection.remove(instance) }
                            })) {
                            Text(String(localized: String.LocalizationValue(
                                "ai_picker_subject_n \(instance)")))
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("ai.picker.instance.\(instance)")
                    }
                }

                // The live combined-selection preview (tinted label plane).
                if let plane = combinedPlane {
                    Image(decorative: Self.tintedImage(from: plane), scale: 1)
                        .resizable()
                        .aspectRatio(
                            CGFloat(plane.width) / CGFloat(plane.height), contentMode: .fit)
                        .frame(width: 150)
                        .background(.black.opacity(0.6))
                        .cornerRadius(4)
                        .accessibilityIdentifier("ai.picker.preview")
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "alert_cancel"), action: onCancel)
                    .accessibilityIdentifier("ai.picker.cancel")
                Button(String(localized: "ai_picker_confirm")) {
                    if let plane = combinedPlane {
                        onConfirm(plane)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty && catalog.instances.isEmpty)
                .accessibilityIdentifier("ai.picker.confirm")
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .accessibilityIdentifier("ai.picker")
        .onAppear { selection = Set(catalog.instances) }
    }

    /// The mask plane → an RGBA CGImage (yellow RGB, alpha = the mask
    /// value). CPU-side, plane-sized (the label map is ≤512 — small); the
    /// provider owns the bytes. Degenerate planes render as a 1×1 image.
    static func tintedImage(from plane: AIMaskPlane) -> CGImage {
        var rgba = [UInt8](repeating: 0, count: plane.width * plane.height * 4)
        for i in 0..<(plane.width * plane.height) {
            let v = max(0, min(1, plane.floats[i]))
            rgba[i * 4 + 0] = 255
            rgba[i * 4 + 1] = 230
            rgba[i * 4 + 2] = 0
            rgba[i * 4 + 3] = UInt8((v * 255).rounded())
        }
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: plane.width, height: plane.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: plane.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            // Degenerate fallback: an opaque 1×1 gray pixel (cannot fail).
            let provider = CGDataProvider(data: Data([0]) as CFData)!
            return CGImage(
                width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)!
        }
        return image
    }
}
