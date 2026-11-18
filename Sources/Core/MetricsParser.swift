import Foundation

// Testable, UI-independent parsing of vLLM / TensorFold Prometheus metrics.
// Compiled together with the app target (swiftc accepts multiple inputs),
// so no module/framework wiring is required.

public struct MetricsSnapshot {
    public var prompt = 0.0
    public var generation = 0.0
    public var requests = 0.0
    public var ttftSum = 0.0
    public var ttftCount = 0.0
    public var decodeSeconds = 0.0
    public var promptCreated: Date?
    public var modelName = "Local model"

    public init() {}
}

// Prometheus text exposition format is:
//
//     metric_name{label="value",other="value"} <number> [<timestamp_ms>]
//
// The name never contains a space or a brace, but label values may contain
// spaces, so the numeric value has to be located from the right-hand side.
public func metricName(_ line: Substring) -> Substring? {
    let name = line.prefix { $0 != " " && $0 != "{" }
    return name.isEmpty ? nil : name
}

public func metricValue(_ line: Substring) -> Double? {
    var fields = line.split(separator: " ")
    guard fields.count >= 2 else { return nil }
    // Drop an optional trailing millisecond timestamp (integer epoch ms).
    if fields.count >= 3, let last = fields.last, let stamp = Double(last),
       stamp.rounded() == stamp, stamp >= 1_000_000_000_000 {
        fields.removeLast()
    }
    guard let raw = fields.last, let value = Double(raw), value.isFinite else { return nil }
    return value
}

// Both vLLM ("vllm:name") and TensorFold ("tensorfold:name") prefix their
// metrics. Older TensorFold builds used an underscore instead of a colon, and
// a few metric names differ between the two, so names are normalised to a
// single canonical vocabulary before matching.
public func canonicalMetricName(_ raw: Substring) -> String {
    var name = String(raw)
    for prefix in ["vllm:", "vllm_", "tensorfold:", "tensorfold_"] where name.hasPrefix(prefix) {
        name = String(name.dropFirst(prefix.count))
        break
    }
    switch name {
    case "completion_tokens_total":
        return "generation_tokens_total"
    case "requests_total":
        return "request_success_total"
    case "request_latency_seconds_count":
        // TensorFold exposes no request counter; the latency histogram's
        // sample count is the number of completed requests.
        return "request_success_total"
    case "prefill_seconds_total":
        return "time_to_first_token_seconds_sum"
    case "decode_seconds_total":
        return "request_decode_time_seconds_sum"
    default:
        return name
    }
}

public func parseMetrics(_ text: String) -> MetricsSnapshot {
    var snapshot = MetricsSnapshot()
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        if snapshot.modelName == "Local model",
           let range = line.range(of: "model_name=\"") {
            let remainder = line[range.upperBound...]
            if let end = remainder.firstIndex(of: "\"") {
                snapshot.modelName = String(remainder[..<end])
            }
        }
        guard let rawName = metricName(line) else { continue }
        switch canonicalMetricName(rawName) {
        case "prompt_tokens_total":
            snapshot.prompt += metricValue(line) ?? 0
        case "generation_tokens_total":
            snapshot.generation += metricValue(line) ?? 0
        case "request_success_total":
            snapshot.requests += metricValue(line) ?? 0
        case "time_to_first_token_seconds_sum":
            snapshot.ttftSum += metricValue(line) ?? 0
        case "time_to_first_token_seconds_count":
            snapshot.ttftCount += metricValue(line) ?? 0
        case "request_decode_time_seconds_sum":
            snapshot.decodeSeconds += metricValue(line) ?? 0
        case "prompt_tokens_created":
            if let seconds = metricValue(line) {
                snapshot.promptCreated = Date(timeIntervalSince1970: seconds)
            }
        default:
            break
        }
    }
    return snapshot
}

public func counterDelta(_ current: Double, _ previous: Double?) -> Double {
    guard let previous else { return current }
    return current >= previous ? current - previous : current
}

// The very first sample has no previous counters to diff against. The server's
// counters are cumulative for the whole life of the process, so counting them
// would credit all historical traffic to the current month. Only accept them
// when the server proves it started during the current month (vLLM exposes
// `prompt_tokens_created` for that; TensorFold exposes nothing, so the default
// is to start from zero).
public func firstSampleIsCurrentMonth(promptCreated: Date?, now: Date, calendar: Calendar = .current) -> Bool {
    guard let promptCreated else { return false }
    return calendar.isDate(promptCreated, equalTo: now, toGranularity: .month)
}

public struct UsageHistoryPoint: Codable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let promptTokens: Double
    public let generationTokens: Double
    public let requests: Double
    public let averageTTFT: Double
    public let generationSpeed: Double

    public init(timestamp: Date,
                promptTokens: Double,
                generationTokens: Double,
                requests: Double,
                averageTTFT: Double,
                generationSpeed: Double) {
        self.timestamp = timestamp
        self.promptTokens = promptTokens
        self.generationTokens = generationTokens
        self.requests = requests
        self.averageTTFT = averageTTFT
        self.generationSpeed = generationSpeed
    }
}

public func makeHistoryPoint(timestamp: Date,
                             promptDelta: Double,
                             generationDelta: Double,
                             requestsDelta: Double,
                             ttftSumDelta: Double,
                             ttftCountDelta: Double,
                             decodeSecondsDelta: Double) -> UsageHistoryPoint {
    // Per-window sample: TTFT averaged over requests completed in this polling
    // window and decode speed from this window's generation delta. Storing
    // window-local values (instead of cumulative month averages) keeps the
    // charts showing actual per-sample behaviour.
    let windowTTFT = ttftCountDelta > 0 ? ttftSumDelta / ttftCountDelta : 0
    let windowSpeed = decodeSecondsDelta > 0 ? generationDelta / decodeSecondsDelta : 0
    return UsageHistoryPoint(
        timestamp: timestamp,
        promptTokens: max(0, promptDelta),
        generationTokens: max(0, generationDelta),
        requests: max(0, requestsDelta),
        averageTTFT: windowTTFT.isFinite ? windowTTFT : 0,
        generationSpeed: windowSpeed.isFinite ? windowSpeed : 0
    )
}

public func pruneHistory(_ history: [UsageHistoryPoint], retentionDays: Int, now: Date = Date()) -> [UsageHistoryPoint] {
    let resolved = retentionDays > 0 ? retentionDays : 30
    let cutoff = Calendar.current.date(byAdding: .day, value: -resolved, to: now) ?? .distantPast
    return history.filter { $0.timestamp >= cutoff }
}
