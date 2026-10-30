# Dynatrace MCP Security Flow

## End-to-End Flow (Mermaid)

```mermaid
sequenceDiagram
    participant Agent
    participant AGW as Agent Gateway
    participant Auth as JWT / CEL Authz
    participant HITL as HITL Check
    participant DynatraceMCP as Dynatrace MCP Server
    participant DT as Dynatrace API

    Agent->>AGW: tools/call (e.g. get_problems) + JWT
    AGW->>Auth: Validate JWT (issuer, audience, signature)
    Auth-->>AGW: Claims (sub, roles, scopes)
    AGW->>Auth: CEL RBAC check (role → allowed tools)
    alt Role not authorized
        Auth-->>AGW: Deny
        AGW-->>Agent: 403 Forbidden
    else Authorized
        AGW->>HITL: Check if tool requires human approval
        alt High-risk tool & no human_approved claim
            HITL-->>AGW: Deny
            AGW-->>Agent: 403 + approval challenge
        else Allowed
            AGW->>DynatraceMCP: tools/call (inject Dynatrace API token)
            DynatraceMCP->>DT: Query (metrics / logs / problems)
            DT-->>DynatraceMCP: Result
            DynatraceMCP-->>AGW: Tool result
            AGW-->>Agent: Sanitized result
        end
    end
```

## RBAC Model (example)

| Role | Allowed Tools | Notes |
|------|---------------|-------|
| `observer` | get_problems, get_metrics, get_logs | Read-only |
| `sre` | observer + create_alert, update_maintenance_window | Can change configuration |
| `admin` | all tools | Full access; HITL still applies to destructive tools |

Roles come from the JWT `roles` or `groups` claim.

## Credential Isolation

- Agents never see the Dynatrace API token.
- The token lives only in a Kubernetes Secret referenced by the AgentgatewayBackend.
- The gateway injects it on the upstream call to the Dynatrace MCP server.

## Deployment

The existing CD workflow applies all YAMLs under `mcp/use-cases/dynatrace-mcp/policies/` when their basenames are listed in `ENABLED_POLICIES` (or when the variable is empty).
