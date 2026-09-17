import AppKit
import CoreText

/// ABC Areal Superfamily Variable — bundled variable font with a continuous
/// MONO axis (0 = proportional, 50 = semi-mono, 100 = mono), a weight axis,
/// a slant axis, and a DRKM darkmode axis.
///
/// The TTF is gitignored (Dinamo EULA forbids public repositories); it must be
/// present at build time under `Markfops/Fonts/`. When the file is absent the
/// helpers fall back to the system fonts Markfops used before.
enum ArealFont {
    /// Tracking applied on top of MONO 100% so full-mono text sits tighter.
    /// Tuned by eye in the Areal prototype (2026-09-17).
    static let monoTracking: CGFloat = -0.20

    // Axis identifiers: four-character tags read as big-endian integers.
    private static let monoAxisID: Int = 0x4D4F4E4F   // 'MONO'
    private static let wghtAxisID: Int = 0x77676874   // 'wght'
    private static let slntAxisID: Int = 0x736C6E74   // 'slnt'

    private static let resourceName = "ABCArealSuperfamilyVariable"
    private static var postScriptName: String?
    private static var didAttemptRegistration = false

    /// Registers the bundled font with CoreText (process-scoped) and caches its
    /// PostScript name. Safe to call repeatedly.
    @discardableResult
    static func register() -> Bool {
        if didAttemptRegistration { return postScriptName != nil }
        didAttemptRegistration = true
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "ttf") else {
            return false
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        guard let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        else { return false }
        postScriptName = name
        return true
    }

    static var isAvailable: Bool { register() }

    /// Whether the font came from this helper (as opposed to a system fallback).
    /// Tests use this instead of the .monoSpace trait, which Areal does not
    /// report even at MONO 100.
    static func isAreal(_ font: NSFont) -> Bool {
        font.familyName?.hasPrefix("ABC Areal") == true
    }

    /// Builds an Areal font at the given size. `mono` ranges 0...100;
    /// `italic` maps onto the slant axis (-12°).
    static func font(
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool = false,
        mono: CGFloat
    ) -> NSFont? {
        guard register(), let psName = postScriptName else { return nil }
        let ctWeight = ctWeightValue(for: weight)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: psName as CFString,
            kCTFontVariationAttribute: [
                monoAxisID: mono,
                wghtAxisID: ctWeight,
                slntAxisID: italic ? -12.0 : 0.0,
            ] as CFDictionary,
        ] as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return ctFont as NSFont
    }

    /// Maps NSFont.Weight onto the wght axis (Areal supports 400...700).
    private static func ctWeightValue(for weight: NSFont.Weight) -> CGFloat {
        // NSFont.Weight regular ≈ 0.0 maps to 400; medium ≈ 0.23 → 500; bold ≈ 0.4 → 700.
        switch weight {
        case .ultraLight, .thin, .light: return 400
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold, .heavy, .black: return 700
        default: return 400
        }
    }
}
