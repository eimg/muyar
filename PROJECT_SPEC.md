# Muyar: Quick Market Update

## Product

An iPhone-only personal market tracker, installed locally on a paired device. No App Store distribution. Fast daily observation without an exchange login. Native SwiftUI and Swift Charts, minimum iOS 17, portrait. No external dependencies.

UI preference: data only. No marketing copy, warning paragraphs, educational boilerplate, or decorative taglines. Show prices, charts, offers, limits, payment methods, counts and timestamps. Keep necessary empty/error/saved states short. Source and instrument type are factual labels, not advisory text.

Appearance: gold accents on warm light or charcoal dark surfaces; keep green/red for price direction. A subtle three-icon System / Light / Dark control sits at the bottom of the watchlist. Save the choice in UserDefaults, default to System, and apply it across navigation, charts and sheets. The app icon uses the same gold palette.

## Scope

Watchlist defaults: GC=F (COMEX gold futures), CL=F (WTI crude futures), BTCUSDT, ETHUSDT, AAPL, NVDA. Users can add supported instruments, prevent duplicates, remove all defaults if desired, reorder, and filter by category. USDT/MMK P2P reference card is fixed above the watchlist.

P2P independently refreshes BUY and SELL reference quotes. Show MMK per USDT and fetch time, never claim an executable offer, and distinguish USDT from USD. Tapping the fixed P2P card opens a sheet with up to five offers on each side. BUY is the viewer paying MMK to sellers, sorted cheapest first; SELL is the viewer receiving MMK from buyers, sorted highest first. Rank among up to 20 public returned listings per direction. Show advertiser name, price, MMK limits, available USDT, payment methods, 30-day order count and completion fraction when supplied. No payment or amount filter in this version. No P2P history, chart, order list, account integration, or trade execution.

Detail chart presets 4H, 1D, 1W and 1M choose 5m, 30m, 4h and 1D bars with initial windows of 48, 48, 42 and 30 observations. Candle and line icon buttons save the user's style preference. A single control row places style icons on the left and earlier/calendar/newer/latest icons on the right (Latest is a calendar displaying today's day number); there are no zoom buttons. Render real OHLC candles: up bodies green, down red, neutral dojis and full high/low wicks. Line mode uses real closing observations even if OHLC is incomplete. Tap selection shows price/time and, for candles, O/H/L/C; otherwise show the latest visible observation. Never synthesize OHLC or fill missing periods. Yahoo hourly data aggregates into UTC four-hour buckets. Observations have equal horizontal spacing, compressing closed sessions while keeping real dates in axis labels and readouts. Home sparklines stay close-price lines.

Charts support horizontal scrolling, pinch zoom (8–160 observed bars, bounded by available data), earlier/newer paging, a date picker and Latest. Fetch up to 200 observations per page, preserve the visible date when prepending, discard obsolete interval requests and scale the y-axis to the visible values (including candle wicks). Date jumps end at the selected day and may page backward through empty sessions. Source limits: ten years for Binance and Yahoo daily data, 59 days for Yahoo 5m/30m and 729 days for Yahoo hourly data, further bounded by listing date. History pages are in-memory detail state, not a stored archive. Empty/error states are short.

Watchlist percent change: source 24-hour change for Binance, previous-close change for Yahoo. Detail percent change: visible first candle open to last candle close, or first/last close in Line mode. Futures, units, currency, session status, source, quote time, and fetch time are factual labels.

Known crypto/company assets use bundled vector brand marks across watchlist, detail, search and editing. Resolve crypto marks from the exact base asset using its quote currency; similar prefixes must not inherit an unrelated brand. Unsupported symbols retain monograms. Oil futures use a droplet symbol. No runtime logo requests. Icon sources and licensing are recorded under `ThirdParty/`.

## Architecture

- `Models.swift`: provider-independent instruments, quotes, OHLC candles, aggregation, wick-aware series domains, formatting, and range semantics. Latest quote caches optionally include OHLC; existing close-only caches remain readable but cannot be plotted as candles.
- `MarketService.swift`: `MarketServing` protocol, actor-isolated HTTPS URLSession adapter, provider DTOs and pure parsers. Binance Spot and public P2P endpoints; Yahoo public finance chart/search for non-crypto. No secrets or account APIs.
- `MarketStore.swift`: main-actor observable state, independent fetch failures, watchlist mutations, atomic file-protected Application Support JSON. Retain last successful values on failure and ignore responses for removed instruments.
- `MuyarApp.swift`: app entry. `PreviewMarketService.swift` provides explicit Debug-only fixture data for isolated UI tests.
- `WatchlistView.swift`: dashboard, P2P card, edit sheet, filters, foreground refresh loop.
- `P2POffers.swift`: explicit viewer-side enum, public ad/payment DTO decoding, validation, ranking/deduplication, independent per-direction observable refresh state.
- `P2POffersView.swift`: offer comparison sheet, per-side empty/error/saved states, pull/manual/foreground refresh and a one-minute foreground refresh loop.
- `ChartHistory.swift`: chart styles, observed samples, provider history limits, paged loading with cancellation guards, zoom/scroll state, visible scales and retries.
- `InstrumentDetailView.swift`: chart style/range controls, horizontal scrolling, pinch zoom, touch selection, date navigation and quote details.
- `AddInstrumentView.swift`: debounced search, duplicate handling, suggestions.
- `AppAppearance.swift`: shared appearance preference and a Debug preview flag whose name cannot shadow the saved choice.
- `InstrumentBrand.swift`: exact provider/base-asset/ticker matching for bundled brand marks, with no prefix matching.
- `Theme.swift`: adaptive gold palettes, appearance control, contrast-aware brand/commodity icons, sparkline and shared labels.

All feeds are contacted directly from iOS; there is no hosted backend. No background collection. Refresh on foreground, every five minutes while active, and user request. Persist latest successful snapshots and current chart points for immediate display; P2P storage contains only the latest value per direction. A fetch older than ten minutes or failed refresh is marked saved. No fake production values.

Offer books remain in memory for the sheet's lifetime. Failed refreshes retain the last successful book with a saved/error label. Successful empty responses replace old books and say only that the public source returned no offers. Reject mixed pairs, invalid prices/limits, sold-out quantities, duplicate IDs, and mismatched side responses. Never create advertisements from reference quotes or interpret an empty list as zero market liquidity. Payment identifiers are resolved using the public source's method catalog, with the identifier displayed if unavailable.

## Validation and delivery

Xcode project includes app, unit test and UI test targets and a shared Muyar scheme. Simulator testing is supplemented by an explicitly requested development-signed Release installation on the paired iPhone 15 Plus. Installation and launch were verified with devicectl. UI fixtures never affect the normal cache and are absent from Release. No App Store, TestFlight, analytics, notification, trading, or server provisioning work.

Known provider risk: Yahoo endpoints can change or be restricted, and P2P reference quotes do not establish current ad availability. Network restrictions can still prevent live refresh; the app shows a saved/error state. Later versions may add a licensed source/relay and locally stored P2P history.

`Package.swift` runs the same core tests on macOS independently of the simulator test daemon. Debug-only launch arguments can open a default instrument and chart range for live visual smoke checks; they do not change production behavior.
