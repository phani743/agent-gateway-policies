# LLM Edge Cases

## Harmful / Jailbreak Prompts

- Policy: `prompt-guard.yaml`
- Input: prompts containing self-harm, violence, or known jailbreak patterns
- Expected: 403 with configured rejection body
- Audit mode available for logging without blocking

## Token / Cost Runaway

- Policy: rate limiting + token budgets
- Input: high-volume or long-context requests from a single key/user
- Expected: 429 when limit or budget is exceeded
- Rolling windows and per-identity keys recommended

## Streaming with Guardrails

- Enable `streaming: Enabled` on prompt guards
- Partial responses are filtered before being sent to the client

## Credential Isolation

- Provider API keys live only in Kubernetes Secrets referenced by `secretRef`
- Agents never receive the provider key; the gateway injects it on the upstream call

## Model Aliases / Migration

- Use model aliases to map deprecated model names to current ones without client changes
