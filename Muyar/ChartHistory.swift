import Foundation
import Combine

enum PriceChartStyle: String, CaseIterable, Identifiable {
    case candles = "Candles", line = "Line"
    var id: String { rawValue }
}

struct ChartSample: Identifiable, Equatable, Sendable {
    let date: Date
    let close: Double
    let candle: PriceCandle?
    var id: Date { date }
}

struct HistoryPage: Sendable {
    let samples: [ChartSample]
    let fetchedAt: Date
    let nextBefore: Date?
}

enum ChartHistoryPolicy {
    static let pageSize = 200
    static func earliest(provider: MarketProvider, range: ChartRange, now: Date = Date()) -> Date {
        let days: Double
        if provider == .binance { days = 3652 }
        else {
            switch range {
            case .fourHours, .day: days = 59
            case .week: days = 729
            case .month: days = 3652
            }
        }
        return now.addingTimeInterval(-days * 86400)
    }
    static func pageSpan(provider: MarketProvider, range: ChartRange) -> TimeInterval {
        if provider == .binance { return Double(pageSize) * range.candleDuration }
        switch range {
        case .fourHours: return 7 * 86400
        case .day: return 30 * 86400
        case .week: return 90 * 86400
        case .month: return 365 * 86400
        }
    }
    static func samples(points: [PricePoint], candles: [PriceCandle], interval: TimeInterval) -> [ChartSample] {
        guard interval > 0, interval.isFinite else { return [] }
        let validPoints = points.filter { $0.date.timeIntervalSince1970.isFinite && $0.value.isFinite }
        let pointGroups = Dictionary(grouping: validPoints) { floor($0.date.timeIntervalSince1970 / interval) }
        let groupedCandles = CandleAggregation.aggregate(candles, interval: interval)
        let candleGroups = Dictionary(uniqueKeysWithValues: groupedCandles.map { (floor($0.date.timeIntervalSince1970 / interval), $0) })
        return pointGroups.compactMap { bucket, points in
            let sorted = points.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            return ChartSample(date: first.date, close: last.value, candle: candleGroups[bucket])
        }.sorted { $0.date < $1.date }
    }
}

struct IndexedChartSample: Identifiable {
    let index: Int
    let sample: ChartSample
    var id: Date { sample.date }
}

@MainActor
final class ChartHistoryStore: ObservableObject {
    @Published private(set) var samples: [ChartSample] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingNewer = false
    @Published private(set) var error: String?
    @Published private(set) var nextBefore: Date?
    @Published private(set) var range: ChartRange = .day
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var includesLatest = true
    @Published var position: Double = -0.5
    @Published private(set) var visibleCount: Double = 48
    private let instrument: Instrument
    private let service: any MarketServing
    private var generation = UUID()
    private var newerCursor: Date?
    private enum FailedRequest { case load(ChartRange, Date?), earlier, newer }
    private var failedRequest: FailedRequest?

    init(instrument: Instrument, service: any MarketServing) {
        self.instrument = instrument
        self.service = service
    }

    var earliestDate: Date { ChartHistoryPolicy.earliest(provider: instrument.provider, range: range) }
    var hasEarlier: Bool { nextBefore != nil }
    var maximumPosition: Double { max(-0.5, Double(samples.count) - 0.5 - visibleCount) }
    var visibleIndices: Range<Int> {
        let left = position.isFinite ? max(-0.5, min(Double(samples.count), position)) : -0.5
        let start = max(0, min(samples.count, Int(floor(left + 0.5))))
        let end = max(start, min(samples.count, Int(ceil(left + visibleCount + 0.5))))
        return start..<end
    }
    var visibleSamples: [ChartSample] { Array(samples[visibleIndices]) }
    var plottedSamples: [IndexedChartSample] {
        let margin = Int(ceil(visibleCount))
        let indices = max(0, visibleIndices.lowerBound - margin)..<min(samples.count, visibleIndices.upperBound + margin)
        return indices.map { .init(index: $0, sample: samples[$0]) }
    }
    var anchorDate: Date? { sample(at: position + visibleCount / 2)?.date }

    func sample(at index: Double) -> ChartSample? {
        guard !samples.isEmpty, index.isFinite else { return nil }
        return samples[Int(max(0, min(Double(samples.count - 1), index.rounded())))]
    }

    func yDomain(style: PriceChartStyle) -> ClosedRange<Double> {
        let visible = visibleSamples
        if style == .candles, !visible.compactMap(\.candle).isEmpty {
            return ChartSeries(candles: visible.compactMap(\.candle), fetchedAt: fetchedAt ?? Date()).domain
        }
        return ChartSeries(points: visible.map { .init(date: $0.date, value: $0.close) }, fetchedAt: fetchedAt ?? Date()).domain
    }

    func visibleChange(style: PriceChartStyle) -> Double? {
        let visible = visibleSamples
        if style == .candles {
            return ChartSeries(candles: visible.compactMap(\.candle), fetchedAt: fetchedAt ?? Date()).changePercent
        }
        guard let first = visible.first, let last = visible.last, visible.count > 1, first.close > 0 else { return nil }
        return (last.close - first.close) / first.close * 100
    }

