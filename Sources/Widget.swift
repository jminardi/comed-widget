import WidgetKit
import SwiftUI

struct PriceEntry: TimelineEntry {
    let date: Date
    let snapshot: PriceSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
        if context.isPreview {
            completion(PriceEntry(date: Date(), snapshot: .placeholder))
            return
        }
        Task {
            let snap = await ComEd.fetchSnapshot()
            completion(PriceEntry(date: Date(), snapshot: snap))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
        Task {
            let snap = await ComEd.fetchSnapshot()
            let entry = PriceEntry(date: Date(), snapshot: snap)
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct ComEdWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        let snap = entry.snapshot
        Group {
            switch family {
            case .systemSmall:
                PriceWidgetView(snapshot: snap, hoursBack: 0, hoursFwd: 0, compact: true)
            case .systemLarge:
                PriceWidgetView(snapshot: snap, hoursBack: 10, hoursFwd: 14, showReload: true)
            default: // systemMedium
                PriceWidgetView(snapshot: snap, hoursBack: 6, hoursFwd: 8, showReload: true)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ComEdWidget: Widget {
    let kind = "ComEdWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ComEdWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ComEd Hourly Pricing")
        .description("Live Chicago ComEd hourly electricity price with recent actuals and day-ahead forecast.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ComEdWidgetBundle: WidgetBundle {
    var body: some Widget {
        ComEdWidget()
    }
}
