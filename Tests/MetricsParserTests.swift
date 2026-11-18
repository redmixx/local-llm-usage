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

// A verbatim capture from a live TensorFold endpoint: colon-prefixed metric
// names, no labels, and no request counter (the latency histogram's sample
// count stands in for it). The previous parser required an underscore prefix
// plus a label block, so every one of these lines was silently ignored.
@Suite("TensorFold metrics")
struct TensorFoldMetricsTests {

    private let capture = """
    # HELP tensorfold:requests_running Requests in prefill or decode.
    # TYPE tensorfold:requests_running gauge
    tensorfold:requests_running 0
    # TYPE tensorfold:prompt_tokens_total counter
    tensorfold:prompt_tokens_total 67519737
    # TYPE tensorfold:generation_tokens_total counter
    tensorfold:generation_tokens_total 295663
    # TYPE tensorfold:request_latency_seconds_count counter
    tensorfold:request_latency_seconds_count 664
    # TYPE tensorfold:time_to_first_token_seconds_sum counter
    tensorfold:time_to_first_token_seconds_sum 11704.27204
    # TYPE tensorfold:time_to_first_token_seconds_count counter
    tensorfold:time_to_first_token_seconds_count 661
    # TYPE tensorfold:request_decode_seconds_sum counter
    tensorfold:request_decode_seconds_sum 5941.468856
    # TYPE tensorfold:request_decode_time_seconds_sum counter
    tensorfold:request_decode_time_seconds_sum 5941.468856
    """

    @Test("Parses an unlabelled, colon-prefixed capture")
    func parsesRealCapture() {
        let snapshot = parseMetrics(capture)

        #expect(snapshot.prompt == 67_519_737)
        #expect(snapshot.generation == 295_663)
        #expect(snapshot.requests == 664)
        #expect(snapshot.ttftCount == 661)
        #expect(abs(snapshot.ttftSum - 11_704.27204) < 1e-9)
        #expect(abs(snapshot.decodeSeconds - 5_941.468856) < 1e-9)
        #expect(snapshot.modelName == "Local model")
        #expect(snapshot.promptCreated == nil)
    }

    @Test("Aliased decode metrics are not counted twice")
    func decodeNotDoubleCounted() {
        let snapshot = parseMetrics("""
        tensorfold:request_decode_seconds_sum 100.0
        tensorfold:request_decode_time_seconds_sum 100.0
        """)
        #expect(snapshot.decodeSeconds == 100.0)
    }

    @Test("Legacy underscore-prefixed names keep working")
    func legacyUnderscoreNames() {
        let snapshot = parseMetrics("""
        tensorfold_prompt_tokens_total{model_name="m"} 10
        tensorfold_completion_tokens_total{model_name="m"} 20
        tensorfold_requests_total{model_name="m"} 3
        tensorfold_prefill_seconds_total{model_name="m"} 1.5
        tensorfold_decode_seconds_total{model_name="m"} 0.5
        """)
        #expect(snapshot.prompt == 10)
        #expect(snapshot.generation == 20)
        #expect(snapshot.requests == 3)
        #expect(snapshot.ttftSum == 1.5)
        #expect(snapshot.decodeSeconds == 0.5)
    }

    @Test("Metric names normalise to a shared vocabulary")
    func canonicalNames() {
        #expect(canonicalMetricName("vllm:prompt_tokens_total") == "prompt_tokens_total")
        #expect(canonicalMetricName("tensorfold:prompt_tokens_total") == "prompt_tokens_total")
        #expect(canonicalMetricName("tensorfold_completion_tokens_total") == "generation_tokens_total")
        #expect(canonicalMetricName("tensorfold:request_latency_seconds_count") == "request_success_total")
        #expect(canonicalMetricName("some_other_metric") == "some_other_metric")
    }

    @Test("Optional Prometheus timestamp is not read as the value")
    func ignoresTimestampSuffix() {
        let snapshot = parseMetrics("vllm:prompt_tokens_total{model_name=\"m\"} 1234 1725000000000")
        #expect(snapshot.prompt == 1234)
    }

    @Test("Non-finite values are rejected instead of poisoning the counters")
    func rejectsNonFinite() {
        let snapshot = parseMetrics("""
        tensorfold:prompt_tokens_total NaN
        tensorfold:generation_tokens_total inf
        """)
        #expect(snapshot.prompt == 0)
        #expect(snapshot.generation == 0)
        #expect(snapshot.prompt.isFinite)
        #expect(snapshot.generation.isFinite)
    }

    @Test("First sample is only trusted when the server started this month")
    func firstSampleGate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15

        #expect(firstSampleIsCurrentMonth(promptCreated: nil, now: now, calendar: calendar) == false)
        #expect(firstSampleIsCurrentMonth(promptCreated: now.addingTimeInterval(-3600), now: now, calendar: calendar) == true)
        #expect(firstSampleIsCurrentMonth(promptCreated: now.addingTimeInterval(-45 * 24 * 3600), now: now, calendar: calendar) == false)
    }
}
