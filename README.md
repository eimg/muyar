# Muyar

**Quick Market Update** — a small, native iPhone watchlist for a daily glance at gold, oil, stocks, crypto, and Binance P2P USDT/MMK.

SwiftUI + Swift Charts. iOS 17 or later. No packages, backend, exchange account, API key, analytics, or App Store distribution.

The app UI is data-only: prices, charts, offers, limits, payment methods and timestamps. No marketing copy or warning paragraphs. Source limitations below are repository documentation rather than in-app filler.

## Run

Open `Muyar.xcodeproj`, choose the **Muyar** scheme and an iPhone simulator, then Run. Xcode 16 or newer is required (the project uses synchronized source groups).

```sh
xcodebuild -project Muyar.xcodeproj -scheme Muyar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
```

The simulator name must match one installed on your Mac (`xcrun simctl list devices available`).

## Install on your paired iPhone

Choose your Apple development team in Xcode for local installation. The bundle identifier is `com.eimg.Muyar`. No App Store upload is involved.

1. Connect and unlock the iPhone. Developer Mode must be enabled.
2. Open the project in Xcode and select the physical iPhone as the run destination.
3. Under **Signing & Capabilities**, confirm the development team; select another team if needed.
4. Run. Accept any Apple signing or device trust prompts yourself.

Alternatively, run `bash scripts/install-iphone.sh DEVICE_IDENTIFIER` using an identifier from `xcrun devicectl list devices`. This builds Release with automatic development signing, installs, and launches the app. It may need your Xcode developer account to provision the app. Development installations expire according to their provisioning profile; rebuild and reinstall to renew them.

## Version 1

- Initial watchlist: COMEX gold futures, WTI crude futures, BTC/USDT, ETH/USDT, Apple, NVIDIA.
- Search supported stocks/ETFs/indices and Binance spot pairs; add, remove, and reorder instruments.
- 103 bundled brand marks covering 70 company brands, 30 crypto assets, and reserved SpaceX, Anthropic and OpenAI marks. Icons are available before adding an instrument; the reserved marks have no speculative tickers or prices. Icons follow the crypto base asset across quote pairs; unknown symbols keep a monogram. Gold uses a brick, DXY a dollar sign, and oil futures a droplet.
- Category filters and a compact sparkline per available day series.
- Gold accents with light and dark palettes. A small System / Light / Dark icon control at the bottom of the watchlist saves the appearance choice; System follows iOS. Charts and sheets follow the same appearance. The app icon uses the matching gold mark.
- Detail charts use candle and line icon buttons in a single control row, with date navigation on the right and the style choice saved on-device. Candles use real OHLC bodies, high/low wicks, neutral dojis and a tapped O/H/L/C readout; lines use available closing prices, including rows without complete OHLC. Home sparklines remain close-price lines.
- **4H / 1D / 1W / 1M** presets choose **5m / 30m / 4h / 1D bars** and an initial window of 48 / 48 / 42 / 30 observations. Pinch to zoom, drag horizontally, load earlier/newer prices, jump to a date, or return to Latest. History loads in pages of up to 200 observations. The vertical scale follows the visible prices.
- P2P **buy USDT** and **sell USDT** reference quotes in MMK per USDT. No P2P charts or history collection.
- Tap the P2P card to compare **five sellers for buying USDT** and **five buyers for selling USDT**, when available. Show advertised price, payment methods, MMK limits, available USDT, and advertiser completion/order statistics. Buy is cheapest first; sell is highest first. Rankings are among up to 20 returned listings per direction, not a claim about all available market liquidity.
- Refresh on foreground, pull-to-refresh, manual refresh, and every five minutes while active.
- Atomic on-device persistence of watchlist and latest snapshots. Cached prices survive connection failures, are marked saved/stale, and remain visible without login.
- No background polling, push notifications, portfolio connection, or trading functionality.

## Sources and limitations

