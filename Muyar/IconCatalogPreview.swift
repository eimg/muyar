#if DEBUG
import SwiftUI

// Explicit launch preview only; never part of Release or the user's watchlist.
struct IconCatalogPreview: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 20) {
                tile("Gold") { AssetIcon(instrument: Instrument.defaults[0]) }
                tile("DXY") {
                    AssetIcon(instrument: .init(symbol: "DX-Y.NYB", name: "DXY", category: .stocks, provider: .yahoo, currency: "", exchange: "", unit: nil))
                }
                ForEach(InstrumentBrand.allCases) { brand in
                    tile(brand.rawValue) {
                        Image(brand.assetName)
                            .renderingMode(brand.tint == .original ? .original : .template)
                            .resizable().scaledToFit().frame(width: 24, height: 24)
                            .foregroundStyle(MuyarTheme.color(for: brand))
                            .frame(width: 43, height: 43)
                            .background(MuyarTheme.color(for: brand).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }.padding(20)
        }
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-preview-icons-bottom") ? .bottom : .top)
        .background(MuyarTheme.background)
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) {
            content()
            Text(title).font(.system(size: 9)).lineLimit(2).frame(height: 24, alignment: .top)
        }.frame(maxWidth: .infinity)
    }
}
#endif
