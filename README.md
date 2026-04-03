# secure-mcp-using-agentgateway-proxy

Helm chart for securing MCP (Model Context Protocol) servers with [agentgateway](https://agentgateway.dev/) proxy and Keycloak OAuth 2.0.

## Features

- Protect any MCP server (in-cluster or remote endpoint) with OAuth 2.0 authentication
- Token-swap pattern: validates client JWT, injects backend-specific bearer token
- CEL-based per-tool authorization
- Dynamic Client Registration (RFC 7591)
- TLS support for remote HTTPS endpoints
- Keycloak as the identity provider with configurable realms, users, and groups

## Add the Helm Repository

```bash
helm repo add secure-mcp https://chandramohan0316.github.io/secure-mcp-using-agentgateway-proxy/
helm repo update
```

## Install

See [charts/secure-mcp/README.md](charts/secure-mcp/README.md) for full installation instructions and configuration reference.

```bash
# Quick start (two-step install)
helm install secure-mcp secure-mcp/secure-mcp \
  --namespace secure-mcp --create-namespace \
  --set 'mcpServers[0].name=my-mcp' \
  --set 'mcpServers[0].type=remote' \
  --set 'mcpServers[0].host=api.example.com' \
  --set 'mcpServers[0].port=443' \
  --set 'mcpServers[0].path=/mcp/' \
  --set 'mcpServers[0].tls=true' \
  --set 'mcpServers[0].backendToken=<your-token>'

# Then set Keycloak hostname (see chart README for details)
KC_HOST=$(kubectl -n secure-mcp get svc keycloak -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
helm upgrade secure-mcp secure-mcp/secure-mcp -n secure-mcp --reuse-values --set keycloak.hostname=$KC_HOST
```

## Architecture

```
MCP Client (Claude, etc.)
    |
agentgateway (Envoy-based, port 8080)
    |-- OAuth discovery (RFC 8414, RFC 9728)
    |-- JWT validation against Keycloak JWKS
    |-- CEL per-tool authorization
    |-- Token-swap: client JWT -> backend bearer token
    |
    +-- MCP Server (deployment or remote)
    |
Keycloak (OAuth 2.0 IdP)
```