- **Binance Spot**: unauthenticated `data-api.binance.vision` ticker, klines, and exchange catalog endpoints. Crypto prices retain their quote currency: USDT is not relabelled USD.
- **Binance P2P**: public `www.binance.com/bapi/c2c/v1/public/c2c/agent/quote-price`, `ad-list`, and `trade-methods`. BUY means you buy USDT from sellers; SELL means you sell USDT to buyers. No credentials. Fetch time is receipt time, not a source quote/ad timestamp. The offer screen compares public advertisements across payment methods with no amount filter; actual eligibility and executable liquidity are not verified. Price quotes and ads are separate responses and are never substituted for one another. A successful empty list clears previous offers and explicitly says no public offers were returned; a failed refresh preserves the prior in-memory book with a saved/error label. Offers refresh on opening/foreground, manually, and every minute while the screen is active. They are not persisted to disk or accumulated as history.
- **Yahoo Finance**: public chart and symbol search endpoints for stocks and futures. These are unofficial integration endpoints without an availability contract; response formats, access, and delays can change. A licensed provider adapter can replace this service later. Personal installation does not imply redistribution rights.
- Gold and oil defaults are **futures**, not physical gold/oil spot prices. Gold is USD per troy ounce; oil is USD per barrel. The continuous quoted contract can roll. Myanmar retail gold requires its own source.
- A refresh time does not imply a new exchange observation. Quote time and fetch time are separate in instrument details. Detail charts use observed bars with real date labels, compressing closed-session time without inserting prices. The initial visible period can therefore cover more calendar time than its preset, especially for stocks. A date jump loads the observations ending at that date.
- Watchlist percentage changes are Binance 24-hour change or Yahoo previous-close change. Detail changes compare the visible first candle's open with the last candle's close, or first/last closing prices in Line mode. Yahoo hourly OHLC is aggregated into UTC four-hour buckets. Missing OHLC rows are not fabricated; close-only rows remain available in Line mode.
- History is bounded by the source and listing date: up to ten years for Binance and Yahoo daily bars, 59 days for Yahoo 5m/30m bars, and 729 days for Yahoo hourly data used by the four-hour view. History pages remain in memory while the detail screen is open; they are not a locally accumulated archive.
- Feeds are fetched **directly from the phone**. There is no hosted relay. Availability depends on ISP and provider restrictions; caching avoids blank screens but cannot guarantee VPN-free live data. Muyar never manages your VPN or asks for exchange credentials.
- State is stored in Application Support using iOS file protection and atomic writes. Uninstalling the app removes it. Only latest snapshots and their current chart observations are cached; no P2P time series is accumulated.

## Test

```sh
xcodebuild -project Muyar.xcodeproj -scheme Muyar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test
```

Unit tests cover provider parsing, timestamp alignment, null observations, OHLC validation/aggregation, visible scaling, zoom anchors, historical paging/date jumps, empty sessions, request cancellation, retries, source bounds, old-cache compatibility, currency labels, offline preservation, and watchlist persistence. Offer tests cover viewer-side request parameters, ordering/capping, invalid pairs/prices/limits, duplicate ads, payment mapping, empty vs failed responses, and independent refresh failures. UI tests cover P2P display, five offers per direction, empty offer states, chart ranges/style icons and date navigation, search/add, filters, and removal.

UI tests explicitly launch with `-ui-testing`, use deterministic fixture data, and write to a unique temporary state file. This mode exists only in Debug builds. Normal launches always use live services; Release builds contain no fixtures.

The same core tests also run on macOS without a simulator: `swift test --scratch-path build/CoreTests`. This package is a test harness for the shared data layer, not a macOS app.

For visual smoke checks when the UI test daemon is unavailable, a Debug build accepts `-open-instrument BTCUSDT -chart-range 1M`, optionally `-chart-style Line` (or `Candles`), `-chart-date 2025-11-01`, and `-preview-appearance light` (or `dark` / `system`). It opens that detail screen using the normal live service (unless `-ui-testing` is also supplied). These launch shortcuts are absent in Release.

`-show-appearance-controls` starts the watchlist at its bottom appearance control for visual checks. `-open-p2p` opens the offers screen. For deterministic screenshots, combine it with `-ui-testing`; these ads show a short “Sample data” label. Add `-empty-p2p-offers` to exercise the empty state with the fixture service. Normal launches never use fixtures. At the 20 November 2026 live check, public MMK ad lists were empty while CNY returned real listings; Muyar reports MMK's empty result without inventing five offers.

The app icon is drawn from native shapes. Regenerate with:

```sh
swift -module-cache-path build/ModuleCache scripts/generate-icon.swift \
  Muyar/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Later

P2P snapshot collection/history, a reachable feed relay if needed, optional alerts, and a licensed market-data provider. None is required for this version.

Brand icon sources and license information are in [ThirdParty/README.md](ThirdParty/README.md). Icons are bundled locally; no logo service or extra network calls are used.

The complete [icon catalog](ThirdParty/BrandIcons/README.md) lists supported symbols. A Debug launch with `-preview-brand-icons` shows the bundled marks; add `-preview-icons-bottom` for the end of the catalog. Neither preview exists in Release.
