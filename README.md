> ## ⚠️ Vibe-coded warning
> **This project was entirely written by an AI agent (Claude) in one session,
> with no human code review.** It works on the author's machine. Read the code
> before you trust it, and expect rough edges.

# ComEd Hourly Pricing — macOS Widget

A macOS Notification Center / desktop widget showing live **ComEd Hourly Pricing**
(Chicago, IL residential real-time rate). Shows the current-hour price as a large
color-coded numeral plus a Swift Charts bar chart of recent actual hourly averages
and the day-ahead forecast, with a "now" marker.

Data comes straight from `hourlypricing.comed.com`. Prices are cents/kWh, one
decimal, all times in `America/Chicago`.

## What it looks like

- **Headline**: current price, e.g. `6.0¢` — green `<5¢`, orange `5–10¢`, red `>10¢`.
- **Chart**: solid bars = actual settled hourly averages; faded bars = day-ahead
  forecast; dashed vertical line = the current hour.
- **Families**: small (just the number), medium (~6h back / 8h forward),
  large (~10h back / 14h forward).
- Refreshes on the widget timeline roughly every 15 minutes.

## Build from scratch (no Xcode required)

Requirements: macOS 14+ and the Command Line Tools (`swiftc` / `xcrun`).
`xcodebuild` is *not* used. The script builds for your machine's native
architecture (Apple Silicon or Intel) against whatever macOS SDK
`xcrun --show-sdk-path` returns (override with `SDK=/path/to/MacOSX.sdk`).

```sh
./build.sh
```

This compiles both binaries with `swiftc`, hand-assembles the
`.app` / `.appex` bundle, ad-hoc codesigns (`codesign -s -`), installs to
`/Applications/ComEdPrices.app` (or `~/Applications` if `/Applications` isn't
writable), registers with LaunchServices, and launches the host app once so the
widget extension registers.

## Add the widget to the sidebar

1. Click the date/time in the menu bar to open Notification Center.
2. Scroll to the bottom, click **Edit Widgets**.
3. Find **ComEd Hourly Pricing**, and drag your preferred size onto the sidebar.

(You can also right-click the desktop → **Edit Widgets** to place it there.)

If it doesn't appear immediately, run `killall chronod && killall
NotificationCenter` (build.sh does this for you) and reopen the gallery.

## Layout / architecture notes

The appex uses the classic **NSExtension** layout under `Contents/PlugIns/` —
the same layout every working third-party widget on macOS 15 uses (Todoist,
Edge, and most Apple apps):

```
ComEdPrices.app/
  Contents/
    MacOS/ComEdPrices              # host SwiftUI app
    Info.plist                     # CFBundlePackageType APPL
    PlugIns/
      ComEdWidget.appex/
        Contents/
          MacOS/ComEdWidget        # WidgetBundle, built -parse-as-library
          Info.plist               # CFBundlePackageType XPC!, NSExtension dict
```

The appex `Info.plist` declares:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.widgetkit-extension</string>
</dict>
```

Two hard-won gotchas for building this without Xcode:

1. **The appex binary must be linked with `-e _NSExtensionMain`**
   (`-Xlinker -e -Xlinker _NSExtensionMain`) — the entry point Xcode uses for
   appex binaries. Foundation's `NSExtensionMain` performs the extension-host
   check-in and services XPC requests forever. With the default
   `@main`-synthesized entry, WidgetKit's runtime exits(0) ~30 ms after launch,
   before answering chronod's `getAllDescriptors`; chronod logs
   `NSCocoaErrorDomain Code=4099 connection invalidated` and the widget stays
   registered (pluginkit) but invisible in the gallery.
2. The ExtensionKit-style layout (`Contents/Extensions/` +
   `EXAppExtensionAttributes`) also registers with pluginkit but fails the same
   way for hand-assembled ad-hoc-signed bundles; the classic layout works.

No principal class is set; WidgetKit finds `@main struct ComEdWidgetBundle:
WidgetBundle` via runtime metadata. Both binaries target
`<native-arch>-apple-macosx14.0` against the toolchain's macOS SDK and link
SwiftUI / WidgetKit / Charts implicitly.

Both bundles are ad-hoc signed with the sandbox + network-client entitlements
(the appex is signed before the app).

Source files (`Sources/`):

- `ComEdData.swift` — model, timezone helpers, all feed fetching + Highcharts
  parsing + the actual/predicted merge logic.
- `PriceChartView.swift` — shared Swift Charts view and the headline+chart layout.
- `Widget.swift` — `TimelineProvider`, `Widget`, `@main WidgetBundle`.
- `App.swift` — minimal `@main` host app that shows the same chart in a window.

## Verify registration

```sh
pluginkit -mv -p com.apple.widgetkit-extension | grep -i comed
codesign --verify --strict --verbose=2 /Applications/ComEdPrices.app/Contents/PlugIns/ComEdWidget.appex
# Definitive gallery check — chronod extracted the widget descriptors:
/usr/bin/log show --last 10m --info --predicate 'process == "chronod"' \
  | grep -E "comed.*(query returned|Found:)"
```

## Data feeds used

| Purpose | URL |
|---|---|
| Current hour average | `.../api?type=currenthouraverage` |
| Today's hourly actuals | `.../api?type=day` |
| 5-minute feed (fallback bucketing) | `.../api?type=5minutefeed` |
| Day-ahead forecast | `.../rrtp/ServletFeed?type=daynexttoday&date=YYYYMMDD` |

The `type=day` / `daynexttoday` feeds return Highcharts-style
`[[Date.UTC(Y,M0,D,H,0,0), price], ...]` text (month 0-indexed; the H is a Central
*wall-clock* hour). It's parsed with a regex, never eval'd. Tomorrow's forecast is
only published after ~4:30pm CT and is handled gracefully when empty.

## Troubleshooting

- Not in gallery: `killall chronod && killall NotificationCenter` — chronod is
  the WidgetKit daemon that populates the gallery; pluginkit registration alone
  proves nothing about gallery visibility. Then reopen Edit Widgets.
- Not registered: rerun `./build.sh`, or force-register:
  `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/ComEdPrices.app`
- Check logs (use the absolute path if your shell shadows `log`):
  `/usr/bin/log show --last 5m --info --predicate 'process == "chronod"' | grep -i comed`
  Healthy: `query returned 1 descriptors` and
  `Found: <CHSWidgetDescriptor ... kind: ComEdWidget ...>`.
  `Code=4099 connection invalidated` = the appex died before answering; check
  the `-e _NSExtensionMain` entry-point linkage (gotcha #1 above).
