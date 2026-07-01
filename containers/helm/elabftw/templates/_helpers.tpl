{{/*
Expand the name of the chart.
*/}}
{{- define "elabftw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "elabftw.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "elabftw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elabftw.labels" -}}
helm.sh/chart: {{ include "elabftw.chart" . }}
{{ include "elabftw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elabftw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elabftw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Web component selector labels
*/}}
{{- define "elabftw.web.selectorLabels" -}}
{{ include "elabftw.selectorLabels" . }}
app.kubernetes.io/component: web
{{- end }}

{{/*
MySQL component selector labels
*/}}
{{- define "elabftw.mysql.selectorLabels" -}}
{{ include "elabftw.selectorLabels" . }}
app.kubernetes.io/component: mysql
{{- end }}

{{/*
Redis component selector labels
*/}}
{{- define "elabftw.redis.selectorLabels" -}}
{{ include "elabftw.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "elabftw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "elabftw.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resource names for the individual components.
*/}}
{{- define "elabftw.mysql.fullname" -}}
{{- printf "%s-mysql" (include "elabftw.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "elabftw.redis.fullname" -}}
{{- printf "%s-redis" (include "elabftw.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of the Secret holding sensitive values.
*/}}
{{- define "elabftw.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "elabftw.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Resolve the DB host: explicit override wins, otherwise the bundled mysql service.
*/}}
{{- define "elabftw.dbHost" -}}
{{- if .Values.web.env.DB_HOST }}
{{- .Values.web.env.DB_HOST }}
{{- else if .Values.mysql.enabled }}
{{- include "elabftw.mysql.fullname" . }}
{{- else }}
{{- fail "web.env.DB_HOST must be set when mysql.enabled is false" }}
{{- end }}
{{- end }}

{{/*
Whether the web container serves HTTPS internally (affects probe scheme).
*/}}
{{- define "elabftw.probeScheme" -}}
{{- if eq (toString .Values.web.env.DISABLE_HTTPS) "true" -}}
HTTP
{{- else -}}
HTTPS
{{- end -}}
{{- end }}

{{/*
Validate and return the explicitly configured ingress hosts.
Ingress hosts must be provided via ingress.hosts; there is no implicit fallback.
*/}}
{{- define "elabftw.ingressHosts" -}}
{{- if not .Values.ingress.hosts -}}
{{- fail "ingress.enabled is true but ingress.hosts is not set. Provide ingress.hosts explicitly." -}}
{{- end -}}
{{- toYaml .Values.ingress.hosts -}}
{{- end }}
