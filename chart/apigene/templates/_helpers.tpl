{{/*
Expand the name of the chart.
*/}}
{{- define "apigene.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "apigene.fullname" -}}
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

{{- define "apigene.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "apigene.labels" -}}
helm.sh/chart: {{ include "apigene.chart" . }}
{{ include "apigene.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "apigene.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apigene.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "apigene.namespace" -}}
{{- .Values.namespace.name }}
{{- end }}

{{- define "apigene.imageTag" -}}
{{- .Values.imageTag | default .Chart.AppVersion }}
{{- end }}

{{- define "apigene.registry" -}}
{{- .Values.images.mirror | default .Values.images.registry | trimSuffix "/" }}
{{- end }}

{{/*
Third-party image reference. With images.mirror set, the image comes from the
mirror under its short name, such as <mirror>/mongo:7.
Usage: include "apigene.thirdPartyImage" (dict "image" .Values.mongo.image "root" .)
*/}}
{{- define "apigene.thirdPartyImage" -}}
{{- $repository := .image.repository -}}
{{- with .root.Values.images.mirror -}}
{{- $repository = printf "%s/%s" (trimSuffix "/" .) (base $repository) -}}
{{- end -}}
{{- printf "%s:%s" $repository .image.tag }}
{{- end }}

{{- define "apigene.backendImage" -}}
{{- $registry := include "apigene.registry" . -}}
{{- $tag := .Values.images.backendTag | default (include "apigene.imageTag" .) -}}
{{- printf "%s/apigene-backend:%s" $registry $tag }}
{{- end }}

{{- define "apigene.copilotImage" -}}
{{- $registry := include "apigene.registry" . -}}
{{- $tag := .Values.images.copilotTag | default (include "apigene.imageTag" .) -}}
{{- printf "%s/apigene-copilot:%s" $registry $tag }}
{{- end }}

{{- define "apigene.mcpGwImage" -}}
{{- $registry := include "apigene.registry" . -}}
{{- $tag := .Values.images.mcpGwTag | default (include "apigene.imageTag" .) -}}
{{- printf "%s/apigene-mcp-gw:%s" $registry $tag }}
{{- end }}

{{- define "apigene.nginxImage" -}}
{{- $registry := include "apigene.registry" . -}}
{{- $tag := .Values.images.nginxTag | default (include "apigene.imageTag" .) -}}
{{- printf "%s/apigene-nginx:%s" $registry $tag }}
{{- end }}

{{- define "apigene.publicUrl" -}}
{{- if .Values.publicUrl -}}
{{- .Values.publicUrl | trimSuffix "/" -}}
{{- else -}}
{{- printf "http://localhost:%v" .Values.service.port -}}
{{- end -}}
{{- end }}

{{- define "apigene.allowedOrigins" -}}
{{- if .Values.allowedOrigins -}}
{{- .Values.allowedOrigins -}}
{{- else -}}
{{- include "apigene.publicUrl" . -}}
{{- end -}}
{{- end }}

{{- define "apigene.publicUrlHost" -}}
{{- $parsed := urlParse (include "apigene.publicUrl" .) -}}
{{- regexReplaceAll ":[0-9]+$" $parsed.host "" -}}
{{- end }}

{{- define "apigene.copilotHostAliases" -}}
{{- if and .Values.copilot.internalPublicUrlHostAlias .Values.nginx.enabled -}}
{{- $nginx := lookup "v1" "Service" (include "apigene.namespace" .) "nginx" -}}
{{- $host := include "apigene.publicUrlHost" . -}}
{{- if and $nginx $host -}}
hostAliases:
  - ip: {{ $nginx.spec.clusterIP | quote }}
    hostnames:
      - {{ $host | quote }}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "apigene.mongoUrl" -}}
{{- if .Values.externalMongo.enabled -}}
{{- required "externalMongo.url is required when externalMongo.enabled=true" .Values.externalMongo.url -}}
{{- else -}}
mongodb://mongo:27017/?directConnection=true
{{- end -}}
{{- end }}

{{- define "apigene.redisHost" -}}
{{- if .Values.externalRedis.enabled -}}
{{- required "externalRedis.host is required when externalRedis.enabled=true" .Values.externalRedis.host -}}
{{- else -}}
redis
{{- end -}}
{{- end }}

{{- define "apigene.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- include "apigene.fullname" . }}-env
{{- end }}
{{- end }}

{{- define "apigene.validateAuth" -}}
{{- if and (not .Values.auth.existingSecret) (not .Values.auth.secretKey) }}
{{- fail "auth.secretKey is required. Generate one with: openssl rand -hex 32" }}
{{- end }}
{{- if and (include "apigene.mongoAuthEnabled" .) (not .Values.auth.existingSecret) (not .Values.mongo.auth.password) }}
{{- fail "mongo.auth.password is required when mongo.auth.enabled=true" }}
{{- end }}
{{- if and (eq .Values.auth.provider "keycloak") (not .Values.auth.existingSecret) (not .Values.auth.keycloak.issuer) }}
{{- fail "auth.keycloak.issuer is required when auth.provider=keycloak" }}
{{- end }}
{{- end }}

{{- define "apigene.mongoAuthEnabled" -}}
{{- if and .Values.mongo.enabled .Values.mongo.auth.enabled (not .Values.externalMongo.enabled) -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.commonEnv" -}}
{{- /* With MongoDB auth the URL holds a password, so it comes from the secret. */ -}}
{{- if not (include "apigene.mongoAuthEnabled" .) }}
- name: MONGO_DB_URL
  value: {{ include "apigene.mongoUrl" . | quote }}
{{- end }}
- name: REDIS_HOST
  value: {{ include "apigene.redisHost" . | quote }}
- name: REDIS_PORT
  value: {{ .Values.redis.port | default .Values.externalRedis.port | quote }}
- name: REDIS_CACHE_DB
  value: "1"
- name: TENANT_NAME
  value: {{ .Values.tenantName | quote }}
- name: DEPLOYMENT_TYPE
  value: {{ .Values.deploymentType | quote }}
- name: LICENSE_ALGORITHM
  value: {{ .Values.license.algorithm | default "RS256" | quote }}
- name: DATABASE_ENV
  value: {{ .Values.databaseEnv | quote }}
- name: UVICORN_WORKERS
  value: "1"
- name: NEXT_PUBLIC_SERVER_BASE_URL
  value: {{ include "apigene.publicUrl" . | quote }}
- name: ALLOWED_ORIGINS
  value: {{ include "apigene.allowedOrigins" . | quote }}
- name: NEXT_PUBLIC_AUTH_PROVIDER
  value: {{ .Values.auth.provider | quote }}
- name: CACHE_ENABLED
  value: {{ .Values.cache.enabled | quote }}
- name: LOG_ENV
  value: {{ .Values.logging.env | quote }}
{{- with .Values.auth.keycloak.issuer }}
- name: AUTH_KEYCLOAK_ISSUER
  value: {{ . | quote }}
- name: KEYCLOAK_ISSUER
  value: {{ . | quote }}
- name: AUTH_KEYCLOAK_ALLOWED_CLIENTS
  value: {{ $.Values.auth.keycloak.allowedClients | default $.Values.auth.keycloak.clientId | quote }}
- name: KEYCLOAK_CLIENT_ID
  value: {{ $.Values.auth.keycloak.clientId | quote }}
- name: KEYCLOAK_SCOPES
  value: {{ $.Values.auth.keycloak.scopes | quote }}
- name: NEXT_PUBLIC_KEYCLOAK_REDIRECT_URI
  value: {{ $.Values.auth.keycloak.redirectUri | default (printf "%s/client-api/auth/keycloak/callback" (include "apigene.publicUrl" $)) | quote }}
{{- end }}
{{- end }}

{{- define "apigene.waitForMongoInit" -}}
{{- if and .Values.mongo.enabled (not .Values.externalMongo.enabled) }}
- name: wait-for-mongo
  image: {{ include "apigene.thirdPartyImage" (dict "image" .Values.initImage "root" .) | quote }}
  imagePullPolicy: {{ .Values.initImage.pullPolicy }}
  command:
    - sh
    - -c
    - |
      until nc -z mongo 27017; do
        echo "waiting for mongo..."
        sleep 2
      done
{{- end }}
{{- end }}

{{- define "apigene.waitForRedisInit" -}}
{{- if and .Values.redis.enabled (not .Values.externalRedis.enabled) }}
- name: wait-for-redis
  image: {{ include "apigene.thirdPartyImage" (dict "image" .Values.initImage "root" .) | quote }}
  imagePullPolicy: {{ .Values.initImage.pullPolicy }}
  command:
    - sh
    - -c
    - |
      until nc -z redis {{ .Values.redis.port }}; do
        echo "waiting for redis..."
        sleep 2
      done
{{- end }}
{{- end }}

{{- define "apigene.waitForBackendInit" -}}
- name: wait-for-backend
  image: {{ include "apigene.thirdPartyImage" (dict "image" .Values.initImage "root" .) | quote }}
  imagePullPolicy: {{ .Values.initImage.pullPolicy }}
  command:
    - sh
    - -c
    - |
      until wget -q -O - http://backend:8000/api/health 2>/dev/null | grep -q ok; do
        echo "waiting for backend..."
        sleep 3
      done
{{- end }}

{{- define "apigene.imagePullSecrets" -}}
{{- with .Values.images.pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "apigene.nodeScheduling" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
