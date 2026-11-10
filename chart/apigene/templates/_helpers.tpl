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
app.kubernetes.io/version: {{ include "apigene.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: apigene
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "apigene.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apigene.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Every resource goes to namespace.name, or the release namespace when it is empty.
*/}}
{{- define "apigene.namespace" -}}
{{- .Values.namespace.name | default .Release.Namespace }}
{{- end }}

{{- define "apigene.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- .Values.serviceAccount.name | default (include "apigene.fullname" .) }}
{{- else }}
{{- .Values.serviceAccount.name | default "default" }}
{{- end }}
{{- end }}

{{- define "apigene.imageTag" -}}
{{- .Values.imageTag | default .Chart.AppVersion }}
{{- end }}

{{- define "apigene.pullPolicy" -}}
{{- if .Values.images.pullPolicy }}
{{- .Values.images.pullPolicy }}
{{- else if eq (include "apigene.imageTag" .) "latest" }}
{{- "Always" }}
{{- else }}
{{- "IfNotPresent" }}
{{- end }}
{{- end }}

{{- define "apigene.registry" -}}
{{- .Values.images.mirror | default .Values.images.registry | trimSuffix "/" }}
{{- end }}

{{/*
Third-party image reference. With images.mirror set, the image comes from the
mirror under its short name, such as <mirror>/mongo:7.0.45.
Usage: include "apigene.thirdPartyImage" (dict "image" .Values.mongo.image "root" .)
*/}}
{{- define "apigene.thirdPartyImage" -}}
{{- $repository := .image.repository -}}
{{- with .root.Values.images.mirror -}}
{{- $repository = printf "%s/%s" (trimSuffix "/" .) (base $repository) -}}
{{- end -}}
{{- printf "%s:%s" $repository .image.tag }}
{{- end }}

{{/*
Apigene image reference. A digest wins over the tag.
Usage: include "apigene.appImage" (dict "root" . "name" "apigene-backend" "tag" .Values.images.backendTag "digest" .Values.images.digests.backend)
*/}}
{{- define "apigene.appImage" -}}
{{- $registry := include "apigene.registry" .root -}}
{{- if .digest -}}
{{- printf "%s/%s@%s" $registry .name .digest }}
{{- else -}}
{{- printf "%s/%s:%s" $registry .name (.tag | default (include "apigene.imageTag" .root)) }}
{{- end -}}
{{- end }}

{{- define "apigene.backendImage" -}}
{{- include "apigene.appImage" (dict "root" . "name" "apigene-backend" "tag" .Values.images.backendTag "digest" ((.Values.images.digests).backend)) }}
{{- end }}

{{- define "apigene.copilotImage" -}}
{{- include "apigene.appImage" (dict "root" . "name" "apigene-copilot" "tag" .Values.images.copilotTag "digest" ((.Values.images.digests).copilot)) }}
{{- end }}

{{- define "apigene.mcpGwImage" -}}
{{- include "apigene.appImage" (dict "root" . "name" "apigene-mcp-gw" "tag" .Values.images.mcpGwTag "digest" ((.Values.images.digests).mcpGw)) }}
{{- end }}

{{- define "apigene.nginxImage" -}}
{{- include "apigene.appImage" (dict "root" . "name" "apigene-nginx" "tag" .Values.images.nginxTag "digest" ((.Values.images.digests).nginx)) }}
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

{{- define "apigene.bundledMongo" -}}
{{- if and .Values.mongo.enabled (not .Values.externalMongo.enabled) -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.bundledRedis" -}}
{{- if and .Values.redis.enabled (not .Values.externalRedis.enabled) -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.mongoUrl" -}}
{{- if .Values.externalMongo.enabled -}}
{{- .Values.externalMongo.url -}}
{{- else -}}
mongodb://mongo:27017/?directConnection=true
{{- end -}}
{{- end }}

{{/*
MONGO_DB_URL comes from the secret when it carries credentials: bundled MongoDB with
auth, or an external URL (chart secret, or the user's existingSecret).
*/}}
{{- define "apigene.mongoUrlInSecret" -}}
{{- if or (include "apigene.mongoAuthEnabled" .) .Values.externalMongo.enabled -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.redisHost" -}}
{{- if .Values.externalRedis.enabled -}}
{{- required "externalRedis.host is required when externalRedis.enabled=true" .Values.externalRedis.host -}}
{{- else -}}
redis
{{- end -}}
{{- end }}

{{- define "apigene.redisPort" -}}
{{- if .Values.externalRedis.enabled -}}
{{- .Values.externalRedis.port | default 6379 -}}
{{- else -}}
{{- .Values.redis.port | default 6379 -}}
{{- end -}}
{{- end }}

{{- define "apigene.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- include "apigene.fullname" . }}-env
{{- end }}
{{- end }}

{{- define "apigene.validate" -}}
{{- if and (not .Values.auth.existingSecret) (not .Values.auth.secretKey) }}
{{- fail "auth.secretKey is required. Generate one with: openssl rand -hex 32" }}
{{- end }}
{{- if and (include "apigene.mongoAuthEnabled" .) (not .Values.auth.existingSecret) (not .Values.mongo.auth.password) }}
{{- fail "mongo.auth.password is required when mongo.auth.enabled=true" }}
{{- end }}
{{- if and (include "apigene.redisAuthEnabled" .) (not .Values.auth.existingSecret) (not .Values.redis.auth.password) }}
{{- fail "redis.auth.password is required when redis.auth.enabled=true" }}
{{- end }}
{{- if and (eq .Values.auth.provider "keycloak") (not .Values.auth.existingSecret) (not .Values.auth.keycloak.issuer) }}
{{- fail "auth.keycloak.issuer is required when auth.provider=keycloak" }}
{{- end }}
{{- if and .Values.externalMongo.enabled (not .Values.auth.existingSecret) (not .Values.externalMongo.url) }}
{{- fail "externalMongo.url is required when externalMongo.enabled=true (or put MONGO_DB_URL in auth.existingSecret)" }}
{{- end }}
{{- if and .Values.mongo.backup.enabled (not (include "apigene.bundledMongo" .)) }}
{{- fail "mongo.backup works with the bundled MongoDB only; back up an external MongoDB with its own tooling" }}
{{- end }}
{{- if and .Values.ingress.enabled .Values.route.enabled }}
{{- fail "enable either ingress or route, not both" }}
{{- end }}
{{- end }}

{{- define "apigene.mongoAuthEnabled" -}}
{{- if and (include "apigene.bundledMongo" .) .Values.mongo.auth.enabled -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.redisAuthEnabled" -}}
{{- if and (include "apigene.bundledRedis" .) .Values.redis.auth.enabled -}}
true
{{- end -}}
{{- end }}

{{- define "apigene.commonEnv" -}}
{{- if not (include "apigene.mongoUrlInSecret" .) }}
- name: MONGO_DB_URL
  value: {{ include "apigene.mongoUrl" . | quote }}
{{- end }}
- name: REDIS_HOST
  value: {{ include "apigene.redisHost" . | quote }}
- name: REDIS_PORT
  value: {{ include "apigene.redisPort" . | quote }}
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
  value: {{ .Values.backend.uvicornWorkers | default 1 | quote }}
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
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Init containers. Usage: include "apigene.waitForMongoInit" (dict "root" . "component" "backend")
*/}}
{{- define "apigene.initContainerCommon" -}}
image: {{ include "apigene.thirdPartyImage" (dict "image" .Values.initImage "root" .) | quote }}
imagePullPolicy: {{ .Values.initImage.pullPolicy }}
{{- with .Values.initImage.resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
securityContext:
  {{- mergeOverwrite (deepCopy .Values.containerSecurityContext) (deepCopy (.Values.initImage.securityContext | default dict)) | toYaml | nindent 2 }}
{{- end }}

{{- define "apigene.waitForMongoInit" -}}
{{- if include "apigene.bundledMongo" . }}
- name: wait-for-mongo
  {{- include "apigene.initContainerCommon" . | nindent 2 }}
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
{{- if include "apigene.bundledRedis" . }}
- name: wait-for-redis
  {{- include "apigene.initContainerCommon" . | nindent 2 }}
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
  {{- include "apigene.initContainerCommon" . | nindent 2 }}
  command:
    - sh
    - -c
    - |
      until wget -q -O - http://backend:8000/api/health 2>/dev/null | grep -q ok; do
        echo "waiting for backend..."
        sleep 3
      done
{{- end }}

{{/*
Pod template metadata: labels and annotations, with config/secret checksums so a
changed secret or nginx config rolls the pods.
Usage: include "apigene.podMetadata" (dict "root" . "component" "backend" "values" .Values.backend)
*/}}
{{- define "apigene.podMetadata" -}}
{{- $root := .root -}}
labels:
  app.kubernetes.io/component: {{ .component }}
  {{- include "apigene.selectorLabels" $root | nindent 2 }}
  {{- with $root.Values.podLabels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- with .values.podLabels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
annotations:
  checksum/secret: {{ include (print $root.Template.BasePath "/secret.yaml") $root | sha256sum }}
  {{- if eq .component "nginx" }}
  checksum/config: {{ include (print $root.Template.BasePath "/configmap-nginx.yaml") $root | sha256sum }}
  {{- end }}
  {{- if eq .component "mongo" }}
  checksum/config: {{ include (print $root.Template.BasePath "/configmap-mongo.yaml") $root | sha256sum }}
  {{- end }}
  {{- with $root.Values.podAnnotations }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- with .values.podAnnotations }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}

{{/*
Pod-level spec shared by every workload: service account, pull secrets, security
context, scheduling. Component values win over the global ones.
Usage: include "apigene.podSpecCommon" (dict "root" . "component" "backend" "values" .Values.backend)
*/}}
{{- define "apigene.podSpecCommon" -}}
{{- $root := .root -}}
{{- $v := .values -}}
serviceAccountName: {{ include "apigene.serviceAccountName" $root }}
automountServiceAccountToken: {{ $root.Values.serviceAccount.automountToken }}
{{- with $root.Values.images.pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with ($v.priorityClassName | default $root.Values.priorityClassName) }}
priorityClassName: {{ . }}
{{- end }}
securityContext:
  {{- mergeOverwrite (deepCopy $root.Values.podSecurityContext) (deepCopy ($v.podSecurityContext | default dict)) | toYaml | nindent 2 }}
{{- with (mergeOverwrite (deepCopy ($root.Values.nodeSelector | default dict)) (deepCopy ($v.nodeSelector | default dict))) }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with ($v.tolerations | default $root.Values.tolerations) }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with ($v.affinity | default $root.Values.affinity) }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if $v.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml $v.topologySpreadConstraints | nindent 2 }}
{{- else if $root.Values.topologySpread.enabled }}
topologySpreadConstraints:
  {{- range list "topology.kubernetes.io/zone" "kubernetes.io/hostname" }}
  - maxSkew: 1
    topologyKey: {{ . }}
    whenUnsatisfiable: {{ $root.Values.topologySpread.whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        app.kubernetes.io/component: {{ $.component }}
        {{- include "apigene.selectorLabels" $root | nindent 8 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Container security context. Usage: include "apigene.containerSecurityContext" (dict "root" . "values" .Values.backend)
*/}}
{{- define "apigene.containerSecurityContext" -}}
{{- mergeOverwrite (deepCopy .root.Values.containerSecurityContext) (deepCopy (.values.securityContext | default dict)) | toYaml }}
{{- end }}

{{/*
Environment for the Apigene app containers.
Usage: include "apigene.appEnv" (dict "root" . "values" .Values.backend)
*/}}
{{- define "apigene.appEnv" -}}
{{- include "apigene.commonEnv" .root }}
{{- /* Images run as an arbitrary non-root UID, whose home is not writable. */}}
- name: HOME
  value: /tmp
{{- with .values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
