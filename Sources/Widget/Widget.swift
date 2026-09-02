import SwiftUI
import WidgetKit

private let suiteName = "group.com.redmix.localllmusage"
private let stateKey = "usage-state-v1"

struct UsageState: Codable {
    var monthKey = ""
    var dayKey = ""
    var monthPrompt = 0.0
    var monthGeneration = 0.0
    var monthRequests = 0.0
    var monthTTFTSum = 0.0
    var monthTTFTCount = 0.0
    var monthDecodeSeconds = 0.0
    var dayPrompt = 0.0
    var dayGeneration = 0.0
    var dayRequests = 0.0
    var lastPrompt: Double?
    var lastGeneration: Double?
    var lastRequests: Double?
    var lastTTFTSum: Double?
    var lastTTFTCount: Double?
    var lastDecodeSeconds: Double?
    var lastUpdated: Date?
    var online = false
    var modelName = "Local model"
}

private func loadState() -> UsageState {
    let store = UserDefaults(suiteName: suiteName) ?? .standard
    guard let data = store.data(forKey: stateKey),
          let state = try? JSONDecoder().decode(UsageState.self, from: data) else {
        return UsageState()
    }
    return state
}

private func compact(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: UsageState
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), state: UsageState()) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), state: loadState()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), state: loadState())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        let state = entry.state
        let total = state.monthPrompt + state.monthGeneration
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(state.online ? .green : .red)
                Text("Local LLM")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(state.online ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
            }
            Text(compact(total))
                .font(.system(size: family == .systemSmall ? 28 : 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
            Text("tokenów w tym miesiącu")
                .font(.caption)
                .foregroundStyle(.secondary)
            if family != .systemSmall {
                HStack(spacing: 18) {
                    stat("WEJŚCIE", compact(state.monthPrompt))
                    stat("WYJŚCIE", compact(state.monthGeneration))
                    stat("ŻĄDANIA", compact(state.monthRequests))
                }
            } else {
                Text("Dziś: \(compact(state.dayPrompt + state.dayGeneration))")
                    .font(.caption2)
            }
            Spacer(minLength: 0)
            if let updated = state.lastUpdated {
                Text("Aktualizacja \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.blue.opacity(0.20), Color.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
    }
}

@main
struct LocalLLMUsageWidget: Widget {
    let kind = "LocalLLMUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Local LLM Usage")
        .description("Łączne użycie tokenów przez wszystkie aplikacje korzystające z lokalnego modelu.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
