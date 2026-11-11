# Step 1: End-to-End Inbound SSO Flow — Client → Azure APIM (Self-Hosted Gateway) → Agentgateway with Entra Well-Known Provider

**Audience:** Beginners who need a complete, step-by-step picture of how an MCP client authenticates through Azure API Management into agentgateway when agentgateway is configured with the native `entra` MCP authentication provider.

**Goal of this document:** Explain every hop, every well-known endpoint, and every role so you can understand (and later configure) the inbound authentication path. The outbound On-Behalf-Of (OBO) token exchange that happens *after* the user is authenticated is covered in existing policies and remains unchanged.

---

## 1. Architecture Overview

```
┌────────────────┐     ┌─────────────────────────────┐     ┌────────────────────────────┐
│  MCP Client     │     │  Azure APIM                  │     │  Agentgateway               │
│  (ChatGPT,      │────▶│  (Managed + Self-hosted      │────▶│  with provider: entra       │
│   VS Code,      │     │   gateway)                   │     │                             │
│   custom agent) │     │  - TLS termination           │     │  - Serves well-known        │
│                 │     │  - Subscription / API key    │     │    OAuth metadata           │
│                 │     │  - Rate limiting             │     │  - Proxies auth/token       │
│                 │     │  - Routing / path rewrite    │     │  - Validates JWT (JWKS)     │
└────────────────┘     │  - Header propagation        │     │  - Admits MCP requests      │
                        └──────────────────────────────┘     └────────────────────────────┘
                                      │
                                      ▼
                               (optional backend
                                MCP server)
```

**Three layers**

| Layer | Role in this flow |
|-------|-------------------|
| **Client** | Any MCP-compliant client (VS Code Copilot, Claude, ChatGPT custom GPT, MCP Inspector, etc.). Speaks the MCP Authorization specification. |
| **Azure APIM** | Front door. Terminates TLS, enforces subscription keys / rate limits, optionally validates a subscription or API key, and routes traffic (including `.well-known` paths) to the self-hosted gateway and then to agentgateway. Does **not** implement the MCP OAuth metadata itself in this design. |
| **Agentgateway** | The MCP/A2A gateway. With `mcpAuthentication.provider.entra` it acts as an Authorization Server *facade*. It serves the well-known endpoints, adapts Entra’s OAuth quirks, validates the final JWT, and only then forwards the MCP request to the real backend. |

---

## 2. Why the `entra` Provider Exists

Microsoft Entra ID does **not** fully implement the OAuth behaviors the MCP Authorization specification expects. Agentgateway’s native `entra` provider bridges the gaps so you do not need a separate adapter proxy.

| MCP Spec Expectation | Entra Reality | What agentgateway does |
|----------------------|---------------|------------------------|
| RFC 8414 Authorization Server metadata (`/.well-known/oauth-authorization-server`) | Only serves OIDC Discovery (`openid-configuration`) | Fetches Entra’s v2.0 `openid-configuration` and re-serves it as RFC 8414 metadata |
| `code_challenge_methods_supported: ["S256"]` | Entra supports PKCE but omits the claim from discovery | Injects the claim |
| Clients send RFC 8707 `resource` parameter | Entra v2 endpoints reject it (`AADSTS9010010: invalid_target`) | Advertises **proxied** authorize/token endpoints and strips `resource` before forwarding to Entra |
| Dynamic Client Registration (RFC 7591) | No registration endpoint | Short-circuits DCR and returns the pre-registered `clientId` |
| Public clients using PKCE | Web-platform apps are confidential and require a client secret | Registration response advertises `token_endpoint_auth_method: none`; if you set `clientSecret`, the gateway attaches it server-side only for the configured client |

---

## 3. Prerequisites (What You Must Have Ready)

1. **Entra App Registration**
   - Application (client) ID
   - Tenant ID
   - Redirect URIs of your MCP clients registered under **Mobile and desktop applications** (public/PKCE) or **Web** (confidential). Do **not** use the SPA platform.
   - An exposed API with a scope (e.g. `mcp_access`) so the Application ID URI is `api://<client-id>`.
   - Optional: client secret if the app is registered as a Web (confidential) platform.
2. **Agentgateway** running with a config that sets `provider: entra` and lists the well-known path matches.
3. **Azure API Management** instance with a self-hosted gateway that can reach agentgateway (VNet, private endpoint, or public ingress).

