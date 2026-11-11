# Step 1: APIM → Agentgateway Entra Well-Known Flow (High-Level Outline)

## Goal
Document the end-to-end inbound SSO path where an AI client reaches agentgateway through Azure APIM, and agentgateway serves Entra-compatible well-known OAuth metadata so MCP clients can authenticate without a separate adapter proxy.

## Layers
1. **Client** — ChatGPT, VS Code extension, or any MCP client.
2. **Azure APIM** — front door with a self-hosted gateway. Terminates TLS, does subscription/API-key checks, rate limits, and routes to agentgateway.
3. **Agentgateway** — MCP/A2A gateway with the native `entra` MCP authentication provider.

## Flow (summary)
1. Client calls the APIM endpoint for the MCP server.
2. APIM self-hosted gateway forwards the request to agentgateway, preserving the Authorization header and path.
3. Agentgateway's `entra` provider returns 401 with a WWW-Authenticate header pointing at `/.well-known/oauth-protected-resource/mcp`.
4. Client fetches that metadata, then the gateway-proxied `/.well-known/oauth-authorization-server` metadata (Entra's openid-configuration reshaped to RFC 8414, with PKCE S256 injected).
5. Client registers via the gateway's short-circuited DCR (returns the pre-registered Entra client ID).
6. Client runs authorization code + PKCE against the gateway-proxied authorize/token endpoints; the gateway strips the RFC 8707 `resource` parameter Entra rejects.
7. Entra issues the token; agentgateway validates it against Entra JWKS and admits the request.

## Open items for the detailed version
- Exact APIM policy XML (validate-jwt vs pass-through, header propagation).
- Self-hosted gateway networking (VNet, private endpoints, ingress to agentgateway).
- agentgateway config.yaml for `provider: entra` behind APIM base path.
- How APIM path rewrites interact with `/.well-known/` routes.
- Token validation audience/issuer alignment between APIM and agentgateway.

## Status
Outline only. Detailed beginner walkthrough to follow.
