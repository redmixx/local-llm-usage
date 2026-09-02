# Contributing

1. Fork the repository and create a focused branch.
2. Keep the app compatible with macOS 14 or newer.
3. Do not introduce telemetry or content logging.
4. Run `./scripts/check.sh` before opening a pull request.
5. Include screenshots for visible UI changes, using synthetic or non-sensitive metrics.

Please keep pull requests small and explain changes to metric semantics. New server backends should degrade gracefully when individual metrics are unavailable.
