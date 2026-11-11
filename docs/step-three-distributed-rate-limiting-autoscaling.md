# Step 3: Distributed Rate Limiting and Autoscaling on Kubernetes

This document covers how rate limiting, Entra JWKS validation, and well-known protected resource (PRM) metadata behave when APIM self-hosted gateway and agentgateway run as auto-scaling deployments on Kubernetes. It documents the known issues and their mitigations.

## Architecture context

- **APIM self-hosted gateway**: deployed as a Kubernetes Deployment, auto-scaled on CPU/memory or requests-per-second. Each pod is a gateway replica.
- **agentgateway**: deployed as a Gateway with multiple proxy replicas behind a ClusterIP service, also auto-scaled.
- **Entra ID**: identity provider issuing JWTs, serving JWKS at the well-known keys endpoint, and serving the OAuth protected resource metadata (PRM) document.

The client path is: ChatGPT/VS Code → Akamai → Azure Application Gateway → APIM self-hosted gateway → agentgateway → MCP backend. APIM does bare JWT validation (no OBO) and forwards the original token. agentgateway enforces the well-known protected resource policy and audience binding.

## 1. APIM self-hosted gateway rate limiting across replicas

### How it works

APIM's `rate-limit` and `rate-limit-by-key` policies can synchronize counters across self-hosted gateway instances using UDP-based neighborhood discovery:

- **UDP port 4290**: rate-limit counter synchronization between instances.
- **UDP port 4291**: heartbeat discovery so instances find each other.

Setup steps:

1. Expose ports 4290 and 4291 (UDP) on the gateway container in the Deployment.
2. Create a **headless Kubernetes Service** that selects all gateway pods and exposes the same two UDP ports. Headless (no cluster IP) is required so DNS returns the individual pod IPs rather than a single virtual IP.
3. Set the `neighborhood.host` environment variable on every gateway pod to the headless service name (for example, `rate-limit-discovery`).
4. Ensure NetworkPolicies, the CNI, and any host firewalls allow bidirectional UDP 4290 and 4291 between all gateway pods.
5. All pods must run the same self-hosted gateway resource and a v2 image.

Once configured, instances automatically discover each other and exchange counters asynchronously.

### Known issues and mitigations

| Issue | Impact | Mitigation |
| --- | --- | --- |
| Counters are exchanged **asynchronously** | Brief bursts can slightly exceed the nominal limit | Accept the eventual consistency, or if an exact transactional global quota is mandatory, use a centralized backend (for example Redis) instead of UDP sync |
| Sync is **local to that one self-hosted gateway resource** | Counters do not merge with the managed cloud gateway or a different gateway resource | Design quotas per gateway resource; do not assume cross-resource aggregation |
| **NetworkPolicy or CNI blocks UDP 4290/4291** | Sync silently fails; every pod enforces its own independent limit, so the effective limit becomes N times the configured value with N replicas | This is the most common production bug. Add an explicit NetworkPolicy allowing the UDP ports, verify with packet captures or logs, and alert on per-pod counter divergence |
| Pod IP churn during scaling or rolling updates | A pod that restarts gets a new IP; discovery must re-resolve | The headless service plus heartbeats handle this automatically, but give pods a reasonable `terminationGracePeriodSeconds` (60+) so in-flight synced state drains cleanly |
| Mixed image versions across pods | Counter format or protocol mismatches | Pin the Deployment to one image tag and use a rolling update strategy with `maxUnavailable: 0` |

### Recommended hardening for APIM

- Run a minimum of three replicas with high-available scheduling (anti-affinity across nodes and availability zones).
- Prefer scale-out (more small pods) over scale-up.
- Set container log level to `warn` in production to reduce overhead.
- Deploy the self-hosted gateway in a dedicated namespace.
- After any change to `neighborhood.host` or ports, restart the Deployment so discovery re-initializes.
- Monitor: track 429 responses per pod and compare against the configured limit. If any pod's 429 rate is near zero while others are high, sync is likely broken.

## 2. agentgateway rate limiting across replicas

agentgateway offers two modes:

### Local rate limiting

- Counters live **in-process on each proxy replica**.
- Simple to configure via `AgentgatewayPolicy` with `spec.traffic.rateLimit.local` (requests, unit, optional burst).
- **Trap**: with three replicas, the effective fleet-wide limit is three times the configured value. A budget of 30 requests per minute per agent becomes ~90 across the fleet.
- Fine for coarse ceilings or per-replica safety valves, but not for strict per-user or per-agent quotas.

### Global rate limiting

