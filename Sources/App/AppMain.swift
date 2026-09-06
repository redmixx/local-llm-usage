import AppKit
import Charts
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

private let suiteName = "group.com.redmix.localllmusage"
private let stateKey = "usage-state-v1"
private let historyKey = "usage-history-v1"
private let endpointKey = "metrics-endpoint"
private let refreshIntervalKey = "refresh-interval"
private let menuDisplayKey = "menu-display"
private let historyRetentionKey = "history-retention-days"
private let languageKey = "app-language"
private let defaultEndpoint = "http://127.0.0.1:8000/metrics"

private let translations: [String: [String: String]] = [
    "pl": [
        "statistics": "Statystyki", "settings": "Ustawienia", "usage": "UŻYCIE", "performance": "WYDAJNOŚĆ",
        "month": "Ten miesiąc", "today": "Dzisiaj", "inputTokens": "Tokeny wejściowe", "outputTokens": "Tokeny wyjściowe",
        "menuInput": "Wejście", "menuOutput": "Wyjście", "menuTTFT": "TTFT", "menuAverage": "Średnia", "menuLive": "Na żywo", "menuUpdated": "Aktualizacja",
        "requests": "Żądania", "averageTTFT": "Średni TTFT", "averageGeneration": "Średnia generacja", "liveGeneration": "Generacja teraz",
        "lastUpdate": "Ostatnia aktualizacja", "refreshNow": "Odśwież", "settingsAndStats": "Otwórz panel…",
        "quit": "Zakończ", "windowTitle": "Local LLM Usage", "statsTitle": "Statystyki lokalnego modelu", "online": "Połączono", "offline": "Brak połączenia",
        "range": "Zakres", "hours24": "24 godziny", "days7": "7 dni", "days30": "30 dni", "days90": "90 dni",
        "tokens": "Tokeny", "generation": "Generacja", "tokensPerRequests": "Tokeny na zakończone żądania",
        "input": "Wejściowe", "output": "Wyjściowe", "historyInfo": "Historia wykresów jest zbierana od tej wersji aplikacji i pojawi się po kolejnych zakończonych żądaniach.",
        "connection": "Połączenie", "metricsEndpoint": "Endpoint metryk", "saveEndpoint": "Zapisz endpoint",
        "testConnection": "Testuj połączenie", "saved": "Zapisano", "checking": "Sprawdzanie…", "connected": "Połączono — HTTP 200",
        "invalidResponse": "Nieprawidłowa odpowiedź", "connectionError": "Błąd połączenia", "refreshAndMenu": "Odświeżanie i pasek menu",
        "refreshEvery": "Odświeżaj co", "oneSecond": "1 sekunda", "twoSeconds": "2 sekundy", "fiveSeconds": "5 sekund",
        "tenSeconds": "10 sekund", "thirtySeconds": "30 sekund", "menuValue": "Wartość na pasku", "allTokens": "Wszystkie tokeny",
        "history": "Historia", "keepFor": "Przechowuj dane przez", "historyPrivacy": "Historia jest zapisywana lokalnie po zakończeniu żądań. Nie zawiera treści promptów ani odpowiedzi.",
        "exportJSON": "Eksportuj JSON…", "resetStats": "Wyzeruj lokalne statystyki…", "startup": "Uruchamianie",
        "startupInfo": "Uruchamiaj aplikację automatycznie po zalogowaniu.", "launchAtLogin": "Uruchamiaj przy logowaniu", "startupError": "Nie udało się zmienić ustawienia uruchamiania.", "resetTitle": "Wyzerować statystyki?",
        "cancel": "Anuluj", "reset": "Wyzeruj", "resetMessage": "Usunie to lokalne sumy i historię wykresów. Nie wpłynie na vLLM ani inne aplikacje.",
        "language": "Język", "automatic": "Automatycznie", "polish": "Polski", "english": "English", "time": "Czas"
    ],
    "en": [
        "statistics": "Statistics", "settings": "Settings", "usage": "USAGE", "performance": "PERFORMANCE",
        "month": "This month", "today": "Today", "inputTokens": "Input tokens", "outputTokens": "Output tokens",
        "menuInput": "Input", "menuOutput": "Output", "menuTTFT": "TTFT", "menuAverage": "Average", "menuLive": "Live", "menuUpdated": "Updated",
        "requests": "Requests", "averageTTFT": "Average TTFT", "averageGeneration": "Average generation", "liveGeneration": "Live generation",
        "lastUpdate": "Last update", "refreshNow": "Refresh", "settingsAndStats": "Open Dashboard…",
        "quit": "Exit", "windowTitle": "Local LLM Usage", "statsTitle": "Local model statistics", "online": "Connected", "offline": "Offline",
        "range": "Range", "hours24": "24 hours", "days7": "7 days", "days30": "30 days", "days90": "90 days",
        "tokens": "Tokens", "generation": "Generation", "tokensPerRequests": "Tokens per completed requests",
        "input": "Input", "output": "Output", "historyInfo": "Chart history is collected from this app version and will appear after subsequent completed requests.",
        "connection": "Connection", "metricsEndpoint": "Metrics endpoint", "saveEndpoint": "Save endpoint",
        "testConnection": "Test connection", "saved": "Saved", "checking": "Checking…", "connected": "Connected — HTTP 200",
        "invalidResponse": "Invalid response", "connectionError": "Connection error", "refreshAndMenu": "Refresh and menu bar",
        "refreshEvery": "Refresh every", "oneSecond": "1 second", "twoSeconds": "2 seconds", "fiveSeconds": "5 seconds",
        "tenSeconds": "10 seconds", "thirtySeconds": "30 seconds", "menuValue": "Menu bar value", "allTokens": "All tokens",
        "history": "History", "keepFor": "Keep data for", "historyPrivacy": "History is stored locally after requests complete. It contains no prompt or response content.",
        "exportJSON": "Export JSON…", "resetStats": "Reset local statistics…", "startup": "Startup",
        "startupInfo": "Start the app automatically after signing in.", "launchAtLogin": "Launch at login", "startupError": "Could not change the startup setting.", "resetTitle": "Reset statistics?",
        "cancel": "Cancel", "reset": "Reset", "resetMessage": "This removes local totals and chart history. It does not affect vLLM or other applications.",
        "language": "Language", "automatic": "Automatic", "polish": "Polski", "english": "English", "time": "Time"
    ]
]

