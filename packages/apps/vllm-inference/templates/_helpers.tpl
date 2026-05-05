{{- define "vllm-inference.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vllm-inference.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "vllm-inference.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "vllm-inference.selectorLabels" -}}
app.kubernetes.io/name: vllm-inference
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
