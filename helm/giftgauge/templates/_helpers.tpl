{{/* =========================================================================
Common helpers — used by deployment.yaml, service.yaml, ingress.yaml.
========================================================================= */}}

{{/*
giftgauge.commonLabels — labels that go on every resource.
Standard Kubernetes recommended labels (app.kubernetes.io/*).
*/}}
{{- define "giftgauge.commonLabels" -}}
app.kubernetes.io/name: giftgauge
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: giftgauge
giftgauge.io/environment: {{ .Values.global.environment }}
{{- end -}}

{{/*
giftgauge.serviceLabels — extends commonLabels with a per-service component
label. Lets you select pods for a single service.
Usage: {{- include "giftgauge.serviceLabels" (dict "Values" .Values "Release" .Release "Chart" .Chart "service" "profile") | nindent N }}
*/}}
{{- define "giftgauge.serviceLabels" -}}
{{ include "giftgauge.commonLabels" . }}
app.kubernetes.io/component: {{ .service }}
{{- end -}}

{{/*
giftgauge.serviceImage — fully-qualified image reference for a service.
Constructs <registry>/<repository>:<tag> from global.registry, the per-service
image.repository, and global.imageTag. Per-env values can override imageTag.
*/}}
{{- define "giftgauge.serviceImage" -}}
{{- $svc := index .Values.services .service -}}
{{- printf "%s/%s:%s" .Values.global.registry $svc.image.repository .Values.global.imageTag -}}
{{- end -}}