private func activeLanguage() -> String {
    let configured = defaults().string(forKey: languageKey) ?? "auto"
    if configured == "pl" || configured == "en" { return configured }
    return Locale.current.language.languageCode?.identifier == "pl" ? "pl" : "en"
}

private func localized(_ key: String) -> String {
    translations[activeLanguage()]?[key] ?? translations["en"]?[key] ?? key
}

extension Notification.Name {
    static let usageSettingsChanged = Notification.Name("usageSettingsChanged")
    static let usageResetRequested = Notification.Name("usageResetRequested")
}

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
    var liveGenerationSpeed: Double?
    var online = false
    var modelName = "Local model"
}

struct UsageHistoryPoint: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let promptTokens: Double
    let generationTokens: Double
    let requests: Double
    let averageTTFT: Double
    let generationSpeed: Double
}

private func loadHistory() -> [UsageHistoryPoint] {
    guard let data = defaults().data(forKey: historyKey),
          let history = try? JSONDecoder().decode([UsageHistoryPoint].self, from: data) else { return [] }
    return history
}

private func saveHistory(_ history: [UsageHistoryPoint]) {
    if let data = try? JSONEncoder().encode(history) {
        defaults().set(data, forKey: historyKey)
    }
}

private struct MetricsSnapshot {
    var prompt = 0.0
    var generation = 0.0
    var requests = 0.0
    var ttftSum = 0.0
    var ttftCount = 0.0
    var decodeSeconds = 0.0
    var promptCreated: Date?
    var modelName = "Local model"
}

