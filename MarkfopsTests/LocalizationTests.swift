import Foundation
import XCTest
@testable import Markfops

final class LocalizationTests: XCTestCase {
    private let locales = ["en", "ko", "ja", "zh-Hans"]

    private let uiLiteralPattern = #"\b(?:Text|Button|Label|Menu|CommandMenu|Section|Picker|TextField|Stepper|WindowGroup)\s*\(\s*\"((?:\\.|[^\"\\])*)\""#
    private let helpLiteralPattern = #"\.help\(\s*\"((?:\\.|[^\"\\])*)\""#
    private let nsLiteralPattern = #"NSLocalizedString\(\s*\"((?:\\.|[^\"\\])*)\""#
    private let conditionalButtonPattern = #"Button\([^\n]*?\?\s*\"((?:\\.|[^\"\\])*)\"\s*:\s*\"((?:\\.|[^\"\\])*)\""#

    func testLocaleCatalogsHaveMatchingKeysAndPlaceholders() throws {
        let catalogs = try Dictionary(uniqueKeysWithValues: locales.map { locale in
            (locale, try loadCatalog(locale: locale))
        })
        let expectedKeys = try sourceLocalizationKeys()

        for locale in locales {
            let catalog = try XCTUnwrap(catalogs[locale])
            XCTAssertEqual(
                Set(catalog.keys),
                expectedKeys,
                "\(locale) must contain exactly the keys used by localized UI source"
            )

            for (key, value) in catalog {
                XCTAssertEqual(
                    placeholders(in: key),
                    placeholders(in: value),
                    "\(locale) changes the format placeholders for \(key)"
                )
            }
        }
    }

    private func sourceLocalizationKeys() throws -> Set<String> {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markfops")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ),
            "Unable to enumerate Swift source files"
        )
        let swiftFiles = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty, "No Swift source files found for localization scan")

        var keys = Set<String>()
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for pattern in [uiLiteralPattern, helpLiteralPattern, nsLiteralPattern] {
                keys.formUnion(try matches(in: source, pattern: pattern).map(decodeSwiftLiteral))
            }
            for match in try matchGroups(in: source, pattern: conditionalButtonPattern) {
                keys.formUnion(match.map(decodeSwiftLiteral))
            }
        }

        // SwiftUI represents this Int interpolation as a printf-style localized key.
        keys.remove("\\(Int(fontSize))pt")
        keys.insert("%lldpt")
        keys.remove("")

        // AppKit receives these labels directly, so they are not discoverable from SwiftUI APIs.
        keys.formUnion([
            "Close",
            "Close Other Tabs",
            "Close Tabs to the Left",
            "Close Tabs to the Right",
            "Move Tab to New Window",
            "View",
        ])
        return keys
    }

    private func matches(in source: String, pattern: String) throws -> [String] {
        try matchGroups(in: source, pattern: pattern).compactMap(\.first)
    }

    private func matchGroups(in source: String, pattern: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern)
        let sourceRange = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: sourceRange).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: source) else { return nil }
                return String(source[range])
            }
        }
    }

    private func decodeSwiftLiteral(_ value: String) -> String {
        var decoded = value
        decoded = decoded.replacingOccurrences(of: "\\u{2026}", with: "…")
        decoded = decoded.replacingOccurrences(of: "\\\"", with: "\"")
        decoded = decoded.replacingOccurrences(of: "\\\\", with: "\\")
        decoded = decoded.replacingOccurrences(of: "\\n", with: "\n")
        decoded = decoded.replacingOccurrences(of: "\\r", with: "\r")
        decoded = decoded.replacingOccurrences(of: "\\t", with: "\t")
        return decoded
    }

    private func loadCatalog(locale: String) throws -> [String: String] {
        let appBundle = Bundle(identifier: "com.markfops.Markfops")
            ?? Bundle(for: DocumentStore.self)
        let url = try XCTUnwrap(
            appBundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: "\(locale).lproj"
            ),
            "Missing \(locale) Localizable.strings resource"
        )
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%[-+0-9.# ]*[a-zA-Z@]")
        let range = NSRange(value.startIndex..., in: value)
        return pattern.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
}
