// swift-tools-version: 6.0
import PackageDescription

// Run the same core tests without requiring a simulator or Xcode's UI test service.
let package = Package(
    name: "MuyarCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MuyarCore", targets: ["MuyarCore"])],
    targets: [
        .target(name: "MuyarCore", path: "Muyar", exclude: ["Assets.xcassets", "MuyarApp.swift", "WatchlistView.swift", "InstrumentDetailView.swift", "AddInstrumentView.swift", "Theme.swift", "P2POffersView.swift"], sources: ["Models.swift", "MarketService.swift", "MarketStore.swift", "P2POffers.swift", "ChartHistory.swift", "PreviewMarketService.swift", "AppAppearance.swift"]),
        .testTarget(name: "MuyarCoreTests", dependencies: ["MuyarCore"], path: "MuyarTests")
    ],
    swiftLanguageModes: [.v5]
)
