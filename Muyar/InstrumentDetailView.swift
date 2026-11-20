import SwiftUI
import Charts

struct InstrumentDetailView: View {
    let instrument: Instrument
    @EnvironmentObject private var store: MarketStore
    @StateObject private var chart: ChartHistoryStore
    @AppStorage("price-chart-style") private var styleValue = PriceChartStyle.candles.rawValue
    @State private var range: ChartRange
    @State private var selectedDate: Date?
    @State private var showingDate = false
    @State private var jumpDate = Date()
    @State private var initialDate: Date?
    @State private var pinchCount: Double?
    @State private var pinchAnchor: Date?

    init(instrument: Instrument, service: any MarketServing = MarketService()) {
        self.instrument = instrument
        var initialRange = ChartRange.day
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-chart-range"), arguments.indices.contains(index + 1),
           let value = ChartRange(rawValue: arguments[index + 1]) { initialRange = value }
        if let index = arguments.firstIndex(of: "-chart-date"), arguments.indices.contains(index + 1) {
            _initialDate = State(initialValue: ISO8601DateFormatter().date(from: arguments[index + 1] + "T23:59:00Z"))
        }
        #endif
        _range = State(initialValue: initialRange)
        _chart = StateObject(wrappedValue: ChartHistoryStore(instrument: instrument, service: service))
    }

