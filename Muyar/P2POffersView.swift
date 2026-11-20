import SwiftUI

struct P2POffersView: View {
    @StateObject private var offers: P2POffersStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(service: any MarketServing) {
        _offers = StateObject(wrappedValue: P2POffersStore(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text("Binance P2P · MMK / USDT")
                        Spacer()
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { Text("Sample data") }
                        #endif
                    }
                    .font(.caption).foregroundStyle(MuyarTheme.muted)
                    ForEach(P2PTradeSide.allCases) { side in
                        section(side)
                    }
                }
                .padding(22)
            }
            .background(MuyarTheme.background)
            .navigationTitle("USDT / MMK offers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await offers.refresh() }
                    } label: {
                        if offers.isRefreshing { ProgressView().tint(MuyarTheme.accent) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(offers.isRefreshing)
                    .accessibilityLabel("Refresh P2P offers")
                    .accessibilityIdentifier("refresh-p2p-offers")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await offers.refresh() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await offers.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    guard !Task.isCancelled else { return }
                    await offers.refresh()
                }
            }
        }
        .accessibilityIdentifier("p2p-offers-screen")
    }

    private func section(_ side: P2PTradeSide) -> some View {
        let book = offers.books[side]
        let error = offers.errors[side]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(side.title).font(.system(size: 23, weight: .medium, design: .rounded))
                }
                Spacer(minLength: 8)
                if let book {
                    Text("\(book.offers.count) / 5")
                        .font(.caption.monospacedDigit()).foregroundStyle(MuyarTheme.muted)
                }
            }
            Text(side.sortLabel).font(.caption.weight(.medium)).foregroundStyle(side == .buy ? MuyarTheme.gold : MuyarTheme.accent)
            if error != nil {
                Label("Refresh failed", systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(MuyarTheme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let book {
                fetchedLabel(book, failed: error != nil)
                if book.offers.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("No offers returned", systemImage: "tray")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("p2p-empty-\(side.rawValue)")
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(book.offers.enumerated()), id: \.element.id) { index, offer in
                            offerRow(offer, side: side, rank: index + 1)
                        }
                    }
                }
            } else if offers.isRefreshing {
                ProgressView("Loading…")
                    .font(.caption).tint(MuyarTheme.accent)
                    .frame(maxWidth: .infinity).padding(24)
            } else {
                Button("Try again") { Task { await offers.refresh() } }.buttonStyle(.bordered)
            }
        }
        .accessibilityIdentifier("p2p-section-\(side.rawValue)")
    }

    private func fetchedLabel(_ book: P2POfferBook, failed: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let saved = failed || context.date.timeIntervalSince(book.fetchedAt) > 120
            Label("\(saved ? "Saved" : "Updated") · \(book.fetchedAt.formatted(date: .abbreviated, time: .shortened))",
                  systemImage: saved ? "clock.arrow.circlepath" : "clock")
                .font(.system(size: 10)).foregroundStyle(saved ? MuyarTheme.gold : MuyarTheme.muted)
        }
    }

    private func offerRow(_ offer: P2POffer, side: P2PTradeSide, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(rank)).font(.caption.monospacedDigit()).foregroundStyle(MuyarTheme.muted)
                    .frame(width: 23, height: 27)
                    .background(MuyarTheme.background, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    Text(offer.merchant).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text(side.counterparty).font(.caption2).foregroundStyle(MuyarTheme.muted)
                }
                Spacer(minLength: 3)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(PriceFormat.number(offer.price, currency: "MMK"))
                        .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(side == .buy ? MuyarTheme.gold : MuyarTheme.accent)
                    Text("MMK / USDT").font(.system(size: 9)).foregroundStyle(MuyarTheme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Limits: \(limit(offer.minMMK)) – \(limit(offer.maxMMK)) MMK")
                    .font(.caption).foregroundStyle(.primary.opacity(0.85))
                Text(offer.paymentMethods.isEmpty ? "Payments: —" : offer.paymentMethods.joined(separator: " · "))
                    .font(.caption).foregroundStyle(MuyarTheme.muted)
                HStack(alignment: .top, spacing: 12) {
                    if let rate = offer.completionRate {
                        Text("\((rate * 100).formatted(.number.precision(.fractionLength(1))))% completed")
                    }
                    if let count = offer.monthlyOrders { Text("\(count) orders / 30d") }
                }
                .font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
                if let available = offer.availableUSDT {
                    Text("Available: \(PriceFormat.number(available, currency: "USDT")) USDT")
                        .font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MuyarTheme.line))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("p2p-offer-\(side.rawValue)-\(rank)")
    }

    private func limit(_ value: Double?) -> String {
        value.map { PriceFormat.number($0, currency: "MMK") } ?? "—"
    }
}
