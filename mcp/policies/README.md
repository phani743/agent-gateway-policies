# MCP Policy Catalog (Rego)

MCP-specific Rego policies (originally from the monorepo root `mcp-policies/`).

## Classification

| Classification | Meaning |
|---|---|
| **global** | Always enforced. Cannot be disabled. Ships with every deployment. |
| **mandatory** | Must be explicitly enabled per environment via GitHub variable, but strongly recommended. |
| **optional** | On-demand. Enabled only when the use case or edge case applies. |

## Policies

### Global (always on)
- **tool-invocation-guard** - Blocks dangerous tools: delete_resource, drop_database, exec_shell, drop_table, truncate.
- **session-binding** - Binds MCP sessions to authenticated identity; rejects cross-identity session reuse.
- **protocol-version-pin** - Enforces supported MCP protocol versions.

### Mandatory (explicitly enabled)
- **audit-logging** - Structured audit events for every tool call, decision, and denial.

### Optional (on-demand)
- **prompt-injection-detection** - Scans tool params for injection patterns. Use when tool sources are untrusted.
- **response-sanitization** - Strips secrets/PII from responses. Use when tools return sensitive payloads.
- **tool-result-cache-control** - Per-tool cache TTL. Use for time-sensitive results.
- **human-in-the-loop-gate** - Requires human approval for gated tools. Use for financial or destructive ops.
- **per-tool-rate-limit** - Finer-grained limits per tool. Use for expensive tools like search or bulk export.
- **data-exfiltration-guard** - Blocks unbounded bulk reads. Use in read-heavy environments.

## Enabling policies via GitHub Actions

Set the repository variable `ENABLED_MCP_POLICIES` to a comma-separated list of policy names.
Global policies are always included regardless of this variable.
Mandatory and optional policies are only bundled and deployed when listed.

Example: `ENABLED_MCP_POLICIES=audit-logging,prompt-injection-detection,human-in-the-loop-gate`
