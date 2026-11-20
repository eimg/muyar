import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var store: MarketStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: AssetCategory?
    @State private var adding = false
    @State private var editing = false
    @State private var showingP2POffers = false
    @State private var navigationPath: [Instrument] = []

    init() {
        #if DEBUG
        // A live-data visual smoke check can open a screen without the UI test daemon.
        let arguments = ProcessInfo.processInfo.arguments
        _showingP2POffers = State(initialValue: arguments.contains("-open-p2p"))
        if let index = arguments.firstIndex(of: "-open-instrument"), arguments.indices.contains(index + 1),
           let instrument = Instrument.defaults.first(where: { $0.symbol == arguments[index + 1] }) {
            _navigationPath = State(initialValue: [instrument])
        }
        #endif
    }

    private var visible: [Instrument] { store.instruments.filter { category == nil || $0.category == category } }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 27) {
                    header
                    Button { showingP2POffers = true } label: { P2PCard() }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("p2p-open-offers")
                        .accessibilityHint("View the top five offers to buy USDT and the top five to sell USDT")
                    watchlistHeader
                    filters
                    if let message = store.persistenceError {
                        statusNotice(message, icon: "exclamationmark.triangle")
                    }
                    if !store.errors.isEmpty {
                        statusNotice("Refresh incomplete", icon: "wifi.exclamationmark")
                    }
                    if visible.isEmpty {
                        ContentUnavailableView {
                            Label("No instruments", systemImage: "plus.circle")
                        } actions: {
                            Button("Add instrument") { adding = true }.buttonStyle(.bordered)
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visible) { instrument in
                                NavigationLink(value: instrument) {
                                    MarketRow(instrument: instrument, snapshot: store.snapshots[instrument.id], error: store.errors[instrument.id])
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("instrument-\(instrument.symbol)")
                                if instrument.id != visible.last?.id { Divider().overlay(MuyarTheme.line).padding(.leading, 72) }
                            }
                        }
                        .background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(MuyarTheme.line))
                    }
                    Button { adding = true } label: {
                        Label("Add to watchlist", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MuyarTheme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(MuyarTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(MuyarTheme.accent.opacity(0.17), style: .init(lineWidth: 1, dash: [5, 4])))
                    }
                    .accessibilityIdentifier("add-instrument")
                    AppearanceControl()
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 25)
            }
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-show-appearance-controls") ? .bottom : .top)
            #endif
            .background(MuyarTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .navigationDestination(for: Instrument.self) { InstrumentDetailView(instrument: $0, service: store.service) }
            .sheet(isPresented: $adding) { AddInstrumentView() }
            .sheet(isPresented: $editing) { EditWatchlistView() }
            .sheet(isPresented: $showingP2POffers) { P2POffersView(service: store.service) }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await store.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    guard !Task.isCancelled else { return }
                    await store.refresh()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 23, weight: .medium)).foregroundStyle(MuyarTheme.accent)
                    Text("Muyar").font(.system(size: 38, weight: .regular, design: .serif)).tracking(-1.4)
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Group {
                        if store.isRefreshing { ProgressView().tint(MuyarTheme.accent) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .medium)) }
                    }
                    .frame(width: 44, height: 44)
                    .background(MuyarTheme.card, in: Circle())
                    .overlay(Circle().strokeBorder(MuyarTheme.line))
                }
                .disabled(store.isRefreshing).accessibilityLabel("Refresh prices").accessibilityIdentifier("refresh-prices")
            }
        }
    }

    private var watchlistHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Watchlist").font(.system(size: 23, weight: .regular, design: .serif)).tracking(-0.3)
            Text(String(store.instruments.count)).font(.system(size: 11, weight: .medium)).foregroundStyle(MuyarTheme.muted)
                .padding(.horizontal, 8).padding(.vertical, 4).background(MuyarTheme.card, in: Capsule())
            Spacer()
            Button { editing = true } label: { Text("Edit").font(.system(size: 13, weight: .medium)).padding(.vertical, 8) }
                .accessibilityIdentifier("edit-watchlist")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filter("All", value: nil)
                ForEach(AssetCategory.allCases) { filter($0.rawValue, value: $0) }
            }
        }
        .padding(.top, -15).padding(.bottom, -11)
    }

    private func filter(_ title: String, value: AssetCategory?) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { category = value } } label: {
            Text(title).font(.system(size: 12, weight: category == value ? .semibold : .regular))
                .padding(.horizontal, 15).padding(.vertical, 9)
                .foregroundStyle(category == value ? MuyarTheme.background : MuyarTheme.muted)
                .background(category == value ? MuyarTheme.accent : MuyarTheme.card, in: Capsule())
        }
        .accessibilityAddTraits(category == value ? .isSelected : [])
        .accessibilityIdentifier("filter-\(title)")
    }

    private func statusNotice(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon).font(.system(size: 12)).foregroundStyle(MuyarTheme.gold)
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuyarTheme.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct MarketRow: View {
    let instrument: Instrument
    let snapshot: MarketSnapshot?
    let error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            AssetIcon(instrument: instrument)
            VStack(alignment: .leading, spacing: 5) {
                Text(instrument.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                HStack(spacing: 5) {
                    Text(instrument.displaySymbol).lineLimit(1)
                    if error != nil || snapshot?.isStale() == true { Text("· Saved").foregroundStyle(MuyarTheme.gold) }
                    else if let snapshot, !snapshot.marketOpen { Text("· Closed") }
                }
                .font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Sparkline(points: snapshot?.points ?? [], positive: (snapshot?.changePercent ?? 0) >= 0)
                    .frame(width: 47, height: 29)
            }
            VStack(alignment: .trailing, spacing: 5) {
                if let snapshot {
                    Text(PriceFormat.price(snapshot.price, currency: snapshot.currency))
                        .font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    ChangeLabel(value: snapshot.changePercent)
                    Text(snapshot.changeLabel).font(.system(size: 8)).foregroundStyle(MuyarTheme.muted)
                } else {
                    Text("—").font(.system(size: 18)).foregroundStyle(MuyarTheme.muted)
                    Text(error == nil ? "Loading" : "Unavailable").font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
                }
            }
            .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.horizontal, 15).padding(.vertical, 19)
        .accessibilityElement(children: .combine)
    }
}

