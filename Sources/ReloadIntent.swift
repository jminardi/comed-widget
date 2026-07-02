import AppIntents
import WidgetKit

/// Backs the widget's reload button. Interactive widgets (macOS 14+) can only
/// host `Button`/`Toggle` wired to an `AppIntent`; the tap wakes this intent in
/// the background and WidgetKit reloads the timeline once `perform()` returns.
/// The explicit `reloadTimelines` is belt-and-suspenders. Not discoverable, so
/// it never shows up as a Shortcuts action.
struct ReloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh ComEd price"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "ComEdWidget")
        return .result()
    }
}
