{{- define "wordpress.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "wordpress.mysqlName" -}}
{{- printf "%s-mysql" (include "wordpress.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.secretName" -}}
{{- printf "%s-mysql-secret" (include "wordpress.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.labels" -}}
app: wordpress
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "wordpress.selectorLabels" -}}
app: wordpress
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