struct P2PCard: View {
    @EnvironmentObject private var store: MarketStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("USDT / MMK").font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.5)
                }
                Spacer()
                Text("BINANCE P2P").font(.system(size: 8, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(MuyarTheme.gold).padding(.horizontal, 9).padding(.vertical, 7)
                    .background(MuyarTheme.gold.opacity(0.08), in: Capsule())
            }
            HStack(alignment: .top, spacing: 20) {
                side(title: "Buy USDT", quote: store.p2pQuotes.buy, error: store.errors["p2p-buy"])
                Rectangle().fill(MuyarTheme.gold.opacity(0.18)).frame(width: 1, height: 58)
                side(title: "Sell USDT", quote: store.p2pQuotes.sell, error: store.errors["p2p-sell"])
            }
            HStack {
                Text("Top 5 offers")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(MuyarTheme.gold)
        }
        .padding(20)
        .background(LinearGradient(colors: [MuyarTheme.p2pTint, MuyarTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(MuyarTheme.gold.opacity(0.22)))
        .accessibilityIdentifier("p2p-card")
    }

    private func side(title: String, quote: P2PSide?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary.opacity(0.8))
            Text(quote.map { PriceFormat.number($0.price, currency: "MMK") } ?? "—")
                .font(.system(size: 31, weight: .medium, design: .rounded)).tracking(-1).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                .accessibilityIdentifier(title == "Buy USDT" ? "p2p-buy-price" : "p2p-sell-price")
            if let quote {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let saved = error != nil || context.date.timeIntervalSince(quote.fetchedAt) > 600
                    HStack(spacing: 3) {
                        if saved { Image(systemName: "clock.arrow.circlepath") }
                        Text(saved ? "Saved ·" : "Updated")
                        Text(quote.fetchedAt, style: .time)
                    }
                    .font(.system(size: 9)).foregroundStyle(saved ? MuyarTheme.gold : MuyarTheme.muted)
                }
            } else {
                Text(error == nil ? "Loading…" : "Unavailable")
                    .font(.system(size: 9)).foregroundStyle(MuyarTheme.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct EditWatchlistView: View {
    @EnvironmentObject private var store: MarketStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.instruments) { instrument in
                        HStack(spacing: 12) {
                            AssetIcon(instrument: instrument)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(instrument.name).font(.subheadline)
                                Text(instrument.displaySymbol).font(.caption).foregroundStyle(MuyarTheme.muted)
                            }
                        }
                        .listRowBackground(MuyarTheme.card)
                    }
                    .onDelete(perform: store.remove)
                    .onMove(perform: store.move)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden).background(MuyarTheme.background)
            .navigationTitle("Edit watchlist").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
