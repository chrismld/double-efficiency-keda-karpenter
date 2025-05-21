#!/usr/bin/env bash

# simple script to setup a demo k3d cluster with kedify in offline mode and deploying a sample app
# requirements: k3d, helm, kubectl

set -euo pipefail

k3d cluster create --k3s-arg "--kube-controller-manager-arg=horizontal-pod-autoscaler-sync-period=1s@server:*"
helm repo add kedifykeda https://kedify.github.io/charts

helm upgrade --install keda kedifykeda/keda --namespace keda --create-namespace --version v2.17.1-0 --values <(cat << EOF
watchNamespace: ''
image:
  pullPolicy: IfNotPresent
env:
  - name: KEDIFY_SCALINGGROUPS_ENABLED
    value: "true"
EOF
)
helm upgrade --install keda-add-ons-http kedifykeda/keda-add-ons-http --namespace keda --version v0.10.0-7 --values <(cat << EOF
scaler:
  pullPolicy: IfNotPresent
interceptor:
  pullPolicy: IfNotPresent
  replicas:
    min: 1
    max: 1
EOF
)
kubectl --namespace=keda set env deployment/keda-add-ons-http-interceptor KEDIFY_EXCLUDE_INTERCEPTOR_METRICS=true
kubectl --namespace=keda set image deployment/keda-add-ons-http-interceptor keda-add-ons-http-interceptor=wozniakjan/http-add-on-interceptor:kcd-2025

helm upgrade --install kedify-agent kedifykeda/kedify-agent --namespace keda --create-namespace --version v0.2.7 --values <(cat << EOF
clusterName: kcd-2025
agent:
  orgId: "00000000-0000-0000-0000-000000000000"
  agentId: "00000000-0000-0000-0000-000000000000"
  apiKey: "kfy_0000000000000000000000000000000000000000000000000000000000000000"
  extraArgs:
    offline: true
EOF
)

cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: default
spec:
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: ghcr.io/kedify/sample-http-server:latest
          imagePullPolicy: IfNotPresent
EOF

cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app
  namespace: default
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: app
  type: ClusterIP
EOF

cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  namespace: default
spec:
  rules:
  - host: demo.keda
    http:
      paths:
      - backend:
          service:
            name: app
            port:
              number: 8080
        path: /
        pathType: Prefix
EOF

while ! kubectl wait --for=condition=established --timeout=5m crd/scaledobjects.keda.sh; do sleep 5; done

cat << 'EOF' | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: app 
  namespace: default
spec:
  maxReplicaCount: 5
  minReplicaCount: 0
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  triggers:
  - metadata:
      hosts: demo.keda
      pathPrefixes: /
      port: "8080"
      scalingMetric: requestRate
      service: app
      targetValue: "10"
      window: "10s"
    metricType: AverageValue
    type: kedify-http
EOF

kubectl patch scaledobject app -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleDown":{"stabilizationWindowSeconds": 5}}}}}}'
kubectl patch scaledobject app -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleUp":{"stabilizationWindowSeconds": 1}}}}}}'
kubectl patch scaledobject app -n default --type=merge -p='{"spec":{"cooldownPeriod": 5}}'

docker pull ghcr.io/kedify/sample-http-server:latest
k3d image import ghcr.io/kedify/sample-http-server:latest

kubectl wait -ndefault --for=jsonpath='{.status.loadBalancer.ingress}' ingress/app --timeout=5m
while ! kubectl wait -ndefault --timeout=5m --for=condition=Available deployment/kedify-proxy; do sleep 5; done
kubectl wait -ndefault --timeout=5m --for=jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}="kedify-proxy"' ingress/app

sudo sed -i.bak "/demo.keda/d" /etc/hosts
IP=$(kubectl get ingress app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "${IP} demo.keda" | sudo tee -a /etc/hosts
