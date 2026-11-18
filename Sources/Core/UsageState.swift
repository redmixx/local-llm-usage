import Foundation

// Shared persisted state and the pure ingest logic. Both the app and the
// widget compile this file (see build.sh), so the Codable layout lives in
// exactly one place: a field added here is instantly visible to both targets
// instead of silently breaking the other side's decoder.

public enum UsageStore {
    public static let suiteName = "group.com.redmix.localllmusage"
    public static let stateKey = "usage-state-v1"
    public static let historyKey = "usage-history-v1"
}

public struct UsageState: Codable {
    public var monthKey = ""
    public var dayKey = ""
    public var monthPrompt = 0.0
    public var monthGeneration = 0.0
    public var monthRequests = 0.0
    public var monthTTFTSum = 0.0
    public var monthTTFTCount = 0.0
    public var monthDecodeSeconds = 0.0
    public var dayPrompt = 0.0
    public var dayGeneration = 0.0
    public var dayRequests = 0.0
    public var lastPrompt: Double?
    public var lastGeneration: Double?
    public var lastRequests: Double?
    public var lastTTFTSum: Double?
    public var lastTTFTCount: Double?
    public var lastDecodeSeconds: Double?
    public var lastUpdated: Date?
    public var liveGenerationSpeed: Double?
    // Serwer (np. tensorfold) zrzuca metryki partiami co ~10 s, więc między
    // zrzutami delta wynosi 0. Trzymamy ostatnią niezerową prędkość i czas jej
    // pomiaru, żeby menu nie mrugało 0 między partiami podczas długiej generacji.
    public var liveGenerationSpeedAt: Date?
    public var online = false
    public var modelName = "Local model"

    public init() {}
}

extension UsageState {
    /// Replaces NaN/±inf with zero. JSONEncoder refuses non-finite numbers, so a
    /// single poisoned sample would otherwise stop state persistence for good.
    public mutating func sanitizeNonFinite() {
        let counters: [WritableKeyPath<UsageState, Double>] = [
            \.monthPrompt, \.monthGeneration, \.monthRequests,
            \.monthTTFTSum, \.monthTTFTCount, \.monthDecodeSeconds,
            \.dayPrompt, \.dayGeneration, \.dayRequests
        ]
        for path in counters where !self[keyPath: path].isFinite {
            self[keyPath: path] = 0
        }
        let lastValues: [WritableKeyPath<UsageState, Double?>] = [
            \.lastPrompt, \.lastGeneration, \.lastRequests,
            \.lastTTFTSum, \.lastTTFTCount, \.lastDecodeSeconds,
            \.liveGenerationSpeed
        ]
        for path in lastValues {
            if let value = self[keyPath: path], !value.isFinite {
                self[keyPath: path] = 0
            }
        }
    }
}

/// What happened during an ingest, for the caller's side effects (history
/// recording, widget reload) that must stay out of the pure core.
public struct IngestEffects: Equatable {
    public var promptDelta: Double = 0
    public var generationDelta: Double = 0
    public var requestsDelta: Double = 0
    public var ttftSumDelta: Double = 0
    public var ttftCountDelta: Double = 0
    public var decodeSecondsDelta: Double = 0
    public var isFirstSample = false
    public var onlineChanged = false
    public var shouldRecordHistory = false

    public init() {}
}

/// Applies one metrics sample to the state: calendar rollovers, counter
/// deltas, first-sample gating, live-speed hold. Pure apart from the
/// `calendar` default; all persistence stays with the caller.
public func ingestSample(_ snapshot: MetricsSnapshot,
                   into state: inout UsageState,
                   now: Date,
                   historySeeded: Bool,
                   calendar: Calendar = .current) -> IngestEffects {
    var effects = IngestEffects()
    let sampleDuration = max(now.timeIntervalSince(state.lastUpdated ?? now), 0.001)
    let month = String(format: "%04d-%02d", calendar.component(.year, from: now), calendar.component(.month, from: now))
    let day = String(format: "%@-%02d", month, calendar.component(.day, from: now))
    let isFirstSample = state.lastPrompt == nil
    effects.isFirstSample = isFirstSample

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
    let previousOnline = state.online

    // On the first sample, accept the server's existing counters only when
    // it proves the process started during the current month. A server with
    // no creation gauge would otherwise credit its lifetime totals to now.
    if isFirstSample, !firstSampleIsCurrentMonth(promptCreated: snapshot.promptCreated, now: now) {
        promptDelta = 0
        generationDelta = 0
        requestsDelta = 0
        ttftSumDelta = 0
        ttftCountDelta = 0
        decodeDelta = 0
    }
    effects.promptDelta = promptDelta
    effects.generationDelta = generationDelta
    effects.requestsDelta = requestsDelta
    effects.ttftSumDelta = ttftSumDelta
    effects.ttftCountDelta = ttftCountDelta
    effects.decodeSecondsDelta = decodeDelta

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

    let measuredSpeed = !isFirstSample && generationDelta > 0 ? generationDelta / sampleDuration : 0
    if measuredSpeed > 0 {
        state.liveGenerationSpeed = measuredSpeed
        state.liveGenerationSpeedAt = now
    } else if let at = state.liveGenerationSpeedAt {
        // Serwer może raportować metryki partiami: zerujemy dopiero po 15 s
        // ciszy (dwa typowe odstępy między zrzutami metryk).
        if now.timeIntervalSince(at) > 15 { state.liveGenerationSpeed = 0 }
    } else {
        state.liveGenerationSpeed = 0
    }
    state.lastUpdated = now
    state.online = true
    state.modelName = snapshot.modelName

    effects.onlineChanged = state.online != previousOnline
    effects.shouldRecordHistory = requestsDelta > 0 || !historySeeded
    return effects
}

/// Time-bucketed history: a new sample within `bucketSeconds` of the last
/// point is merged into it instead of appended. Keeps the stored array at
/// ~1 point per minute instead of one per poll, while weighted averages
/// preserve TTFT/speed semantics. Returns the new history.
public func mergeIntoHistory(_ history: [UsageHistoryPoint],
                             point: UsageHistoryPoint,
                             bucketSeconds: TimeInterval = 60) -> [UsageHistoryPoint] {
    guard let last = history.last,
          Int(last.timestamp.timeIntervalSince1970 / bucketSeconds) ==
          Int(point.timestamp.timeIntervalSince1970 / bucketSeconds) else {
        return history + [point]
    }
    let requests = last.requests + point.requests
    let mergedTTFT: Double
    if requests > 0 {
        mergedTTFT = (last.averageTTFT * last.requests + point.averageTTFT * point.requests) / requests
    } else {
        mergedTTFT = last.averageTTFT
    }
    let generation = last.generationTokens + point.generationTokens
    let mergedSpeed: Double
    if generation > 0 {
        mergedSpeed = (last.generationSpeed * last.generationTokens + point.generationSpeed * point.generationTokens) / generation
    } else {
        mergedSpeed = last.generationSpeed
    }
    let merged = UsageHistoryPoint(
        timestamp: last.timestamp,
        promptTokens: last.promptTokens + point.promptTokens,
        generationTokens: generation,
        requests: requests,
        averageTTFT: mergedTTFT,
        generationSpeed: mergedSpeed
    )
    return history.dropLast() + [merged]
}