---

## 4. Detailed End-to-End Flow (Beginner Walkthrough)

### Step 0 – Client tries to talk to the MCP server

The client (e.g. VS Code) is configured with the **APIM public URL**:

```
https://your-apim.azure-api.net/my-mcp/mcp
```

It sends a normal MCP `initialize` (or any tools/list) request **without** an Authorization header.

### Step 1 – Request hits Azure APIM

- APIM (managed gateway or self-hosted gateway) receives the request.
- Typical policies at this stage (you configure them):
  - Subscription key / API key check (optional).
  - Rate limiting.
  - CORS (if browser-based clients).
  - **Path forwarding**: the self-hosted gateway must forward both the main `/mcp` path **and** all `/.well-known/...` paths unchanged (or with a known rewrite that agentgateway understands).
- APIM does **not** return the MCP 401 itself. It forwards the request (preserving the original path and any headers) to agentgateway.

**Role of APIM here:** front-door security, traffic management, and consistent public hostname. The OAuth discovery stays on agentgateway.

### Step 2 – Agentgateway returns 401 with well-known pointer

Agentgateway’s `mcpAuthentication` (mode: strict) sees no valid JWT and responds:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer resource_metadata="https://your-apim.azure-api.net/my-mcp/.well-known/oauth-protected-resource/mcp"

{"error":"unauthorized","error_description":"JWT token required"}
```

**Important:** The URL inside `resource_metadata` must be reachable by the client. Therefore the self-hosted gateway / APIM must route `/.well-known/oauth-protected-resource/...` to the same agentgateway instance that protects `/mcp`.

### Step 3 – Client fetches Protected Resource Metadata

Client GETs:

```
GET https://your-apim.azure-api.net/my-mcp/.well-known/oauth-protected-resource/mcp
```

Agentgateway (via APIM) returns something like:

```json
{
  "resource": "https://your-apim.azure-api.net/my-mcp/mcp",
  "authorization_servers": ["https://your-apim.azure-api.net/my-mcp"],
  "mcp_protocol_version": "2025-06-18",
  "resource_type": "mcp-server",
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["api://<client-id>/mcp_access"]
}
```

Note that `authorization_servers` points back at the **gateway** (the APIM URL), not directly at `login.microsoftonline.com`. This is intentional so the client continues talking to the facade.

### Step 4 – Client discovers Authorization Server metadata

Client follows the authorization server and requests:

```
GET https://your-apim.azure-api.net/my-mcp/.well-known/oauth-authorization-server
```

(or the path-prefixed form the gateway advertises).

Agentgateway:
1. Fetches Entra’s real OIDC discovery document (`https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration`).
2. Reshapes it into RFC 8414 metadata.
3. Injects `code_challenge_methods_supported: ["S256"]`.
4. Rewrites `authorization_endpoint` and `token_endpoint` to **proxied** URLs that go through agentgateway (so it can strip the `resource` parameter).

### Step 5 – Dynamic Client Registration (short-circuited)

Client POSTs a registration request to the gateway’s registration endpoint.

Because Entra has no DCR endpoint, agentgateway **does not forward** the request. It immediately returns:

```json
{
  "client_id": "<your-pre-registered-client-id>",
  "token_endpoint_auth_method": "none"
}
```

The client is told it is a public client and must use PKCE.

### Step 6 – Authorization Code + PKCE flow (proxied)

1. Client redirects the user (or opens a browser) to the **proxied** authorize endpoint that agentgateway advertised.
2. Agentgateway forwards the request to Entra’s real authorize endpoint **after stripping** the RFC 8707 `resource` parameter.
3. User authenticates and consents in Entra.
4. Entra redirects back with an authorization code.
5. Client exchanges the code at the **proxied** token endpoint.
6. Agentgateway:
   - Strips any `resource` parameter.
   - If you configured `clientSecret` (confidential client), attaches it server-side.
   - Forwards the token request to Entra.
7. Entra returns an access token (JWT) whose `aud` is `api://<client-id>` or the bare client ID, and whose `iss` matches your configured issuer.

### Step 7 – Client presents the token; agentgateway validates and admits

Client retries the original MCP request, now with:

```
Authorization: Bearer <entra-access-token>
```