- Every replica calls an **external rate limit service** over Envoy's rate limit gRPC protocol.
- The service matches descriptors (for example, extracted via CEL from the JWT `sub` or an `X-Agent-ID` header) to rules and keeps shared counters in a backend store, typically **Redis**.
- This gives a true fleet-wide quota: 100 requests per minute per user means 100 total, regardless of which replica receives the request.
- Two components are required:
  1. An `AgentgatewayPolicy` with `rateLimit.global`, specifying descriptors, a domain identifier, and a `backendRef` to the rate limit service.
  2. A rate limit service implementing the Envoy Rate Limit protocol (for example, Envoy's reference rate-limit service) backed by Redis.
- Solo's enterprise build for agentgateway ships a built-in rate limiter (`rate-limiter-<gatewayclass>`) and a bundled in-cluster Redis (`ext-cache-<gatewayclass>`) as shared extensions, so you do not need to run your own. For production, point `spec.sharedExtensions.extCache.redis.url` at an external Redis instance with persistent storage, because the bundled one resets counters when its pod is rescheduled.
- The gRPC hop adds a small amount of latency per request but is the only way to get consistent enforcement.

### Known issues and mitigations

| Issue | Impact | Mitigation |
| --- | --- | --- |
| Using `local` limits on a multi-replica Gateway | Effective quota is multiplied by replica count; budgets are not what operators expect | Use `global` limits for anything that must be a hard fleet-wide ceiling; reserve `local` for per-replica circuit breakers |
| Bundled in-cluster Redis has no persistent storage | Counters reset when the Redis pod is rescheduled, causing a temporary window where limits are loose | Use an external Redis with persistence for production |
| Rate limit service or Redis unavailable | Behavior depends on configuration; requests may fail open or closed | Configure the policy's failure mode explicitly; monitor the rate limiter's health and alert on it; consider a circuit breaker so a dead limiter does not take down the gateway |
| Descriptor extraction depends on JWT claims being present | If a request lacks the expected claim (for example, anonymous or malformed token), the descriptor may be empty and all such traffic shares one bucket | Validate the JWT before the rate limit policy in the chain, and define a fallback descriptor or reject unauthenticated traffic upstream |
| CEL expressions in descriptors are v1alpha1 | Schema may change between versions | Pin the agentgateway version and review release notes on upgrades |

### Recommended pattern for this stack

Since APIM already does coarse JWT validation and forwards the original token, agentgateway's global rate limiter should key on the same identity APIM checked — the JWT `sub` claim, or the `X-Agent-ID` header that a JWT auth policy populates from `sub`. That keeps the quota aligned with the authorization decision made one hop upstream.

Example descriptor sketch (Envoy rate-limit service config):

```yaml
domain: agentgateway
descriptors:
  - key: agent
    rate_limit:
      unit: minute
      requests_per_unit: 150
```

And the matching `remoteRateLimit` policy on the agentgateway route points every replica at the same rate-limit service host and domain.

## 3. Entra JWKS validation during scaling

- Each APIM and agentgateway replica validates JWTs locally against a cached copy of Entra's JWKS.
- The cache has a refresh interval. When a new pod starts (scale-out or rolling update), its JWKS cache is cold until the first refresh completes.
- **Impact**: a newly scaled pod can return brief 401 spikes for otherwise valid tokens until its cache warms. The window is typically seconds to a minute depending on the refresh interval.
- **Mitigations**:
  - Keep the JWKS refresh interval reasonably short (for example, five to ten minutes) so cold caches recover quickly.
  - Use a readiness probe that performs a token validation check before the pod receives traffic, so Kubernetes does not route requests to a cold replica.
  - Entra's JWKS is served over HTTPS with standard caching headers; pods should be allowed to reach `login.microsoftonline.com` without interception.
  - On key rotation, expect a short overlap where both old and new keys are valid — do not treat a single 401 during rotation as an incident.

## 4. Well-known protected resource metadata across replicas

- The PRM document (served at `/.well-known/oauth-protected-resource`) is **static content** generated from configuration. No shared state or coordination is required between replicas.
- **Requirements**: every replica must serve the identical PRM document (same issuer, same audiences, same scopes) and the URL must be reachable from clients through the full fronting path (Akamai, Application Gateway, APIM).
- **Mitigations**: generate the PRM from a single source of truth (the same config that defines agentgateway's `mcpAuthentication` audiences), and add a synthetic check that fetches the PRM URL through the public path and asserts the contents match the expected config.
- If APIM is also serving a PRM document as a facade (as discussed in Step 2), both PRM endpoints must agree on issuer and audience values or clients will see conflicting metadata.

## 5. Summary of recommendations

1. **APIM**: enable UDP neighborhood sync (ports 4290/4291) via a headless service and `neighborhood.host`; verify NetworkPolicy allows the traffic; monitor per-pod 429 rates for divergence.
2. **agentgateway**: use `global` rate limiting with an external Redis-backed rate limit service for any strict quota; keep `local` limits only as per-replica safety valves; use external persistent Redis in production.
3. **Entra**: accept brief cold-cache 401s on new pods; add a readiness probe and a short JWKS refresh interval.
4. **PRM**: treat it as replicated static config; assert identical content across replicas and through the public URL.
5. **Observability**: alert on rate-limiter and Redis health, on per-pod counter divergence, and on 401 spikes correlated with scaling events.

## References

- Azure APIM self-hosted gateway production guidance: https://learn.microsoft.com/en-us/azure/api-management/how-to-self-hosted-gateway-on-kubernetes-in-production
- APIM rate limit synchronization sample: https://github.com/tomkerkhove/azure-apim-shgw-rate-limit-discovery
- agentgateway global rate limiting: https://agentgateway.dev/docs/kubernetes/latest/security/rate-limit-global/
- agentgateway local rate limiting: https://agentgateway.dev/docs/kubernetes/latest/documentation/security/rate-limit-http/
- Solo Enterprise agentgateway rate limiting architecture: https://docs.solo.io/agentgateway/kubernetes/latest/documentation/about/architecture/rate-limiting/
- External Redis for Solo Enterprise extensions: https://docs.solo.io/agentgateway/kubernetes/latest/documentation/setup/customize/extensions/external-redis/
