# Agent Gateway Policies (Standalone)

Standalone repository for open-source agentgateway policies, documentation, and GitHub Actions CI/CD targeting AKS.

Extracted from the monorepo `mcp-policy-comparison`.

## Structure

- `a2a/` — Agent-to-Agent policies, docs, testdata
- `llm/` — LLM protocol policies, docs, testdata
- `mcp/` — MCP-related docs
- `docs/` — Shared docs (abbreviations, HITL overview)
- `deploy/` — CI/CD docs and yamllint config
- `.github/workflows/` — CI (validation) and CD (dynamic AKS apply)
- Root YAMLs — base rate-limiting, authentication, authorization

## Quick start

1. Set GitHub Variables and Secrets as documented in `deploy/FLOW.md`.
2. Push to `main` — CI validates, CD applies selected policies to AKS.

See `deploy/CI-AND-VERSION-CONTROL.md` for details on what CI does and how version control works.

## Abbreviations

See `docs/abbreviations.md`.