private func metricValue(_ line: Substring) -> Double? {
    guard let raw = line.split(separator: " ").last else { return nil }
    return Double(raw)
}

private func parseMetrics(_ text: String) -> MetricsSnapshot {
    var snapshot = MetricsSnapshot()
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        if line.hasPrefix("vllm:prompt_tokens_total{") {
            snapshot.prompt += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:generation_tokens_total{") {
            snapshot.generation += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:request_success_total{") {
            snapshot.requests += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:time_to_first_token_seconds_sum{") {
            snapshot.ttftSum += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:time_to_first_token_seconds_count{") {
            snapshot.ttftCount += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:request_decode_time_seconds_sum{") {
            snapshot.decodeSeconds += metricValue(line) ?? 0
        } else if line.hasPrefix("vllm:prompt_tokens_created{") {
            if let seconds = metricValue(line) { snapshot.promptCreated = Date(timeIntervalSince1970: seconds) }
        }
        if snapshot.modelName == "Local model",
           let range = line.range(of: "model_name=\"") {
            let remainder = line[range.upperBound...]
            if let end = remainder.firstIndex(of: "\"") {
                snapshot.modelName = String(remainder[..<end])
            }
        }
    }
    return snapshot
}

private func counterDelta(_ current: Double, _ previous: Double?) -> Double {
    guard let previous else { return current }
    return current >= previous ? current - previous : current
}

private func compact(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}

private func friendlyModelName(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("deepseek-v4-flash") { return "DeepSeek v4 Flash Vision" }
    if lower.contains("glm-5.3-flash") { return "GLM 5.3 Flash" }
    return raw.replacingOccurrences(of: "-", with: " ")
}

private func defaults() -> UserDefaults {
    UserDefaults(suiteName: suiteName) ?? .standard
}

private enum LaunchAtLoginManager {
    static let label = "com.redmix.localllmusage"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ enabled: Bool) throws {
        let domain = "gui/\(getuid())"
        if enabled {
            let payload: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-gj", Bundle.main.bundlePath],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
            runLaunchctl(["bootstrap", domain, plistURL.path])
        } else {
            runLaunchctl(["bootout", domain, plistURL.path])
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

@MainActor
private final class MetricMenuRow: NSView {
    private let nameField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: 25))
        nameField.font = .systemFont(ofSize: 13)
        nameField.textColor = .secondaryLabelColor
        valueField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueField.textColor = .labelColor
        valueField.alignment = .right
        nameField.translatesAutoresizingMaskIntoConstraints = false
        valueField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)
        addSubview(valueField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 16),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(name: String, value: String, accent: Bool = false) {
        nameField.stringValue = name
        valueField.stringValue = value
        valueField.textColor = .labelColor
    }
}

@MainActor
private final class MenuSectionRow: NSView {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: 23))
        let field = NSTextField(labelWithString: title.uppercased())
        field.font = .systemFont(ofSize: 10, weight: .semibold)
        field.textColor = .tertiaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class ModelMenuHeader: NSView {
    private let dot = NSTextField(labelWithString: "●")
    private let modelField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: 43))
        dot.font = .systemFont(ofSize: 13, weight: .bold)
        modelField.font = .systemFont(ofSize: 13, weight: .semibold)
        modelField.textColor = .labelColor
        modelField.lineBreakMode = .byTruncatingTail
        statusField.font = .systemFont(ofSize: 10)
        statusField.textColor = .secondaryLabelColor
        [dot, modelField, statusField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: modelField.centerYAnchor),
            modelField.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            modelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            modelField.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            statusField.leadingAnchor.constraint(equalTo: modelField.leadingAnchor),
            statusField.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(model: String, online: Bool) {
        dot.textColor = online ? .systemGreen : .systemRed
        modelField.stringValue = model
        statusField.stringValue = localized(online ? "online" : "offline")
    }
}

