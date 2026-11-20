import SwiftUI
import Charts
import UIKit

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

enum MuyarTheme {
    static let background = adaptive(light: (0.98, 0.97, 0.94), dark: (0.055, 0.052, 0.045))
    static let card = adaptive(light: (1, 0.995, 0.98), dark: (0.105, 0.098, 0.083))
    static let line = adaptive(light: (0.87, 0.84, 0.78), dark: (0.18, 0.165, 0.14))
    static let accent = adaptive(light: (0.49, 0.34, 0.08), dark: (0.90, 0.76, 0.46))
    static let positive = adaptive(light: (0.08, 0.43, 0.31), dark: (0.55, 0.89, 0.73))
    static let gold = accent
    static let muted = adaptive(light: (0.44, 0.41, 0.35), dark: (0.65, 0.63, 0.58))
    static let red = adaptive(light: (0.75, 0.20, 0.22), dark: (1, 0.49, 0.48))
    static let p2pTint = adaptive(light: (0.98, 0.94, 0.83), dark: (0.16, 0.135, 0.085))
    static let bitcoin = adaptive(light: (0.72, 0.34, 0.02), dark: (0.97, 0.62, 0.17))
    static let ethereum = adaptive(light: (0.32, 0.40, 0.66), dark: (0.64, 0.69, 0.88))
    static let nvidia = adaptive(light: (0.35, 0.48, 0), dark: (0.60, 0.80, 0.10))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
    static func color(for category: AssetCategory) -> Color {
        switch category {
        case .metals: gold
        case .energy: adaptive(light: (0.19, 0.39, 0.70), dark: (0.62, 0.75, 0.97))
        case .stocks: adaptive(light: (0.43, 0.32, 0.68), dark: (0.74, 0.69, 0.96))
        case .crypto: accent
        }
    }
    static func color(for brand: InstrumentBrand) -> Color {
        switch brand.tint {
        case .bitcoin: bitcoin
        case .ethereum: ethereum
        case .nvidia: nvidia
        case .primary, .original: .primary
        case .positive: positive
        case .red: red
        case .gold: gold
        case .blue: color(for: .energy)
        }
    }
}

struct AppearanceControl: View {
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppAppearance.allCases) { item in
                Button { appearance = item.rawValue } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(appearance == item.rawValue ? Color.primary : MuyarTheme.muted)
                        .frame(width: 44, height: 44)
                        .background(appearance == item.rawValue ? MuyarTheme.line.opacity(0.45) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue.capitalized) appearance")
                .accessibilityAddTraits(appearance == item.rawValue ? .isSelected : [])
                .accessibilityIdentifier("appearance-\(item.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AssetIcon: View {
    let instrument: Instrument
    private var color: Color {
        if let brand = instrument.brand { return MuyarTheme.color(for: brand) }
        return instrument.glyph == .dollar ? MuyarTheme.accent : MuyarTheme.color(for: instrument.category)
    }
    var body: some View {
        Group {
            if let brand = instrument.brand {
                Image(brand.assetName)
                    .renderingMode(brand.tint == .original ? .original : .template)
                    .resizable().scaledToFit().frame(width: 24, height: 24)
            } else if let glyph = instrument.glyph {
                switch glyph {
                case .goldBrick: GoldBrickIcon().frame(width: 25, height: 25)
                case .oil: Image(systemName: "drop.fill").font(.system(size: 23))
                case .dollar: Image(systemName: "dollarsign").font(.system(size: 24, weight: .medium))
                }
            } else {
                Text(instrument.monogram)
                    .font(.system(size: instrument.monogram.count > 2 ? 13 : 17, weight: .semibold, design: .rounded))
            }
        }
            .foregroundStyle(color)
            .frame(width: 43, height: 43)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

private struct GoldBrickIcon: View {
    var body: some View {
        Canvas { context, _ in
            var top = Path()
            top.move(to: .init(x: 6, y: 4))
            top.addLine(to: .init(x: 19, y: 4))
            top.addLine(to: .init(x: 23, y: 16))
            top.addLine(to: .init(x: 2, y: 16))
            top.closeSubpath()
            context.fill(top, with: .foreground)
            var front = Path()
            front.move(to: .init(x: 2, y: 16))
            front.addLine(to: .init(x: 23, y: 16))
            front.addLine(to: .init(x: 21, y: 21))
            front.addLine(to: .init(x: 4, y: 21))
            front.closeSubpath()
            var faceContext = context
            faceContext.opacity = 0.65
            faceContext.fill(front, with: .foreground)
            var bevel = Path()
            bevel.move(to: .init(x: 7, y: 7))
            bevel.addLine(to: .init(x: 18, y: 7))
            context.stroke(bevel, with: .color(MuyarTheme.background.opacity(0.55)), style: .init(lineWidth: 1.3, lineCap: .round))
        }
    }
}

struct ChangeLabel: View {
    let value: Double?
    var body: some View {
        HStack(spacing: 3) {
            if let value { Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .bold)) }
            Text(PriceFormat.change(value)).monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(value == nil ? MuyarTheme.muted : ((value ?? 0) >= 0 ? MuyarTheme.positive : MuyarTheme.red))
    }
}

struct Sparkline: View {
    let points: [PricePoint]
    let positive: Bool
    var body: some View {
        if points.count > 1 {
            let color = positive ? MuyarTheme.positive : MuyarTheme.red
            let series = ChartSeries(points: points, fetchedAt: Date())
            Chart(points) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Base", series.domain.lowerBound), yEnd: .value("Price", point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.18), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Price", point.value))
                    .foregroundStyle(color).lineStyle(.init(lineWidth: 1.5))
            }
            .chartYScale(domain: series.domain)
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .accessibilityHidden(true)
        } else {
            Rectangle().fill(MuyarTheme.line).frame(height: 1).accessibilityHidden(true)
        }
    }
}

struct FootnoteLabel: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(MuyarTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
