# CI and Version Control for Agent Gateway Policies

## What the CI builds / does

The CI workflow (`.github/workflows/ci.yaml`) does **not** build a container image or compile code. It is a pure **policy validation pipeline**. It runs on every push and pull request.

### Exact steps

1. **Checkout** the repo.
2. **YAML lint** — runs yamllint against:
   - `*.yaml`
   - `a2a/policies/`
   - `llm/policies/`
   - `mcp/policies/` (if present)
3. **Set up kubectl**.
4. **Server-side dry-run** — if a `KUBECONFIG` secret exists, it executes:
   ```bash
   kubectl apply --dry-run=server -f <each policy yaml> -n $GATEWAY_NS
   ```
   This validates the manifests against the live AKS API server (schema, CRDs, RBAC, etc.) without actually applying them.
5. **Kubeconform** — strict schema validation of the same YAML files.

That is the entire CI. It is a gate that prevents bad policy YAML from reaching `main`.

## How version control works

Everything is standard Git + GitHub:

| Aspect | How it works |
|--------|--------------|
| **Source of truth** | The YAML files in the Git repo (`a2a/policies/`, `llm/policies/`, etc.) |
| **Branches** | CI runs on every PR and on `main`. CD only deploys from `main` (or manual `workflow_dispatch`). |
| **History** | Every policy change is a normal Git commit. You can `git log`, `git diff`, or revert any policy file. |
| **Promotion** | Merge PR → CI passes → CD automatically applies the new/updated policies to AKS. |
| **Selective deploy** | The `ENABLED_POLICIES` GitHub variable (comma-separated basenames) lets you deploy only a subset. Empty = deploy everything. |
| **Environment isolation** | Same Git commit can be applied to different environments by changing GitHub Variables (`AGENT_GATEWAY_NS`, `AKS_CLUSTER_NAME`, etc.) or by using GitHub Environments. |
| **Secrets** | Cluster credentials (`KUBECONFIG` or `AZURE_CREDENTIALS`), test JWTs, etc. live only in GitHub Secrets — never in the repo. |

## Typical flow

1. Developer opens a PR that changes `a2a/policies/virtual-token-entra-obo.yaml`.
2. CI runs → lint + dry-run + kubeconform.
3. After review and merge to `main`, CD runs and does `kubectl apply` of the selected policies to the AKS namespace defined by variables.
4. The agentgateway controller on the cluster reconciles the CRDs and hot-reloads the data plane.

No images are built, no binaries are produced — only declarative policy YAML is validated and then applied.

## Related files

- CI workflow: `.github/workflows/ci.yaml`
- CD workflow: `.github/workflows/cd.yaml`
- Deployment flow diagram: `FLOW.md`
- Abbreviations: `../docs/abbreviations.md`