private final class AppDelegateReference: @unchecked Sendable {
    weak var value: AppDelegate?
    init(_ value: AppDelegate) { self.value = value }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var modelHeader: ModelMenuHeader!
    private var valueRows: [String: MetricMenuRow] = [:]
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var state = UsageState()
    private var polling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = defaults().data(forKey: stateKey),
           let saved = try? JSONDecoder().decode(UsageState.self, from: data) {
            state = saved
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Local LLM usage")
        statusItem.button?.imagePosition = .imageLeading
        buildMenu()
        refreshDisplay()
        poll()
        scheduleRefreshTimer()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .usageSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetUsage), name: .usageResetRequested, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func scheduleRefreshTimer() {
        timer?.invalidate()
        let configured = defaults().double(forKey: refreshIntervalKey)
        let interval = configured > 0 ? max(1, min(configured, 60)) : 2
        let refreshTimer = Timer(timeInterval: interval, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: true)
        timer = refreshTimer
        // NSMenu runs the main run loop in event-tracking mode while it is open.
        // A common-mode timer continues firing, so values update live in the menu.
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    private func poll() {
        guard !polling else { return }
        let configuredEndpoint = defaults().string(forKey: endpointKey) ?? defaultEndpoint
        guard let endpoint = URL(string: configuredEndpoint),
              let scheme = endpoint.scheme, ["http", "https"].contains(scheme),
              endpoint.host != nil else {
            state.online = false
            persistAndRefresh()
            return
        }
        polling = true
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        let reference = AppDelegateReference(self)
        URLSession.shared.dataTask(with: request) { data, _, error in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            let succeeded = error == nil
            Task { @MainActor in
                guard let self = reference.value else { return }
                defer { self.polling = false }
                guard succeeded, let text else {
                    self.state.online = false
                    self.persistAndRefresh()
                    return
                }
                self.ingest(parseMetrics(text))
            }
        }.resume()
    }

    private func ingest(_ snapshot: MetricsSnapshot) {
        let now = Date()
        let sampleDuration = max(now.timeIntervalSince(state.lastUpdated ?? now), 0.001)
        let calendar = Calendar.current
        let month = String(format: "%04d-%02d", calendar.component(.year, from: now), calendar.component(.month, from: now))
        let day = String(format: "%@-%02d", month, calendar.component(.day, from: now))
        let isFirstSample = state.lastPrompt == nil

        if state.monthKey != month {
            state.monthKey = month
            state.monthPrompt = 0
            state.monthGeneration = 0
            state.monthRequests = 0
            state.monthTTFTSum = 0
            state.monthTTFTCount = 0
            state.monthDecodeSeconds = 0
        }
        if state.dayKey != day {
            state.dayKey = day
            state.dayPrompt = 0
            state.dayGeneration = 0
            state.dayRequests = 0
        }

        var promptDelta = counterDelta(snapshot.prompt, state.lastPrompt)
        var generationDelta = counterDelta(snapshot.generation, state.lastGeneration)
        var requestsDelta = counterDelta(snapshot.requests, state.lastRequests)
        var ttftSumDelta = counterDelta(snapshot.ttftSum, state.lastTTFTSum)
        var ttftCountDelta = counterDelta(snapshot.ttftCount, state.lastTTFTCount)
        var decodeDelta = counterDelta(snapshot.decodeSeconds, state.lastDecodeSeconds)

        // On the first sample, count existing counters only when this vLLM
        // instance started during the current month. Otherwise historical
        // counters cannot be split reliably across calendar months.
        if isFirstSample, let created = snapshot.promptCreated,
           !calendar.isDate(created, equalTo: now, toGranularity: .month) {
            promptDelta = 0
            generationDelta = 0
            requestsDelta = 0
            ttftSumDelta = 0
            ttftCountDelta = 0
            decodeDelta = 0
        }

        state.monthPrompt += promptDelta
        state.monthGeneration += generationDelta
        state.monthRequests += requestsDelta
        state.monthTTFTSum += ttftSumDelta
        state.monthTTFTCount += ttftCountDelta
        state.monthDecodeSeconds += decodeDelta
        state.dayPrompt += promptDelta
        state.dayGeneration += generationDelta
        state.dayRequests += requestsDelta
        state.lastPrompt = snapshot.prompt
        state.lastGeneration = snapshot.generation
        state.lastRequests = snapshot.requests
        state.lastTTFTSum = snapshot.ttftSum
        state.lastTTFTCount = snapshot.ttftCount
        state.lastDecodeSeconds = snapshot.decodeSeconds
        state.liveGenerationSpeed = !isFirstSample && generationDelta > 0 ? generationDelta / sampleDuration : 0
        state.lastUpdated = now
        state.online = true
        state.modelName = snapshot.modelName
        if requestsDelta > 0 || loadHistory().isEmpty {
            recordHistory(promptDelta: promptDelta, generationDelta: generationDelta, requestsDelta: requestsDelta)
        }
        persistAndRefresh()
    }

    private func recordHistory(promptDelta: Double, generationDelta: Double, requestsDelta: Double) {
        let ttft = state.monthTTFTCount > 0 ? state.monthTTFTSum / state.monthTTFTCount : 0
        let speed = state.monthDecodeSeconds > 0 ? state.monthGeneration / state.monthDecodeSeconds : 0
        var history = loadHistory()
        history.append(UsageHistoryPoint(
            timestamp: Date(),
            promptTokens: max(0, promptDelta),
            generationTokens: max(0, generationDelta),
            requests: max(0, requestsDelta),
            averageTTFT: ttft,
            generationSpeed: speed
        ))
        let configuredDays = defaults().integer(forKey: historyRetentionKey)
        let retentionDays = configuredDays > 0 ? configuredDays : 30
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        history.removeAll { $0.timestamp < cutoff }
        saveHistory(history)
    }

    private func persistAndRefresh() {
        if let data = try? JSONEncoder().encode(state) {
            defaults().set(data, forKey: stateKey)
            defaults().synchronize()
        }
        refreshDisplay()
        WidgetCenter.shared.reloadTimelines(ofKind: "LocalLLMUsageWidget")
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 304
        valueRows.removeAll()

        modelHeader = ModelMenuHeader()
        addCustomView(modelHeader, to: menu)
        menu.addItem(.separator())
        addSection(menu, localized("usage"))
        addValue(menu, "month")
        addValue(menu, "today")
        addValue(menu, "menuInput")
        addValue(menu, "menuOutput")
        addValue(menu, "requests")
        menu.addItem(.separator())
        addSection(menu, localized("performance"))
        addValue(menu, "menuLive")
        addValue(menu, "menuAverage")
        addValue(menu, "menuTTFT")
        menu.addItem(.separator())
        addValue(menu, "menuUpdated")
        let refresh = NSMenuItem(title: localized("refreshNow"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refresh)
        let settings = NSMenuItem(title: localized("settingsAndStats"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: nil)
        menu.addItem(settings)
        let quit = NSMenuItem(title: localized("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func refreshDisplay() {
        let monthTotal = state.monthPrompt + state.monthGeneration
        let displayMode = defaults().string(forKey: menuDisplayKey) ?? "total"
        let displayedValue: Double
        switch displayMode {
        case "prompt": displayedValue = state.monthPrompt
        case "generation": displayedValue = state.monthGeneration
        default: displayedValue = monthTotal
        }
        statusItem.button?.title = state.online ? " " + compact(displayedValue) + " tok" : " offline"
        statusItem.button?.contentTintColor = state.online ? nil : .systemRed

        let displayName = friendlyModelName(state.modelName)
        modelHeader.update(model: displayName, online: state.online)
        setValue("month", compact(monthTotal))
        setValue("today", compact(state.dayPrompt + state.dayGeneration))
        setValue("menuInput", compact(state.monthPrompt))
        setValue("menuOutput", compact(state.monthGeneration))
        setValue("requests", compact(state.monthRequests))
        let ttft = state.monthTTFTCount > 0 ? state.monthTTFTSum / state.monthTTFTCount : 0
        setValue("menuTTFT", String(format: "%.2f s", ttft))
        let speed = state.monthDecodeSeconds > 0 ? state.monthGeneration / state.monthDecodeSeconds : 0
        setValue("menuAverage", String(format: "%.1f tok/s", speed))
        setValue("menuLive", state.online ? String(format: "%.1f tok/s", state.liveGenerationSpeed ?? 0) : "—", accent: (state.liveGenerationSpeed ?? 0) > 0)
        let refreshed = state.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "—"
        setValue("menuUpdated", refreshed)
    }

    private func addCustomView(_ view: NSView, to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        menu.addItem(item)
    }

    private func addValue(_ menu: NSMenu, _ key: String) {
        let row = MetricMenuRow()
        valueRows[key] = row
        addCustomView(row, to: menu)
    }

    private func setValue(_ key: String, _ value: String, accent: Bool = false) {
        valueRows[key]?.update(name: localized(key), value: value, accent: accent)
    }

    private func addSection(_ menu: NSMenu, _ text: String) {
        addCustomView(MenuSectionRow(title: text), to: menu)
    }

    @objc private func refreshNow() { poll() }
    @objc private func timerDidFire() { poll() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func settingsChanged() {
        scheduleRefreshTimer()
        buildMenu()
        refreshDisplay()
        settingsWindow?.title = localized("windowTitle")
    }

    @objc private func resetUsage() {
        state.monthPrompt = 0
        state.monthGeneration = 0
        state.monthRequests = 0
        state.monthTTFTSum = 0
        state.monthTTFTCount = 0
        state.monthDecodeSeconds = 0
        state.dayPrompt = 0
        state.dayGeneration = 0
        state.dayRequests = 0
        saveHistory([])
        persistAndRefresh()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("windowTitle")
            window.minSize = NSSize(width: 720, height: 600)
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsDashboardView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh immediately on open instead of waiting for the next timer tick.
        poll()
    }
}

private func loadUsageState() -> UsageState {
    guard let data = defaults().data(forKey: stateKey),
          let state = try? JSONDecoder().decode(UsageState.self, from: data) else { return UsageState() }
    return state
}

private struct SettingsDashboardView: View {
    @AppStorage(languageKey, store: defaults()) private var appLanguage = "auto"

    var body: some View {
        TabView {
            StatisticsView()
                .tabItem { Label(localized("statistics"), systemImage: "chart.xyaxis.line") }
            GeneralSettingsView()
                .tabItem { Label(localized("settings"), systemImage: "gearshape") }
        }
        .id(appLanguage)
        .padding(16)
        .frame(minWidth: 720, minHeight: 600)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(endpointKey, store: defaults()) private var storedEndpoint = defaultEndpoint
    @AppStorage(refreshIntervalKey, store: defaults()) private var refreshInterval = 2.0
    @AppStorage(menuDisplayKey, store: defaults()) private var menuDisplay = "total"
    @AppStorage(historyRetentionKey, store: defaults()) private var retentionDays = 30
    @AppStorage(languageKey, store: defaults()) private var appLanguage = "auto"
    @State private var endpointDraft = defaultEndpoint
    @State private var connectionStatus = ""
    @State private var connectionSucceeded = false
    @State private var showResetConfirmation = false
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var startupStatus = ""

    var body: some View {
        Form {
            Section(localized("language")) {
                Picker(localized("language"), selection: $appLanguage) {
                    Text(localized("automatic")).tag("auto")
                    Text(localized("polish")).tag("pl")
                    Text(localized("english")).tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section(localized("connection")) {
                TextField(localized("metricsEndpoint"), text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(localized("saveEndpoint")) { saveEndpoint() }
                        .disabled(!isValidEndpoint)
                    Button(localized("testConnection")) { testConnection() }
                        .disabled(!isValidEndpoint)
                    Text(connectionStatus)
                        .foregroundStyle(connectionSucceeded ? .green : .secondary)
                }
            }

            Section(localized("refreshAndMenu")) {
                Picker(localized("refreshEvery"), selection: $refreshInterval) {
                    Text(localized("oneSecond")).tag(1.0)
                    Text(localized("twoSeconds")).tag(2.0)
                    Text(localized("fiveSeconds")).tag(5.0)
                    Text(localized("tenSeconds")).tag(10.0)
                    Text(localized("thirtySeconds")).tag(30.0)
                }
                Picker(localized("menuValue"), selection: $menuDisplay) {
                    Text(localized("allTokens")).tag("total")
                    Text(localized("inputTokens")).tag("prompt")
                    Text(localized("outputTokens")).tag("generation")
                }
            }

            Section(localized("history")) {
                Picker(localized("keepFor"), selection: $retentionDays) {
                    Text(localized("days7")).tag(7)
                    Text(localized("days30")).tag(30)
                    Text(localized("days90")).tag(90)
                }
                Text(localized("historyPrivacy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(localized("exportJSON")) { exportHistory() }
                    Button(localized("resetStats"), role: .destructive) { showResetConfirmation = true }
                }
            }

            Section(localized("startup")) {
                Toggle(localized("launchAtLogin"), isOn: $launchAtLogin)
                Text(startupStatus.isEmpty ? localized("startupInfo") : startupStatus)
                    .font(.caption)
                    .foregroundStyle(startupStatus.isEmpty ? Color.secondary : Color.red)
            }
        }
        .formStyle(.grouped)
        .onAppear { endpointDraft = storedEndpoint }
        .onChange(of: refreshInterval) { _, _ in notifySettingsChanged() }
        .onChange(of: menuDisplay) { _, _ in notifySettingsChanged() }
        .onChange(of: retentionDays) { _, _ in notifySettingsChanged() }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                try LaunchAtLoginManager.setEnabled(enabled)
                startupStatus = ""
            } catch {
                startupStatus = localized("startupError")
                launchAtLogin = LaunchAtLoginManager.isEnabled
            }
        }
        .onChange(of: appLanguage) { _, _ in
            connectionStatus = ""
            notifySettingsChanged()
        }
        .alert(localized("resetTitle"), isPresented: $showResetConfirmation) {
            Button(localized("cancel"), role: .cancel) {}
            Button(localized("reset"), role: .destructive) {
                NotificationCenter.default.post(name: .usageResetRequested, object: nil)
            }
        } message: {
            Text(localized("resetMessage"))
        }
    }

    private var isValidEndpoint: Bool {
        guard let url = URL(string: endpointDraft),
              let scheme = url.scheme, ["http", "https"].contains(scheme) else { return false }
        return url.host != nil
    }

    private func saveEndpoint() {
        guard isValidEndpoint else { return }
        storedEndpoint = endpointDraft
        connectionStatus = localized("saved")
        connectionSucceeded = true
        notifySettingsChanged()
    }

    private func testConnection() {
        guard let url = URL(string: endpointDraft), isValidEndpoint else { return }
        connectionStatus = localized("checking")
        connectionSucceeded = false
        Task {
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
                request.httpMethod = "GET"
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: data.prefix(4096), encoding: .utf8) ?? ""
                connectionSucceeded = status == 200 && body.contains("vllm:")
                connectionStatus = connectionSucceeded ? localized("connected") : "\(localized("invalidResponse")) (HTTP \(status))"
            } catch {
                connectionSucceeded = false
                connectionStatus = localized("connectionError")
            }
        }
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .usageSettingsChanged, object: nil)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "local-llm-usage-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONEncoder.pretty.encode(loadHistory()) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private struct StatisticsView: View {
    @State private var state = loadUsageState()
    @State private var history = loadHistory()
    @State private var rangeDays = 7
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var filteredHistory: [UsageHistoryPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? .distantPast
        return history.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("statsTitle"))
                                .font(.title2.bold())
                            Text(friendlyModelName(state.modelName))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(localized(state.online ? "online" : "offline"), systemImage: state.online ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(state.online ? Color.green : Color.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((state.online ? Color.green : Color.red).opacity(0.10), in: Capsule())
                    }
                    HStack {
                        Text(localized("range"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker(localized("range"), selection: $rangeDays) {
                            Text(localized("hours24")).tag(1)
                            Text(localized("days7")).tag(7)
                            Text(localized("days30")).tag(30)
                            Text(localized("days90")).tag(90)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 380)
                        Spacer()
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    summaryCard(localized("month"), compact(state.monthPrompt + state.monthGeneration), "calendar")
                    summaryCard(localized("today"), compact(state.dayPrompt + state.dayGeneration), "sun.max")
                    summaryCard(localized("requests"), compact(state.monthRequests), "arrow.up.arrow.down")
                    let ttft = state.monthTTFTCount > 0 ? state.monthTTFTSum / state.monthTTFTCount : 0
                    summaryCard(localized("averageTTFT"), String(format: "%.2f s", ttft), "timer")
                    let speed = state.monthDecodeSeconds > 0 ? state.monthGeneration / state.monthDecodeSeconds : 0
                    summaryCard(localized("generation"), String(format: "%.1f tok/s", speed), "bolt.fill")
                    summaryCard(localized("liveGeneration"), String(format: "%.1f tok/s", state.liveGenerationSpeed ?? 0), "waveform.path.ecg", accent: (state.liveGenerationSpeed ?? 0) > 0)
                }

                chartPanel(localized("tokensPerRequests")) {
                    Chart(filteredHistory) { point in
                        BarMark(x: .value(localized("time"), point.timestamp), y: .value(localized("tokens"), point.promptTokens))
                            .foregroundStyle(by: .value("Type", localized("input")))
                        BarMark(x: .value(localized("time"), point.timestamp), y: .value(localized("tokens"), point.generationTokens))
                            .foregroundStyle(by: .value("Type", localized("output")))
                    }
                    .chartForegroundStyleScale([localized("input"): Color.blue, localized("output"): Color.purple])
                }

                HStack(spacing: 12) {
                    chartPanel(localized("averageTTFT")) {
                        Chart(filteredHistory) { point in
                            LineMark(x: .value(localized("time"), point.timestamp), y: .value("s", point.averageTTFT))
                                .foregroundStyle(.orange)
                            PointMark(x: .value(localized("time"), point.timestamp), y: .value("s", point.averageTTFT))
                                .foregroundStyle(.orange)
                        }
                    }
                    chartPanel(localized("averageGeneration")) {
                        Chart(filteredHistory) { point in
                            LineMark(x: .value(localized("time"), point.timestamp), y: .value("tok/s", point.generationSpeed))
                                .foregroundStyle(.green)
                            PointMark(x: .value(localized("time"), point.timestamp), y: .value("tok/s", point.generationSpeed))
                                .foregroundStyle(.green)
                        }
                    }
                }

                if filteredHistory.count < 2 {
                    Label(localized("historyInfo"), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
        .onReceive(refresh) { _ in
            state = loadUsageState()
            history = loadHistory()
        }
    }

    private func summaryCard(_ title: String, _ value: String, _ symbol: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(accent ? Color.green : Color.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent ? Color.green.opacity(0.10) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chartPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().frame(minHeight: 155)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.10)))
    }
}

@main
struct LocalLLMUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
