import Foundation

// Testable, UI-independent parsing of vLLM Prometheus metrics.
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

public func metricValue(_ line: Substring) -> Double? {
    guard let raw = line.split(separator: " ").last else { return nil }
    return Double(raw)
}

public func parseMetrics(_ text: String) -> MetricsSnapshot {
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

public func counterDelta(_ current: Double, _ previous: Double?) -> Double {
    guard let previous else { return current }
    return current >= previous ? current - previous : current
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
        averageTTFT: windowTTFT,
        generationSpeed: windowSpeed
    )
}

public func pruneHistory(_ history: [UsageHistoryPoint], retentionDays: Int, now: Date = Date()) -> [UsageHistoryPoint] {
    let resolved = retentionDays > 0 ? retentionDays : 30
    let cutoff = Calendar.current.date(byAdding: .day, value: -resolved, to: now) ?? .distantPast
    return history.filter { $0.timestamp >= cutoff }
}