    private var style: PriceChartStyle { PriceChartStyle(rawValue: styleValue) ?? .candles }
    private var snapshot: MarketSnapshot? { store.snapshots[instrument.id] }
    private var selectedSample: ChartSample? {
        guard let selectedDate else { return nil }
        return chart.samples.first { $0.date == selectedDate }
    }
    private var readout: ChartSample? { selectedSample ?? chart.visibleSamples.last }
    private var displayPrice: Double? {
        if style == .candles { return readout?.candle?.close ?? readout?.close ?? snapshot?.price }
        return readout?.close ?? snapshot?.price
    }
    private var selectedIndex: Binding<Double?> {
        Binding {
            selectedDate.flatMap { date in chart.samples.firstIndex { $0.date == date }.map(Double.init) }
        } set: { index in
            selectedDate = index.flatMap { chart.sample(at: $0)?.date }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                instrumentHeader
                priceHeader
                rangePicker
                chartControls
                chartPanel
                quoteDetails
            }
            .padding(24)
        }
        .background(MuyarTheme.background)
        .navigationTitle(instrument.displaySymbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedDate = nil
                    Task {
                        await store.refreshInstrument(instrument)
                        await chart.load(range: range)
                    }
                } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(chart.isLoading).accessibilityLabel("Refresh instrument")
            }
        }
        .task(id: range) {
            selectedDate = nil
            let date = initialDate
            initialDate = nil
            await chart.load(range: range, endingAt: date)
        }
        .onChange(of: chart.position) { _, _ in
            selectedDate = nil
            Task {
                await chart.loadEarlier()
                await chart.loadNewerIfNeeded()
            }
        }
        .onChange(of: styleValue) { _, _ in selectedDate = nil }
        .sheet(isPresented: $showingDate) { dateSheet }
        .accessibilityIdentifier("instrument-detail")
    }

    private var instrumentHeader: some View {
        HStack(spacing: 13) {
            AssetIcon(instrument: instrument)
            VStack(alignment: .leading, spacing: 6) {
                Text(instrument.name).font(.system(size: 25, weight: .regular, design: .serif))
                Text("\(instrument.exchange) · \(instrument.category.rawValue)")
                    .font(.system(size: 12)).foregroundStyle(MuyarTheme.muted)
            }
            Spacer()
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayPrice.map { PriceFormat.price($0, currency: snapshot?.currency ?? instrument.currency) } ?? "—")
                    .font(.system(size: 40, weight: .medium, design: .rounded)).tracking(-1.3)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    .accessibilityIdentifier("detail-price")
                Text(snapshot?.currency ?? instrument.currency).font(.system(size: 12)).foregroundStyle(MuyarTheme.muted)
            }
            HStack(spacing: 9) {
                if let selectedSample {
                    Text(selectedSample.date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                } else {
                    ChangeLabel(value: chart.visibleChange(style: style))
                    Text("Visible range")
                }
            }
            .font(.system(size: 11)).foregroundStyle(MuyarTheme.muted)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(ChartRange.allCases) { item in
                Button { range = item } label: {
                    Text(item.rawValue).font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(range == item ? MuyarTheme.background : MuyarTheme.muted)
                        .background(range == item ? MuyarTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityAddTraits(range == item ? .isSelected : [])
                .accessibilityIdentifier("range-\(item.rawValue)")
            }
        }
        .padding(5).background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chartControls: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(PriceChartStyle.allCases) { item in
                    Button { styleValue = item.rawValue } label: {
                        Group {
                            if item == .candles { CandlestickIcon() }
                            else { Image(systemName: "chart.xyaxis.line").frame(width: 20, height: 20) }
                        }
                        .frame(width: 40, height: 40)
                        .foregroundStyle(style == item ? MuyarTheme.accent : MuyarTheme.muted)
                        .background(style == item ? MuyarTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel(item == .candles ? "Candlestick chart" : "Line chart")
                    .accessibilityAddTraits(style == item ? .isSelected : [])
                    .accessibilityIdentifier(item == .candles ? "chart-style-candles" : "chart-style-line")
                }
            }
            .padding(2).background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 12)
            if chart.isLoadingEarlier || chart.isLoadingNewer { ProgressView().controlSize(.small).tint(MuyarTheme.accent) }
            Button {
                Task {
                    await chart.loadEarlier(force: true)
                    chart.setPosition(chart.position - chart.visibleCount * 0.8)
                }
            } label: { Image(systemName: "chevron.left").frame(width: 36, height: 44) }
                .disabled(chart.isLoading || chart.isLoadingEarlier || chart.isLoadingNewer || (chart.position <= -0.5 && !chart.hasEarlier))
                .accessibilityLabel("Earlier prices").accessibilityIdentifier("chart-earlier")
            Button {
                jumpDate = min(Date(), max(chart.earliestDate, readout?.date ?? Date()))
                showingDate = true
            } label: { Image(systemName: "calendar").frame(width: 40, height: 44) }
                .accessibilityLabel("Go to date").accessibilityIdentifier("chart-date")
            Button {
                Task {
                    chart.setPosition(chart.position + chart.visibleCount * 0.8)
                    await chart.loadNewerIfNeeded()
                }
            } label: { Image(systemName: "chevron.right").frame(width: 36, height: 44) }
                .disabled(chart.isLoading || chart.isLoadingEarlier || chart.isLoadingNewer || (chart.includesLatest && chart.position >= chart.maximumPosition))
                .accessibilityLabel("Newer prices").accessibilityIdentifier("chart-newer")
            Button {
                selectedDate = nil
                Task {
                    if chart.includesLatest { chart.showLatestLoaded() }
                    else { await chart.load(range: range) }
                }
            } label: { TodayCalendarIcon().frame(width: 40, height: 44) }
                .accessibilityLabel("Today, latest prices").accessibilityIdentifier("chart-latest")
        }
        .foregroundStyle(MuyarTheme.accent)
    }

    @ViewBuilder private var chartPanel: some View {
        if chart.isLoading && chart.samples.isEmpty {
            ProgressView("Loading…").tint(MuyarTheme.accent).frame(maxWidth: .infinity).frame(height: 300)
        } else if !chart.samples.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if style == .candles, let candle = readout?.candle { candleReadout(candle) }
                priceChart.frame(height: 290)
                    .accessibilityLabel(style == .candles ? "Candlestick chart" : "Price line chart")
                    .accessibilityIdentifier("price-chart")
                HStack(alignment: .top) {
                    Text(range.candleLabel)
                    Spacer()
                    if let first = chart.visibleSamples.first, let last = chart.visibleSamples.last {
                        Text(first.date, format: .dateTime.year().month(.abbreviated).day())
                        Text("–")
                        Text(last.date, format: .dateTime.year().month(.abbreviated).day())
                    }
                }
                .font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
                if let error = chart.error {
                    HStack {
                        Text(error).foregroundStyle(MuyarTheme.gold)
                        Spacer()
                        Button("Retry") { Task { await chart.retry() } }
                    }.font(.caption)
                }
                if style == .candles && chart.visibleSamples.compactMap(\.candle).isEmpty {
                    Text("No OHLC").font(.caption).foregroundStyle(MuyarTheme.muted)
                }
            }
        } else {
            VStack(spacing: 14) {
                Text(chart.error ?? "No data").font(.subheadline).foregroundStyle(MuyarTheme.muted)
                HStack(spacing: 20) {
                    if chart.hasEarlier { Button("Earlier") { Task { await chart.loadEarlier(force: true) } } }
                    Button("Retry") { Task { await chart.retry() } }
                }.font(.subheadline)
            }.frame(maxWidth: .infinity).frame(height: 240)
        }
    }

    private var priceChart: some View {
        let lineColor = (chart.visibleChange(style: .line) ?? 0) >= 0 ? MuyarTheme.positive : MuyarTheme.red
        return Chart {
            ForEach(chart.plottedSamples) { item in
                if style == .candles {
                    if let candle = item.sample.candle { CandleMarks(candle: candle, index: Double(item.index)) }
                } else {
                    LineMark(x: .value("Observation", Double(item.index)), y: .value("Close", item.sample.close))
                        .foregroundStyle(lineColor).lineStyle(.init(lineWidth: 2))
                }
            }
            if let date = selectedDate, let index = chart.samples.firstIndex(where: { $0.date == date }) {
                RuleMark(x: .value("Selected", Double(index)))
                    .foregroundStyle(.primary.opacity(0.5)).lineStyle(.init(dash: [3, 4]))
                if style == .line, let sample = selectedSample {
                    PointMark(x: .value("Observation", Double(index)), y: .value("Close", sample.close))
                        .foregroundStyle(lineColor).symbolSize(35)
                }
            }
        }
        .chartYScale(domain: chart.yDomain(style: style))
        .chartXScale(domain: -0.5...(Double(max(1, chart.samples.count)) - 0.5))
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: chart.visibleCount)
        .chartScrollPosition(x: Binding(get: { chart.position }, set: { chart.setPosition($0) }))
        .chartXSelection(value: selectedIndex)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .simultaneousGesture(pinchGesture)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let index = value.as(Double.self), index >= 0, index < Double(chart.samples.count), let sample = chart.sample(at: index) {
                        Text(sample.date, format: axisDateFormat).font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(MuyarTheme.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.notation(.compactName).precision(.fractionLength(0...2))))
                            .font(.system(size: 10)).foregroundStyle(MuyarTheme.muted).frame(width: 43, alignment: .leading)
                    }
                }
            }
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchCount == nil { pinchCount = chart.visibleCount; pinchAnchor = chart.anchorDate }
                chart.zoom(to: (pinchCount ?? chart.visibleCount) / value.magnification, around: pinchAnchor)
            }
            .onEnded { _ in
                pinchCount = nil
                pinchAnchor = nil
                Task { await chart.loadEarlier() }
            }
    }
    private var xAxisValues: [Double] {
        let step = max(1, Int(chart.visibleCount / 3))
        let first = max(0, Int(floor(chart.position / Double(step))) * step)
        return stride(from: first, through: min(chart.samples.count - 1, Int(ceil(chart.position + chart.visibleCount))), by: step).map(Double.init)
    }
    private var axisDateFormat: Date.FormatStyle {
        let span = (chart.visibleSamples.last?.date.timeIntervalSince(chart.visibleSamples.first?.date ?? Date())) ?? 0
        return span > 86400 ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute()
    }

    private func candleReadout(_ candle: PriceCandle) -> some View {
        HStack(spacing: 8) {
            candleValue("O", candle.open); candleValue("H", candle.high)
            candleValue("L", candle.low); candleValue("C", candle.close)
        }.accessibilityIdentifier("candle-ohlc")
    }
    private func candleValue(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(MuyarTheme.muted)
            Text(PriceFormat.number(value, currency: snapshot?.currency ?? instrument.currency))
                .font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var dateSheet: some View {
        NavigationStack {
            DatePicker("Date", selection: $jumpDate, in: chart.earliestDate...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical).padding(20)
                .background(MuyarTheme.background)
                .navigationTitle("Go to date").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingDate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            showingDate = false
                            selectedDate = nil
                            let end = min(Date(), Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: jumpDate)) ?? jumpDate)
                            Task { await chart.load(range: range, endingAt: end) }
                        }
                    }
                }
        }.presentationDetents([.medium, .large])
    }

    private var quoteDetails: some View {
        VStack(spacing: 16) {
            detailRow("Source", value: instrument.provider.name)
            if let snapshot {
                detailRow("Session", value: snapshot.marketOpen ? (instrument.provider == .binance ? "24/7 market" : "Market open") : "Market closed")
                detailRow("\(snapshot.changeLabel.capitalized) change", value: PriceFormat.change(snapshot.changePercent))
                detailRow("Quote time", value: snapshot.marketDate.formatted(date: .abbreviated, time: .shortened))
                detailRow("Last fetched", value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                if snapshot.isStale() || store.errors[instrument.id] != nil { FootnoteLabel(icon: "clock.arrow.circlepath", text: "Saved quote") }
            }
            if let unit = instrument.unit { detailRow("Quoted per", value: "1 \(unit)") }
        }.padding(19).background(MuyarTheme.card, in: RoundedRectangle(cornerRadius: 19))
    }
    private func detailRow(_ name: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(name).foregroundStyle(MuyarTheme.muted)
            Spacer(minLength: 20)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 12))
    }
}