Agentgateway:
1. Validates the JWT signature against Entra’s JWKS (`https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`).
2. Checks `iss` and `aud` (you should list both `api://<client-id>` and the bare client ID in `audiences`).
3. If valid, removes the authentication requirement and forwards the MCP request to the real backend (stdio or remote MCP server).

From this point the user is authenticated. Any subsequent OBO / token-exchange policy (the “Step 2” we already have) can use this validated token as the subject token.

---

## 5. Minimal Agentgateway Configuration Sketch

```yaml
# yaml-language-server: $schema=https://agentgateway.dev/schema/config
gateways:
  default:
    port: 3000
routes:
  - matches:
      - path: { exact: /mcp }
      - path: { exact: /.well-known/oauth-protected-resource/mcp }
      - path: { pathPrefix: /.well-known/oauth-authorization-server }
    backends:
      - mcp:
          targets:
            - name: my-backend
              # ... your MCP target
    policies:
      cors:
        allowOrigins: ["*"]
        allowHeaders: ["*"]
        exposeHeaders: ["Mcp-Session-Id"]
      mcpAuthentication:
        mode: strict
        issuer: https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0
        audiences:
          - api://${ENTRA_CLIENT_ID}
          - ${ENTRA_CLIENT_ID}
        provider:
          entra: {}
        clientId: ${ENTRA_CLIENT_ID}
        # clientSecret: ${ENTRA_CLIENT_SECRET}   # only for Web/confidential platform
        resourceMetadata:
          resource: https://your-apim.azure-api.net/my-mcp/mcp
          scopesSupported:
            - api://${ENTRA_CLIENT_ID}/mcp_access
          bearerMethodsSupported: [header]
```

**Critical routing note:** The same route (or an additional route) **must** match the well-known paths. Otherwise the client receives 404 when it follows the `WWW-Authenticate` header.

---

## 6. APIM / Self-Hosted Gateway Considerations

- **Path handling:** Ensure the API in APIM (and the self-hosted gateway) forwards:
  - `/mcp`
  - `/.well-known/oauth-protected-resource/...`
  - `/.well-known/oauth-authorization-server/...`
  without stripping the prefix that agentgateway expects.
- **Header propagation:** Forward `Authorization`, `Accept`, `Content-Type`, and any MCP-specific headers.
- **Base path:** If APIM exposes the API under a prefix (e.g. `/my-mcp`), the `resource` value in `resourceMetadata` and the URLs you put in client configuration must use the **public APIM URL**.
- **TLS & networking:** Self-hosted gateway needs network reachability to agentgateway (private VNet, private endpoint, or public ingress).
- **Optional JWT validation at APIM:** You can add a `validate-jwt` policy at APIM for an extra layer, but the authoritative MCP-aware validation (and the 401 that starts the OAuth dance) should stay on agentgateway so the well-known metadata is consistent.

---

## 7. What Happens After This Step

Once the client has a valid Entra access token that agentgateway has accepted, the request is inside the gateway. At this point the existing **On-Behalf-Of (OBO)** virtual-token policies (already documented in this repository under `a2a/policies/virtual-token-entra-obo.yaml` and related docs) can exchange that token for a downstream token if the backend needs a different audience.

This document covers only the **inbound** well-known / SSO path (Step 1).

---

## 8. Quick Verification Checklist

1. Unauthenticated call to the APIM MCP URL returns `401` with `WWW-Authenticate` containing the correct public `resource_metadata` URL.
2. GET of that well-known URL returns JSON with `authorization_servers` pointing at your gateway.
3. GET of the authorization-server well-known returns metadata that contains S256 and proxied endpoints.
4. Client registration returns your pre-registered `client_id`.
5. Full authorization-code + PKCE flow succeeds and the subsequent MCP call is admitted.

---

## References

- [agentgateway Microsoft Entra ID guide](https://agentgateway.dev/docs/standalone/1.5.x/integrations/auth/entra/)
- [MCP Authentication configuration](https://agentgateway.dev/docs/standalone/latest/configuration/security/mcp-authn/)
- [examples/mcp-authentication/README.md](https://github.com/agentgateway/agentgateway/blob/main/examples/mcp-authentication/README.md)
- MCP Authorization specification (well-known protected resource metadata)

---

*Document status: Detailed beginner walkthrough for Step 1 (inbound well-known / Entra provider path). OBO outbound exchange is intentionally left to the existing policies.*
