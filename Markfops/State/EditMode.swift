import Foundation

enum EditMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }
}
