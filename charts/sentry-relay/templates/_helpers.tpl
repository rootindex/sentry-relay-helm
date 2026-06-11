{{- define "sentry-relay.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sentry-relay.fullname" -}}
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

{{- define "sentry-relay.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sentry-relay.labels" -}}
helm.sh/chart: {{ include "sentry-relay.chart" . }}
{{ include "sentry-relay.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sentry-relay.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sentry-relay.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "sentry-relay.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sentry-relay.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "sentry-relay.mode" -}}
{{- if not (has .Values.mode (list "managed" "proxy")) }}
{{- fail (printf "mode must be managed or proxy (static mode was removed in Relay 25.9.0); got %q" .Values.mode) }}
{{- end }}
{{- if and (eq .Values.mode "managed") (not .Values.credentials.existingSecret) }}
{{- fail "managed mode requires credentials.existingSecret (a Secret containing credentials.json generated via `relay config init`)" }}
{{- end }}
{{- .Values.mode }}
{{- end }}

{{- define "sentry-relay.config" -}}
{{- $upstream := required "upstream is required: set it to the URL of your Sentry, e.g. https://sentry.internal.example.com" .Values.upstream }}
{{- $relay := dict "upstream" $upstream "host" "0.0.0.0" "port" 3000 "mode" (include "sentry-relay.mode" .) }}
{{- $defaults := dict "relay" $relay }}
{{- mustMergeOverwrite $defaults (default (dict) .Values.config) | toYaml }}
{{- end }}

{{- define "sentry-relay.port" -}}
{{- (include "sentry-relay.config" . | fromYaml).relay.port }}
{{- end }}
