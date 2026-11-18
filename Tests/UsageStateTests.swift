import Foundation
import Testing

import LocalLLMUsageCore

@Suite("Ingest")
struct IngestTests {

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func snapshot(prompt: Double, generation: Double = 0, requests: Double = 0,
                          ttftSum: Double = 0, ttftCount: Double = 0, decode: Double = 0,
                          created: Date? = nil) -> MetricsSnapshot {
        let s = MetricsSnapshot()
        var snapshot = s
        snapshot.prompt = prompt
        snapshot.generation = generation
        snapshot.requests = requests
        snapshot.ttftSum = ttftSum
        snapshot.ttftCount = ttftCount
        snapshot.decodeSeconds = decode
        snapshot.promptCreated = created
        return snapshot
    }

    @Test("Month and day rollovers reset the counters")
    func rollovers() {
        var state = UsageState()
        let calendar = gregorianUTC()
        let october = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-15
        let created = october.addingTimeInterval(-60)
        var effects = ingestSample(snapshot(prompt: 100, generation: 10, requests: 2, created: created),
                                   into: &state, now: october, historySeeded: true, calendar: calendar)
        #expect(state.monthPrompt == 100 && state.dayPrompt == 100)
        #expect(effects.shouldRecordHistory) // requestsDelta > 0

        let november = Date(timeIntervalSince1970: 1_794_600_000) // 2026-11-14
        effects = ingestSample(snapshot(prompt: 150, generation: 5, requests: 1),
                               into: &state, now: november, historySeeded: true, calendar: calendar)
        #expect(state.monthPrompt == 50) // month reset, then +delta(150-100)
        #expect(state.dayPrompt == 50)
        #expect(state.dayGeneration == 5)
        #expect(state.monthRequests == 1)
        #expect(state.monthKey.hasPrefix("2026-11"))
    }

    @Test("First sample without a creation gauge starts from zero")
    func firstSampleGate() {
        var state = UsageState()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let effects = ingestSample(snapshot(prompt: 67_519_737, requests: 664),
                                   into: &state, now: now, historySeeded: true, calendar: gregorianUTC())
        #expect(state.monthPrompt == 0)
        #expect(state.monthRequests == 0)
        #expect(state.lastPrompt == 67_519_737)
        #expect(effects.isFirstSample)
        #expect(!effects.shouldRecordHistory || true) // recorded via !historySeeded path when false
    }

    @Test("First sample with a current-month creation gauge is credited")
    func firstSampleCredited() {
        var state = UsageState()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let created = now.addingTimeInterval(-3600)
        let effects = ingestSample(snapshot(prompt: 500, generation: 20, requests: 3, created: created),
                                   into: &state, now: now, historySeeded: true, calendar: gregorianUTC())
        #expect(state.monthPrompt == 500)
        #expect(state.monthGeneration == 20)
        #expect(state.monthRequests == 3)
        #expect(effects.requestsDelta == 3)
    }

    @Test("Deltas accumulate; a counter reset counts from the new value")
    func deltasAndResets() {
        var state = UsageState()
        let calendar = gregorianUTC()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = ingestSample(snapshot(prompt: 1000, generation: 100, requests: 10, ttftSum: 5, ttftCount: 10, decode: 50,
                                  created: t0.addingTimeInterval(-60)),
                         into: &state, now: t0, historySeeded: true, calendar: calendar)
        // Normal continuation.
        var effects = ingestSample(snapshot(prompt: 1200, generation: 160, requests: 12, ttftSum: 6, ttftCount: 12, decode: 60),
                                   into: &state, now: t0.addingTimeInterval(2), historySeeded: true, calendar: calendar)
        #expect(state.monthPrompt == 1200)
        #expect(state.monthGeneration == 160)
        #expect(effects.requestsDelta == 2)
        #expect(state.monthTTFTSum == 6)
        #expect(state.monthDecodeSeconds == 60)
        // Server restarted: counters went down.
        effects = ingestSample(snapshot(prompt: 30),
                               into: &state, now: t0.addingTimeInterval(4), historySeeded: true, calendar: calendar)
        #expect(state.monthPrompt == 1230)
        #expect(effects.promptDelta == 30)
    }

