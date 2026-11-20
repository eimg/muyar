import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "appearance"
    var id: String { rawValue }

    #if DEBUG
    // UserDefaults reads command-line flags before saved preferences. The preview
    // flag must have a different name so a later button tap can change the value.
    static let previewArgument = "-preview-appearance"
    static func applyPreview(arguments: [String], defaults: UserDefaults = .standard) {
        guard let index = arguments.firstIndex(of: previewArgument), arguments.indices.contains(index + 1),
              let value = Self(rawValue: arguments[index + 1]) else { return }
        defaults.set(value.rawValue, forKey: preferenceKey)
    }
    #endif
}
