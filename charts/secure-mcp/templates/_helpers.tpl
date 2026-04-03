{{/*
Common labels
*/}}
{{- define "secure-mcp.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Keycloak internal URL
*/}}
{{- define "secure-mcp.keycloak.internalUrl" -}}
http://keycloak.{{ .Values.keycloak.namespace }}.svc.cluster.local:8080
{{- end }}

{{/*
Keycloak external URL (used for issuer + OAuth browser flow)
When hostname is set, uses external LB; otherwise falls back to internal DNS.
*/}}
{{- define "secure-mcp.keycloak.externalUrl" -}}
{{- if .Values.keycloak.hostname -}}
http://{{ .Values.keycloak.hostname }}:{{ .Values.keycloak.port | default 8080 }}
{{- else -}}
{{ include "secure-mcp.keycloak.internalUrl" . }}
{{- end -}}
{{- end }}

{{/*
Keycloak issuer URL (must match JWT 'iss' claim)
*/}}
{{- define "secure-mcp.keycloak.issuer" -}}
{{ include "secure-mcp.keycloak.externalUrl" . }}/realms/{{ .Values.keycloak.realm.name }}
{{- end }}

{{/*
Keycloak JWKS path
*/}}
{{- define "secure-mcp.keycloak.jwksPath" -}}
/realms/{{ .Values.keycloak.realm.name }}/protocol/openid-connect/certs
{{- end }}

