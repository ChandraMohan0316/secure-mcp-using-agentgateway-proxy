# secure-mcp Helm Chart

Deploys a complete secure MCP (Model Context Protocol) stack on Kubernetes using **agentgateway** (Envoy-based MCP gateway) with **Keycloak** as the OAuth 2.0 identity provider.

Supports two server types:
- **`deployment`** — runs an MCP server container in-cluster
- **`remote`** — proxies to an external MCP endpoint (e.g., GitHub Copilot MCP)

Auth pattern: **token-swap** — validates client OAuth JWT, strips it, injects a backend-specific bearer token.

## Prerequisites

- Kubernetes 1.27+
- Helm 3.12+
- AWS EKS with AWS Load Balancer Controller (for NLB provisioning)

## Installation (Two-Step)

A fresh install requires two steps because the Keycloak LoadBalancer hostname is not known until the Service is created.

### Step 1: Install the chart

```bash
helm dependency update helm/secure-mcp/

helm upgrade --install secure-mcp helm/secure-mcp/ \
  --namespace secure-mcp --create-namespace \
  --set 'mcpServers[0].backendToken=<your-backend-token>'
```

Wait for the Keycloak pod to become ready:

```bash
kubectl -n secure-mcp rollout status deployment/keycloak --timeout=180s
```

### Step 2: Set the Keycloak hostname

Retrieve the Keycloak LoadBalancer hostname and upgrade:

```bash
KC_HOST=$(kubectl -n secure-mcp get svc keycloak \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

helm upgrade secure-mcp helm/secure-mcp/ \
  --namespace secure-mcp \
  --reuse-values \
  --set keycloak.hostname=$KC_HOST
```

This sets `KC_HOSTNAME` in Keycloak so that OAuth browser redirects (login, consent) use the externally-accessible URL instead of the internal cluster DNS.

### Verify

```bash
# Gateway URL
GW=$(kubectl -n secure-mcp get svc agentgateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MCP endpoint: http://$GW:8080/<server-name>"

# Test 401 response
curl -s http://$GW:8080/<server-name>
```

## Alternative Hostname Approaches

### Custom DNS with ACM certificates (recommended for production)

Pre-create a Route53 CNAME pointing to a stable hostname (e.g., `keycloak.example.com`). This eliminates the two-step install since the hostname is known upfront:

```bash
helm upgrade --install secure-mcp helm/secure-mcp/ \
  --namespace secure-mcp --create-namespace \
  --set keycloak.hostname=keycloak.example.com \
  --set 'mcpServers[0].backendToken=<token>'
```

Add ACM certificate annotations to the Keycloak Service for HTTPS:

```yaml
keycloak:
  hostname: keycloak.example.com
```

### Auto-discovery via hook job

It is possible to extend the existing `keycloak-realm-config` hook job to auto-discover the LoadBalancer hostname and patch the Keycloak deployment with `KC_HOSTNAME`. This would make installation fully single-step without custom DNS.

## Configuration

### Subchart toggles

If agentgateway CRDs and controller are already installed in your cluster:

```bash
--set agentgateway-crds.enabled=false \
--set agentgateway.enabled=false
```

### Namespace overrides

By default, Keycloak deploys to the `keycloak` namespace and the gateway to `agentgateway-system`. Override for isolation:

```bash
--set keycloak.namespace=my-namespace \
--set gateway.namespace=my-namespace
```

### MCP Servers

Defined in `values.yaml` under `mcpServers`. Each entry generates:
- `AgentgatewayBackend` — upstream target configuration
- `AgentgatewayPolicy` — JWT validation + CEL authorization + TLS
- `HTTPRoute` — routes traffic through agentgateway

For `type: deployment`, additionally generates:
- `Deployment`, `Service`, `ConfigMap`, `Secret`

#### Remote endpoint example

```yaml
mcpServers:
  - name: github-mcp
    type: remote
    host: api.githubcopilot.com
    port: 443
    path: /mcp/
    tls: true                    # enables TLS to upstream
    sessionRouting: Stateless
    backendToken: ""             # GitHub PAT — pass via --set
```

#### In-cluster deployment example

```yaml
mcpServers:
  - name: my-mcp-server
    type: deployment
    namespace: default
    image:
      repository: my-registry/my-mcp-server
      tag: latest
    replicas: 2
    port: 3000
    path: /mcp
    backendToken: ""             # pass via --set
    env:
      - name: AUTH_ENABLED
        value: "false"
    envSecrets:                  # stored in K8s Secret
      API_KEY: ""                # pass via --set
    configFiles:
      - mountPath: /app/config.yaml
        fileName: config.yaml
        content: |
          key: value
```

### Authorization (CEL rules)

Global default rules apply to all servers unless overridden per-server:

```yaml
authorization:
  defaultRules:
    - expression: 'true'                        # allow all authenticated users
    # - expression: 'jwt.group == "engineers"'   # restrict to engineers group
```

Per-server override:

```yaml
mcpServers:
  - name: my-server
    authorization:
      rules:
        - expression: 'jwt.sub == "admin"'
```

Available CEL variables: `jwt`, `jwt.sub`, `jwt.group`, `request`, `request.path`, `mcp_tool`, `mcp_tool.name`.

### Keycloak

| Value | Description | Default |
|-------|-------------|---------|
| `keycloak.hostname` | External LB hostname for OAuth browser flow | `""` (internal DNS) |
| `keycloak.adminPassword` | Admin console password | `admin` |
| `keycloak.realm.name` | OAuth realm name | `mcp` |
| `keycloak.realm.users` | Test users with group assignments | user1/engineers, user2/viewers |

### Post-install realm configuration

A Helm hook job runs after install/upgrade to:
1. Remove the "Trusted Hosts" DCR policy (allows Dynamic Client Registration from any host)
2. Remove the "Allowed Client Scopes" DCR policy (allows MCP clients to request needed scopes)
3. Add a `group` protocol mapper to the `profile` client scope (includes user group in JWT)

## Architecture

```
MCP Client (Claude, etc.)
    |
agentgateway (Envoy-based, port 8080)
    |-- Serves OAuth discovery (RFC 8414, RFC 9728)
    |-- Proxies Dynamic Client Registration (RFC 7591) to Keycloak
    |-- Validates JWTs against Keycloak JWKS
    |-- Enforces CEL-based per-tool authorization
    |-- Token-swap: strips client JWT, injects backend bearer token
    |-- TLS to upstream (for remote endpoints on port 443)
    |
    +-- MCP Server (deployment or remote)
    |
Keycloak (OAuth 2.0 IdP, realm: "mcp")
```

## Uninstalling

```bash
helm uninstall secure-mcp -n secure-mcp
kubectl delete namespace secure-mcp
```
