# Privacy

Local LLM Usage runs locally on macOS.

It stores timestamps, numeric token/request counters, aggregate TTFT and decode-time measurements, and user preferences. It does **not** store prompts, model responses, API keys, browser history, user identity, or per-application usage.

The app contains no analytics or telemetry and sends no data to the project maintainers. The configured metrics endpoint receives a regular HTTP GET request. Users are responsible for securing remote endpoints appropriately.