private struct TodayCalendarIcon: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                Canvas { context, _ in
                    var outline = Path(roundedRect: CGRect(x: 1, y: 3, width: 18, height: 18), cornerRadius: 3)
                    outline.move(to: CGPoint(x: 1, y: 8))
                    outline.addLine(to: CGPoint(x: 19, y: 8))
                    for x: CGFloat in [6, 14] {
                        outline.move(to: CGPoint(x: x, y: 1))
                        outline.addLine(to: CGPoint(x: x, y: 5))
                    }
                    context.stroke(outline, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                Text(context.date, format: .dateTime.day())
                    .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                    .offset(y: 3.5)
            }.frame(width: 20, height: 22)
        }.accessibilityHidden(true)
    }
}

private struct CandlestickIcon: View {
    var body: some View {
        Canvas { context, _ in
            let bars: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (4, 2, 17, 5, 7), (10, 5, 20, 9, 7), (16, 0, 16, 3, 8)
            ]
            for (x, top, bottom, bodyTop, height) in bars {
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: top))
                wick.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(wick, with: .foreground, lineWidth: 1.3)
                context.fill(Path(CGRect(x: x - 2, y: bodyTop, width: 4, height: height)), with: .foreground)
            }
        }
        .frame(width: 20, height: 20).accessibilityHidden(true)
    }
}

private struct CandleMarks: ChartContent {
    let candle: PriceCandle
    let index: Double
    private var color: Color { candle.close == candle.open ? MuyarTheme.muted : (candle.close > candle.open ? MuyarTheme.positive : MuyarTheme.red) }
    var body: some ChartContent {
        RuleMark(x: .value("Observation", index), yStart: .value("Low", candle.low), yEnd: .value("High", candle.high))
            .foregroundStyle(color).lineStyle(.init(lineWidth: 1)).accessibilityHidden(true)
        if candle.open == candle.close {
            RuleMark(xStart: .value("Start", index - 0.32), xEnd: .value("End", index + 0.32), y: .value("Open / Close", candle.open))
                .foregroundStyle(color).lineStyle(.init(lineWidth: 1.5))
        } else {
            RectangleMark(xStart: .value("Start", index - 0.32), xEnd: .value("End", index + 0.32),
                          yStart: .value("Body low", min(candle.open, candle.close)), yEnd: .value("Body high", max(candle.open, candle.close)))
                .foregroundStyle(color)
        }
    }
}
