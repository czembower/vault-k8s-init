# Available parameters and their default values for the Vault chart.

global:
  enabled: true
  imagePullSecrets: []
  tlsDisable: true
  openshift: false
  psp:
    enable: false
    annotations: |
      seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default,runtime/default
      apparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default
      seccomp.security.alpha.kubernetes.io/defaultProfileName:  runtime/default
      apparmor.security.beta.kubernetes.io/defaultProfileName:  runtime/default

injector:
  enabled: true
  replicas: ${injector_replicas}
  port: 8080
  leaderElector:
    enabled: true
    image:
      repository: "gcr.io/google_containers/leader-elector"
      tag: "0.4"
    ttl: 60s
  metrics:
    enabled: false
  externalVaultAddr: ""
  image:
    repository: "hashicorp/vault-k8s"
    tag: ${vault_k8s_image_tag}
    pullPolicy: IfNotPresent
  agentImage:
    repository: "vault"
    tag: "1.7.2"
  agentDefaults:
    cpuLimit: "500m"
    cpuRequest: "250m"
    memLimit: "128Mi"
    memRequest: "64Mi"
    template: "map"
  authPath: "auth/kubernetes"
  logLevel: "info"
  logFormat: "standard"
  revokeOnShutdown: false
  namespaceSelector: {}
  objectSelector: {}
  failurePolicy: Ignore
  certs:
    secretName: null
    caBundle: ""
    certName: tls.crt
    keyName: tls.key
  resources: {}
  extraEnvironmentVars: {}
  affinity: |
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: {{ template "vault.name" . }}-agent-injector
              app.kubernetes.io/instance: "{{ .Release.Name }}"
              component: webhook
          topologyKey: kubernetes.io/hostname
  tolerations: |
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
    - key: "kubernetes.azure.com/scalesetpriority"
      operator: "Equal"
      value: "spot"
      effect: "NoSchedule"
  nodeSelector: |
    nodepool: ${node_selector}
  priorityClassName: ""
  annotations: {}
  extraLabels: {}
  hostNetwork: false
  service:
    annotations: {}

server:
  enabled: true
  image:
    repository: "vault"
    tag: ${image_tag}
    pullPolicy: IfNotPresent
  updateStrategyType: "OnDelete"
  logLevel: ""
  logFormat: ""
  resources: {}
  ingress:
    enabled: true
    labels: {}
    annotations: {}
    hosts:
      - host: ${ingress_host}
      - host: vault.query.consul
      - host: vault.service.consul
        paths: []
    extraPaths: []
    tls:
      - hosts:
        - ${ingress_host}
        - vault.query.consul
        - vault.service.consul
        secretName: vault-cert
  route:
    enabled: false
    labels: {}
    annotations: {}
    host: chart-example.local
  authDelegator:
    enabled: true
  extraInitContainers: null
  extraContainers: null
  shareProcessNamespace: false
  extraArgs: ""
  readinessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"
    failureThreshold: 2
    initialDelaySeconds: 5
    periodSeconds: 5
    successThreshold: 1
    timeoutSeconds: 3
  livenessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true"
    failureThreshold: 2
    initialDelaySeconds: 60
    periodSeconds: 5
    successThreshold: 1
    timeoutSeconds: 3
  preStopSleepSeconds: 5
  postStart:
    - "sh"
    - "-c"
    - "sleep 10; if [[ $(hostname | grep 0) ]] && [[ $(vault status -format json | grep initialized | awk {'print $2'}) == 'false,' ]]; then vault operator init > /home/vault/init-output; fi;"
  extraEnvironmentVars: {}
  extraSecretEnvironmentVars: []
  extraVolumes: []
  volumes: null
  volumeMounts: null
  affinity: |
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: {{ template "vault.name" . }}
              app.kubernetes.io/instance: "{{ .Release.Name }}"
              component: server
          topologyKey: kubernetes.io/hostname
  tolerations: |
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
    - key: "kubernetes.azure.com/scalesetpriority"
      operator: "Equal"
      value: "spot"
      effect: "NoSchedule"
  nodeSelector: |
    nodepool: ${node_selector}
  networkPolicy:
    enabled: false
    egress: []
  priorityClassName: ""
  extraLabels: {}
  annotations: {}
  service:
    enabled: true
    port: 8200
    targetPort: 8200
    annotations: {}
  dataStorage:
    enabled: true
    size: 10Gi
    mountPath: "/vault/data"
    storageClass: null
    accessMode: ReadWriteOnce
    annotations: {}
  auditStorage:
    enabled: false
    size: 10Gi
    mountPath: "/vault/audit"
    storageClass: null
    accessMode: ReadWriteOnce
    annotations: {}
  dev:
    enabled: false
    devRootToken: "root"
  standalone:
    enabled: false
    config: null
  ha:
    enabled: true
    replicas: ${server_replicas}
    #apiAddr: null
    raft:
      enabled: true
      setNodeId: true
      config: |
        disable_mlock = true
        ui = true
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
          telemetry {
            unauthenticated_metrics_access = true
          }
        }
        storage "raft" {
          path = "/vault/data"
            retry_join {
            leader_api_addr = "http://primary-vault-0.primary-vault-internal.vault.svc.cluster.local:8200"
          }
          retry_join {
            leader_api_addr = "http://primary-vault-1.primary-vault-internal.vault.svc.cluster.local:8200"
          }
          retry_join {
            leader_api_addr = "http://primary-vault-2.primary-vault-internal.vault.svc.cluster.local:8200"
          }
          autopilot {
            cleanup_dead_servers = "true"
            last_contact_threshold = "200ms"
            last_contact_failure_threshold = "10m"
            max_trailing_logs = 250000
            min_quorum = 5
            server_stabilization_time = "10s"
          }
        }
        service_registration "kubernetes" {}
        seal "azurekeyvault" {
          tenant_id  = "${tenant_id}"
          vault_name = "${keyvault_name}"
          key_name   = "${key_name}"
        }
        telemetry {
          prometheus_retention_time = "1m"
          disable_hostname = true
        }
    #config: null
    disruptionBudget:
      enabled: true
      maxUnavailable: 2
  serviceAccount:
    create: true
    name: ""
    annotations: {}
  statefulSet:
    annotations: {}

ui:
  enabled: true
  publishNotReadyAddresses: true
  activeVaultPodOnly: false
  serviceType: "ClusterIP"
  serviceNodePort: null
  externalPort: 8200
  targetPort: 8200
  annotations: {}

csi:
  enabled: false
  image:
    repository: "hashicorp/vault-csi-provider"
    tag: "0.2.0"
    pullPolicy: IfNotPresent
  volumes: null
  volumeMounts: null
  resources: {}
  daemonSet:
    updateStrategy:
      type: RollingUpdate
      maxUnavailable: ""
    annotations: {}
  pod:
    annotations: {}
    tolerations: |
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      - key: "kubernetes.azure.com/scalesetpriority"
        operator: "Equal"
        value: "spot"
        effect: "NoSchedule"
  serviceAccount:
    annotations: {}
  readinessProbe:
    failureThreshold: 2
    initialDelaySeconds: 5
    periodSeconds: 5
    successThreshold: 1
    timeoutSeconds: 3
  livenessProbe:
    failureThreshold: 2
    initialDelaySeconds: 5
    periodSeconds: 5
    successThreshold: 1
    timeoutSeconds: 3
  debug: false
  extraArgs: []
