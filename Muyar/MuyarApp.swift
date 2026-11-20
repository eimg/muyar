import SwiftUI

@main
struct MuyarApp: App {
    @StateObject private var store: MarketStore
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        AppAppearance.applyPreview(arguments: arguments)
        _appearance = AppStorage(wrappedValue: AppAppearance.system.rawValue, AppAppearance.preferenceKey)
        if let index = arguments.firstIndex(of: "-chart-style"), arguments.indices.contains(index + 1),
           let style = PriceChartStyle(rawValue: arguments[index + 1]) {
            UserDefaults.standard.set(style.rawValue, forKey: "price-chart-style")
        }
        if arguments.contains("-ui-testing") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("muyar-ui-\(UUID().uuidString).json")
            _store = StateObject(wrappedValue: MarketStore(service: PreviewMarketService(), cacheURL: url))
            return
        }
        #endif
        _store = StateObject(wrappedValue: MarketStore())
    }

    var body: some Scene {
        WindowGroup {
            WatchlistView()
                .environmentObject(store)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .tint(MuyarTheme.accent)
        }
    }
}
