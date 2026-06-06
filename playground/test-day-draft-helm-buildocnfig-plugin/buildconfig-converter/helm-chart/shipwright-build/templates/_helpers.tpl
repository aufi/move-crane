{{/*
Expand the name of the chart.
*/}}
{{- define "shipwright-build.name" -}}
{{- .Values.buildconfig.name | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "shipwright-build.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "shipwright-build.labels" -}}
helm.sh/chart: {{ include "shipwright-build.chart" . }}
{{ include "shipwright-build.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
converted-from: buildconfig
{{- end }}

{{/*
Selector labels
*/}}
{{- define "shipwright-build.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shipwright-build.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Determine strategy name based on BuildConfig strategy type
*/}}
{{- define "shipwright-build.strategyName" -}}
{{- if eq .Values.buildconfig.strategy.type "Docker" -}}
{{ .Values.conversion.dockerStrategyName }}
{{- else if eq .Values.buildconfig.strategy.type "Source" -}}
{{ .Values.conversion.sourceStrategyName }}
{{- else -}}
buildah
{{- end -}}
{{- end }}

{{/*
Get builder image for Source strategy
Handles ImageStreamTag conversion
*/}}
{{- define "shipwright-build.builderImage" -}}
{{- $from := .Values.buildconfig.strategy.sourceStrategy.from -}}
{{- if eq $from.kind "ImageStreamTag" -}}
  {{- $namespace := $from.namespace | default .Values.buildconfig.namespace -}}
  {{- $parts := splitList ":" $from.name -}}
  {{- $isName := index $parts 0 -}}
  {{- $isTag := "latest" -}}
  {{- if gt (len $parts) 1 -}}
    {{- $isTag = index $parts 1 -}}
  {{- end -}}
  {{- printf "image-registry.openshift-image-registry.svc:5000/%s/%s:%s" $namespace $isName $isTag -}}
{{- else if eq $from.kind "DockerImage" -}}
  {{- $from.name -}}
{{- else -}}
  {{- $from.name -}}
{{- end -}}
{{- end }}

{{/*
Get output image name
Handles ImageStreamTag conversion
*/}}
{{- define "shipwright-build.outputImage" -}}
{{- $output := .Values.buildconfig.output.to -}}
{{- if eq $output.kind "ImageStreamTag" -}}
  {{- $namespace := .Values.buildconfig.namespace -}}
  {{- $parts := splitList ":" $output.name -}}
  {{- $isName := index $parts 0 -}}
  {{- $isTag := "latest" -}}
  {{- if gt (len $parts) 1 -}}
    {{- $isTag = index $parts 1 -}}
  {{- end -}}
  {{- printf "image-registry.openshift-image-registry.svc:5000/%s/%s:%s" $namespace $isName $isTag -}}
{{- else if eq $output.kind "DockerImage" -}}
  {{- $output.name -}}
{{- else -}}
  {{- $output.name -}}
{{- end -}}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "shipwright-build.serviceAccountName" -}}
{{- if .Values.advanced.createServiceAccount -}}
  {{- .Values.advanced.serviceAccountName | default (printf "%s-builder" .Values.buildconfig.name) -}}
{{- else -}}
  {{- "default" -}}
{{- end -}}
{{- end }}