    func zoom(to count: Double, around anchor: Date? = nil) {
        guard !samples.isEmpty, count.isFinite else { return }
        let oldMidpoint = position + visibleCount / 2
        let center = anchor.flatMap { date in samples.firstIndex { $0.date == date }.map(Double.init) } ?? oldMidpoint
        visibleCount = min(Double(samples.count), max(min(8, Double(samples.count)), min(160, count)))
        position = max(-0.5, min(maximumPosition, center - visibleCount / 2))
    }

    func showLatestLoaded() { position = maximumPosition }
    func setPosition(_ value: Double) {
        guard value.isFinite else { return }
        position = max(-0.5, min(maximumPosition, value))
    }

    func load(range requestedRange: ChartRange, endingAt: Date? = nil) async {
        let token = UUID()
        generation = token
        range = requestedRange
        isLoading = true
        isLoadingEarlier = false
        isLoadingNewer = false
        error = nil
        failedRequest = nil
        // Retain a matching book while refreshing; switching interval clears incompatible data.
        if requestedRange.interval != currentInterval {
            samples = []
            nextBefore = nil
            fetchedAt = nil
            position = -0.5
        }
        currentInterval = requestedRange.interval
        defer { if generation == token { isLoading = false } }
        let now = Date()
        let requestedEnd = min(endingAt ?? now, now)
        let reachesLatest = endingAt == nil || requestedEnd >= now.addingTimeInterval(-1)
        do {
            let page = try await nonemptyPage(range: requestedRange, before: requestedEnd)
            guard generation == token, !Task.isCancelled else { return }
            samples = unique(page.samples)
            fetchedAt = page.fetchedAt
            nextBefore = page.nextBefore
            includesLatest = reachesLatest
            newerCursor = requestedEnd
            visibleCount = min(Double(max(1, samples.count)), requestedRange.duration / requestedRange.candleDuration)
            position = maximumPosition
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = MarketStore.message(error)
            failedRequest = .load(requestedRange, endingAt)
        }
    }
    private var currentInterval = ChartRange.day.interval

    func loadEarlier(force: Bool = false) async {
        guard !isLoading, !isLoadingEarlier, !isLoadingNewer, let cursor = nextBefore,
              force || position <= visibleCount * 0.6 else { return }
        let token = generation
        isLoadingEarlier = true
        error = nil
        failedRequest = nil
        defer { if generation == token { isLoadingEarlier = false } }
        do {
            let page = try await nonemptyPage(range: range, before: cursor)
            guard generation == token, !Task.isCancelled else { return }
            let oldFirst = samples.first?.date
            let merged = unique(page.samples + samples)
            let added = oldFirst.flatMap { date in merged.firstIndex { $0.date == date } } ?? 0
            samples = merged
            nextBefore = page.nextBefore.flatMap { $0 < cursor ? $0 : nil }
            position += Double(added)
            position = max(-0.5, min(maximumPosition, position))
            fetchedAt = page.fetchedAt
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = MarketStore.message(error)
            failedRequest = .earlier
        }
    }

    func loadNewerIfNeeded() async {
        guard !isLoading, !isLoadingEarlier, !isLoadingNewer, !includesLatest,
              position >= maximumPosition - visibleCount * 0.6, let last = samples.last else { return }
        let token = generation
        isLoadingNewer = true
        error = nil
        failedRequest = nil
        defer { if generation == token { isLoadingNewer = false } }
        do {
            // Advance through empty sessions without exceeding the provider's 200-bar
            // page cap. Twelve short pages can cross a long market weekend.
            let span = range.candleDuration * 100
            for _ in 0..<12 {
                let now = Date()
                let end = min(now, max(newerCursor ?? last.date, last.date).addingTimeInterval(span))
                let page = try await service.historyPage(for: instrument, range: range, before: end)
                guard generation == token, !Task.isCancelled else { return }
                let additions = page.samples.filter { $0.date >= last.date }
                samples = unique(samples + additions)
                newerCursor = end
                includesLatest = end >= now.addingTimeInterval(-1)
                fetchedAt = page.fetchedAt
                if additions.contains(where: { $0.date > last.date }) || includesLatest { break }
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = MarketStore.message(error)
            failedRequest = .newer
        }
    }

    func retry() async {
        switch failedRequest {
        case let .load(range, date): await load(range: range, endingAt: date)
        case .earlier: await loadEarlier(force: true)
        case .newer: await loadNewerIfNeeded()
        case nil: await load(range: range, endingAt: includesLatest ? nil : newerCursor)
        }
    }

    private func nonemptyPage(range: ChartRange, before: Date) async throws -> HistoryPage {
        var cursor = before
        var last: HistoryPage?
        for _ in 0..<3 {
            let page = try await service.historyPage(for: instrument, range: range, before: cursor)
            try Task.checkCancellation()
            if !page.samples.isEmpty { return page }
            last = page
            guard let next = page.nextBefore, next < cursor else { return page }
            cursor = next
        }
        return last!
    }

    private func unique(_ items: [ChartSample]) -> [ChartSample] {
        var byDate: [Date: ChartSample] = [:]
        for item in items where item.date.timeIntervalSince1970.isFinite && item.close.isFinite { byDate[item.date] = item }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
