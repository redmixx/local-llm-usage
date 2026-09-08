import Foundation
import Testing

import LocalLLMUsageCore

// The parser lives in LocalLLMUsageCore (Sources/Core), the same canonical
// file that build.sh compiles into the app.

@Suite("MetricsParser")
struct MetricsParserTests {

    private let sample = """
    # HELP vllm:prompt_tokens_total Number of prefill tokens processed.
    # TYPE vllm:prompt_tokens_total counter
    vllm:prompt_tokens_total{model_name="meta-llama/Llama-3.1-8B-Instruct"} 1234.0
    # HELP vllm:generation_tokens_total Number of generation tokens processed.
    # TYPE vllm:generation_tokens_total counter
    vllm:generation_tokens_total{model_name="meta-llama/Llama-3.1-8B-Instruct"} 5678.0
    # TYPE vllm:request_success_total counter
    vllm:request_success_total{model_name="meta-llama/Llama-3.1-8B-Instruct",finish_reason="stop"} 42.0
    # TYPE vllm:time_to_first_token_seconds_sum counter
    vllm:time_to_first_token_seconds_sum{model_name="meta-llama/Llama-3.1-8B-Instruct"} 84.0
    # TYPE vllm:time_to_first_token_seconds_count counter
    vllm:time_to_first_token_seconds_count{model_name="meta-llama/Llama-3.1-8B-Instruct"} 42.0
    # TYPE vllm:request_decode_time_seconds_sum counter
    vllm:request_decode_time_seconds_sum{model_name="meta-llama/Llama-3.1-8B-Instruct"} 210.0
    # TYPE vllm:prompt_tokens_created gauge
    vllm:prompt_tokens_created{model_name="meta-llama/Llama-3.1-8B-Instruct"} 1725000000.0
    """

    @Test("Parses all six counters, model name and created timestamp")
    func parsesCoreMetrics() {
        let snapshot = parseMetrics(sample)

        #expect(snapshot.prompt == 1234.0)
        #expect(snapshot.generation == 5678.0)
        #expect(snapshot.requests == 42.0)
        #expect(snapshot.ttftSum == 84.0)
        #expect(snapshot.ttftCount == 42.0)
        #expect(snapshot.decodeSeconds == 210.0)
        #expect(snapshot.modelName == "meta-llama/Llama-3.1-8B-Instruct")
        #expect(snapshot.promptCreated?.timeIntervalSince1970 == 1_725_000_000.0)
    }

    @Test("Aggregates label series instead of overwriting them")
    func aggregatesMultipleSeries() {
        let text = """
        vllm:prompt_tokens_total{model_name="a"} 100.0
        vllm:prompt_tokens_total{model_name="b"} 250.0
        vllm:generation_tokens_total{model_name="a"} 10.0
        vllm:generation_tokens_total{model_name="b"} 20.0
        """
        let snapshot = parseMetrics(text)
        #expect(snapshot.prompt == 350.0)
        #expect(snapshot.generation == 30.0)
        #expect(snapshot.modelName == "a")
    }

    @Test("Unknown metric names and comment lines are ignored")
    func ignoresUnknownAndComments() {
        let text = """
        # HELP some_other_metric Nothing.
        some_other_metric 999.0
        vllm:garbage_metric 5.0
        """
        let snapshot = parseMetrics(text)
        #expect(snapshot.prompt == 0)
        #expect(snapshot.generation == 0)
        #expect(snapshot.requests == 0)
        #expect(snapshot.modelName == "Local model")
    }

    @Test("Empty body yields an empty default snapshot")
    func emptyBodyYieldsDefaults() {
        let snapshot = parseMetrics("")
        #expect(snapshot.prompt == 0)
        #expect(snapshot.ttftCount == 0)
        #expect(snapshot.modelName == "Local model")
        #expect(snapshot.promptCreated == nil)
    }

    @Test("Malformed numeric values do not crash and count as zero")
    func malformedValuesAreTolerated() {
        let text = """
        vllm:prompt_tokens_total{model_name="m"} not-a-number
        vllm:generation_tokens_total{model_name="m"}
        """
        let snapshot = parseMetrics(text)
        #expect(snapshot.prompt == 0)
        #expect(snapshot.generation == 0)
    }

    @Test("Counter delta survives counter reset (current < previous)")
    func counterDeltaOnReset() {
        #expect(counterDelta(100, 900) == 100)
        #expect(counterDelta(900, 100) == 800)
        #expect(counterDelta(42, nil) == 42)
    }

    @Test("History point stores per-window sample, not month average")
    func historyPointIsWindowScoped() {
        let point = makeHistoryPoint(
            timestamp: Date(timeIntervalSince1970: 1_725_000_000),
            promptDelta: 100,
            generationDelta: 250,
            requestsDelta: 2,
            ttftSumDelta: 0.4,
            ttftCountDelta: 2,
            decodeSecondsDelta: 5.0
        )
        #expect(point.averageTTFT == 0.2)
        #expect(point.generationSpeed == 50.0)
        #expect(point.promptTokens == 100)
        #expect(point.generationTokens == 250)
    }

    @Test("History point falls back to zero when window has no samples")
    func historyPointZeroWhenNoSamples() {
        let point = makeHistoryPoint(
            timestamp: Date(),
            promptDelta: 0,
            generationDelta: 0,
            requestsDelta: 0,
            ttftSumDelta: 0,
            ttftCountDelta: 0,
            decodeSecondsDelta: 0
        )
        #expect(point.averageTTFT == 0)
        #expect(point.generationSpeed == 0)
    }

    @Test("Retention prunes old points and keeps the default of 30 days")
    func pruneHistoryRetention() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = UsageHistoryPoint(timestamp: now.addingTimeInterval(-40 * 24 * 3600), promptTokens: 1, generationTokens: 1, requests: 1, averageTTFT: 0, generationSpeed: 0)
        let recent = UsageHistoryPoint(timestamp: now.addingTimeInterval(-2 * 24 * 3600), promptTokens: 2, generationTokens: 2, requests: 2, averageTTFT: 0, generationSpeed: 0)
        let future = UsageHistoryPoint(timestamp: now.addingTimeInterval(3600), promptTokens: 3, generationTokens: 3, requests: 3, averageTTFT: 0, generationSpeed: 0)

        let pruned = pruneHistory([old, recent, future], retentionDays: 30, now: now)
        #expect(pruned.count == 2)
        #expect(pruned.map(\.id) == [recent.id, future.id])

        let fallback = pruneHistory([old, recent], retentionDays: 0, now: now)
        #expect(fallback.count == 1)
        #expect(fallback.map(\.id) == [recent.id])
    }
}
