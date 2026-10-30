# Dynatrace MCP on Open-Source Agent Gateway

Specialized use case: host and govern the Dynatrace MCP server through agentgateway so AI agents can query observability data (metrics, logs, traces, problems) under strict security controls.

## Architecture Overview

```
Agent (with JWT) → Agent Gateway → Dynatrace MCP Server → Dynatrace API
```

The gateway is the only path. It performs:
- JWT authentication
- CEL-based authorization (RBAC-style)
- Rate limiting
- Optional HITL for destructive or high-cost tools
- Credential isolation (Dynatrace API token never leaves the gateway)

## Security Controls

| Control | Implementation | Policy |
|---------|----------------|--------|
| Authentication | JWT validation (Entra / Keycloak / custom IdP) | `dynatrace-jwt-auth.yaml` |
| Authorization / RBAC | CEL rules on roles, scopes, tool names | `dynatrace-rbac.yaml` |
| Rate limiting | Per-user / per-role limits | `dynatrace-rate-limit.yaml` |
| HITL | Deny high-risk tools without `human_approved` claim | `dynatrace-hitl.yaml` |
| Credential isolation | Dynatrace API token in Kubernetes Secret, injected by gateway | `dynatrace-backend.yaml` |
| Audit | Structured logging of every tool call (via gateway access logs or ExtProc) | — |

## Policies

See the `policies/` folder:
- `dynatrace-backend.yaml` — AgentgatewayBackend + Secret for the Dynatrace MCP server
- `dynatrace-jwt-auth.yaml` — Strict JWT authentication
- `dynatrace-rbac.yaml` — Role-based tool allow/deny
- `dynatrace-rate-limit.yaml` — Per-identity rate limits
- `dynatrace-hitl.yaml` — Human-in-the-loop for sensitive tools

## Enabling

Add the policy basenames to the `ENABLED_POLICIES` GitHub variable (or leave empty to deploy all).

## Abbreviations

See [../../docs/abbreviations.md](../../docs/abbreviations.md).
