import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

final class AppearanceTests: XCTestCase {
    func testPreviewLaunchDoesNotLockSubsequentModeChanges() throws {
        let name = "muyar-appearance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // Reproduce UserDefaults' automatic command-line argument domain.
        let argumentKey = String(AppAppearance.previewArgument.dropFirst())
        defaults.setVolatileDomain([argumentKey: "light"], forName: UserDefaults.argumentDomain)
        AppAppearance.applyPreview(arguments: ["Muyar", AppAppearance.previewArgument, "light"], defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppAppearance.preferenceKey), "light")
        for choice in [AppAppearance.dark, .light, .system] {
            defaults.set(choice.rawValue, forKey: AppAppearance.preferenceKey)
            XCTAssertEqual(defaults.string(forKey: AppAppearance.preferenceKey), choice.rawValue)
        }
    }

    func testNormalLaunchKeepsSavedAppearance() throws {
        let name = "muyar-appearance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("dark", forKey: AppAppearance.preferenceKey)
        let relaunched = try XCTUnwrap(UserDefaults(suiteName: name))
        AppAppearance.applyPreview(arguments: ["Muyar"], defaults: relaunched)
        XCTAssertEqual(relaunched.string(forKey: AppAppearance.preferenceKey), "dark")
    }

    func testInvalidPreviewDoesNotReplaceSavedChoice() throws {
        let name = "muyar-appearance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("dark", forKey: AppAppearance.preferenceKey)
        AppAppearance.applyPreview(arguments: ["Muyar", AppAppearance.previewArgument, "invalid"], defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppAppearance.preferenceKey), "dark")
    }
}
