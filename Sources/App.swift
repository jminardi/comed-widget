import SwiftUI

@main
struct ComEdApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 420, minHeight: 380)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var snapshot: PriceSnapshot = .placeholder
    @State private var loading = true

    var body: some View {
        VStack(spacing: 12) {
            Text("ComEd Hourly Pricing")
                .font(.title2.bold())
            if loading {
                ProgressView("Loading live prices…")
                    .frame(maxHeight: .infinity)
            } else {
                PriceWidgetView(snapshot: snapshot, hoursBack: 10, hoursFwd: 14)
                    .frame(minHeight: 300)
            }
            Text("Add the widget from Notification Center: click the date/time in the menu bar, scroll down, click \u{201C}Edit Widgets\u{201D}, and find \u{201C}ComEd Hourly Pricing\u{201D}.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Refresh") { Task { await load() } }
        }
        .padding()
        .task { await load() }
    }

    func load() async {
        loading = true
        snapshot = await ComEd.fetchSnapshot()
        loading = false
    }
}
