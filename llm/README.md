# LLM Protocol Support for Open-Source Agent Gateway

This folder contains policy templates and test data for LLM traffic (OpenAI-compatible chat completions, embeddings, Anthropic Messages, etc.) through the open-source agentgateway.

Agentgateway provides a unified OpenAI-compatible API surface while routing to multiple providers (OpenAI, Anthropic, Gemini, Bedrock, custom) and applying LLM-specific policies.

## Policy Catalog

| Policy | Type | Purpose | Attachment | Notes |
|--------|------|---------|------------|-------|
| `llm-backend.yaml` | Backend definition | Declares an LLM provider (OpenAI, Anthropic, etc.) as an AgentgatewayBackend | Backend (AI) | Required for routing LLM traffic |
| `jwt-authentication.yaml` | Global / Mandatory | Validates incoming agent or user JWT before any LLM call | Traffic (JWT) | Strip original token after validation |
| `api-key-authentication.yaml` | Optional | Validates API keys for LLM clients (with optional metadata / budgets) | Traffic (API key) | Useful when clients do not use JWTs |
| `rate-limiting.yaml` | Optional | Request or token-bucket rate limits per user / key / model | Traffic (rateLimit) | Local or remote; key on jwt.sub or header |
| `prompt-guard.yaml` | Optional / Edge-case | Content moderation (OpenAI Moderation, regex, Bedrock Guardrails, etc.) | Backend (AI promptGuard) | Blocks harmful prompts/responses |
| `model-defaults-overrides.yaml` | Optional | Sets default or override temperature, max_tokens, etc. | Backend (AI) | Enforces organizational model parameters |
| `token-budget.yaml` | Optional / Edge-case | Per-key or per-user token / spend budgets | Traffic or model | Prevents runaway cost |

### Global vs Optional

- **Global / Mandatory**: JWT or API-key authentication for production LLM access.
- **Optional**: Rate limiting, prompt guards, model parameter enforcement, token budgets.
- **Edge-case specific**: Prompt guards for safety; token budgets for cost control; model aliases for migration.

## Policy Uses

- **Authentication**: Ensure only authorized agents/users can invoke models.
- **Authorization / Rate limiting**: Limit blast radius and cost per identity.
- **Prompt guards**: Filter jailbreaks, PII, harmful content before it reaches the provider.
- **Defaults / overrides**: Force temperature, stop sequences, or system prompts organization-wide.
- **Token budgets**: Hard cap spend or token usage per key or user.

## Edge Cases

| Edge case | Policy | Handling |
|-----------|--------|----------|
| Harmful / jailbreak prompt | `prompt-guard.yaml` | Reject with 403 / custom body; optional audit mode |
| Token runaway / high cost | `token-budget.yaml` + rate limit | Block when budget exceeded; rolling windows |
| Model name migration | Model aliases | Map old model names to new provider models |
| Streaming responses with guards | Prompt guard streaming | Enable streaming guardrails so partial responses are filtered |
| Credential isolation for provider keys | Backend auth secretRef | Provider API keys stay in Secrets; never exposed to agents |
| Mixed request types (chat / embeddings) | AI routes | Explicitly map paths to Completions / Embeddings / Messages |

## Documentation

- **[Human-in-the-Loop](docs/human-in-the-loop.md)** — HITL patterns for LLM traffic, edge cases, and Mermaid flow
- **[Abbreviations](../docs/abbreviations.md)** — full list of abbreviations used in these docs

## How GitHub Actions Consume These

The CI/CD workflows lint and apply YAMLs under `llm/policies/`. Filter with the `ENABLED_POLICIES` variable. Live tests use secrets for provider keys / JWTs.

## Abbreviations

See the full [Abbreviations](../docs/abbreviations.md) page. Key terms used in this folder:

- **LLM**: Large Language Model
- **JWT**: JSON Web Token
- **HITL**: Human-in-the-Loop
- **API**: Application Programming Interface
- **ExtProc**: External Processing
- **OSS**: Open Source Software
