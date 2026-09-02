# Security Policy

## Reporting a vulnerability

Please use GitHub private vulnerability reporting when available. Do not publish credentials, private endpoints, prompt content, or reproducible secrets in a public issue.

## Deployment guidance

- Do not expose an unauthenticated Prometheus endpoint to the public internet.
- Prefer localhost, a trusted private network, VPN, or authenticated proxy.
- Review changes before installing third-party builds.

The application never needs an LLM API key when reading an unauthenticated vLLM `/metrics` endpoint.