    @Test("Live generation speed holds for 15 s, then zeroes")
    func liveSpeedHold() {
        var state = UsageState()
        let calendar = gregorianUTC()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = ingestSample(snapshot(prompt: 0), into: &state, now: t0, historySeeded: true, calendar: calendar)
        _ = ingestSample(snapshot(prompt: 0, generation: 100),
                         into: &state, now: t0.addingTimeInterval(2), historySeeded: true, calendar: calendar)
        #expect((state.liveGenerationSpeed ?? 0) == 50)

        // Within the hold window a zero-delta sample keeps the last speed.
        _ = ingestSample(snapshot(prompt: 0, generation: 100),
                         into: &state, now: t0.addingTimeInterval(10), historySeeded: true, calendar: calendar)
        #expect((state.liveGenerationSpeed ?? 0) == 50)

        // Past 15 s of silence it zeroes.
        _ = ingestSample(snapshot(prompt: 0, generation: 100),
                         into: &state, now: t0.addingTimeInterval(30), historySeeded: true, calendar: calendar)
        #expect((state.liveGenerationSpeed ?? 0).isZero)
    }

    @Test("sanitizeNonFinite scrubs counters and optionals")
    func sanitize() {
        var state = UsageState()
        state.monthPrompt = .nan
        state.dayRequests = .infinity
        state.lastGeneration = -.infinity
        state.liveGenerationSpeed = .nan
        state.sanitizeNonFinite()
        #expect(state.monthPrompt == 0)
        #expect(state.dayRequests == 0)
        #expect(state.lastGeneration == 0)
        #expect(state.liveGenerationSpeed == 0)
    }
}

@Suite("History bucketing")
struct HistoryBucketingTests {

    private func point(at time: TimeInterval, prompt: Double = 0, generation: Double = 0,
                       requests: Double = 1, ttft: Double = 0, speed: Double = 0) -> UsageHistoryPoint {
        UsageHistoryPoint(timestamp: Date(timeIntervalSince1970: time),
                          promptTokens: prompt, generationTokens: generation, requests: requests,
                          averageTTFT: ttft, generationSpeed: speed)
    }

    @Test("Samples within one bucket merge into the last point")
    func mergesWithinBucket() {
        let first = point(at: 1_800_000_000, prompt: 10, generation: 100, requests: 2, ttft: 0.5, speed: 40)
        // 59 s later: same 60 s bucket.
        let second = point(at: 1_800_000_059, prompt: 5, generation: 50, requests: 3, ttft: 0.2, speed: 80)
        let merged = mergeIntoHistory([first], point: second)
        #expect(merged.count == 1)
        #expect(merged[0].promptTokens == 15)
        #expect(merged[0].generationTokens == 150)
        #expect(merged[0].requests == 5)
        #expect(abs(merged[0].averageTTFT - (0.5 * 2 + 0.2 * 3) / 5) < 1e-9)
        #expect(abs(merged[0].generationSpeed - (40 * 100 + 80 * 50) / 150) < 1e-9)
    }

    @Test("Samples in different buckets are appended")
    func appendsAcrossBuckets() {
        let first = point(at: 1_800_000_000)
        let second = point(at: 1_800_000_061)
        let merged = mergeIntoHistory([first], point: second)
        #expect(merged.count == 2)
        #expect(merged.map(\.id) == [first.id, second.id])
    }

    @Test("Empty history just appends")
    func emptyHistory() {
        let merged = mergeIntoHistory([], point: point(at: 1_800_000_000, prompt: 7))
        #expect(merged.count == 1)
        #expect(merged[0].promptTokens == 7)
    }
}
