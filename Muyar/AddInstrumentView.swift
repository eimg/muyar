import SwiftUI

struct AddInstrumentView: View {
    @EnvironmentObject private var store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var crypto = false
    @State private var results: [Instrument] = []
    @State private var loading = false
    @State private var error: String?
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var displayed: [Instrument] {
        if term.isEmpty { return Instrument.suggestions.filter { ($0.provider == .binance) == crypto } }
        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Market", selection: $crypto) {
                    Text("Stocks & commodities").tag(false)
                    Text("Crypto pairs").tag(true)
                }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 14)
                if term.isEmpty {
                    HStack {
                        Text("SUGGESTED").font(.system(size: 9, weight: .semibold)).tracking(1.8)
                        Spacer()
                    }
                    .foregroundStyle(MuyarTheme.muted).padding(.horizontal, 24).padding(.top, 15).padding(.bottom, 8)
                }
                if loading {
                    ProgressView("Searching markets…").padding(24).frame(maxWidth: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Search unavailable", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) }
                } else if displayed.isEmpty {
                    ContentUnavailableView.search(text: term)
                } else {
                    List(displayed) { instrument in
                        let added = store.instruments.contains { $0.id == instrument.id }
                        Button {
                            store.add(instrument)
                        } label: {
                            HStack(spacing: 13) {
                                AssetIcon(instrument: instrument)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(instrument.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                    Text("\(instrument.displaySymbol) · \(instrument.exchange)")
                                        .font(.system(size: 11)).foregroundStyle(MuyarTheme.muted)
                                }
                                Spacer()
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 22)).foregroundStyle(added ? MuyarTheme.muted : MuyarTheme.accent)
                            }
                            .padding(.vertical, 5)
                        }
                        .disabled(added)
                        .accessibilityLabel("\(added ? "Added" : "Add") \(instrument.name), \(instrument.displaySymbol)")
                        .accessibilityIdentifier("add-result-\(instrument.symbol)")
                        .listRowBackground(MuyarTheme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
                Spacer(minLength: 0)
            }
            .background(MuyarTheme.background)
            .navigationTitle("Add instrument").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: crypto ? "BTC, SOL/USDT…" : "Apple, TSLA, SPY…")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(crypto)-\(term)") {
                results = []
                error = nil
                loading = false
                guard !term.isEmpty else { return }
                loading = true
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let fetched = try await store.service.search(term, crypto: crypto)
                    guard !Task.isCancelled else { return }
                    results = fetched
                    loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = MarketStore.message(error)
                    loading = false
                }
            }
        }
    }
}
