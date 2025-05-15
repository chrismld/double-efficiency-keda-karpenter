#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "utils.sh"
CLUSTER_NAME="keda-karpenter"
IAM_ROLE_NAME="karpenter-keda-karpenter"

## Demo Workflow
## - Deploy a default nodepool and ec2nodeclass
## - Deploy a sample application to see Karpenter in action
## - Optimize the CPU and Memory requests => will produce underutilized nodes
## - Move to Graviton instances
## - Move to Spot instances

echo "## - Deploy a default nodepool and ec2nodeclass"

cat << EOF > node-pool-default.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
  labels:
    demo: compute-optimization
spec:
  template:
    metadata:
      labels:
        demo: compute-optimization
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["2"]
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 0s
    budgets:
    - nodes: "100%"
EOF

cat << EOF > ec2nodeclass-default.yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
  labels:
    demo: compute-optimization
spec:
  role: "${IAM_ROLE_NAME}"
  amiSelectorTerms:
    - alias: "bottlerocket@v1.38.0"
  subnetSelectorTerms:          
    - tags:
        karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${CLUSTER_NAME}
  tags:
    Name: karpenter.sh/nodepool/default
    NodeType: "efficient-demo"
EOF

# cmd "cat node-pool-default.yaml"
# cmd "cat ec2nodeclass-default.yaml"
cmd "kubectl apply -f ec2nodeclass-default.yaml"
cmd "kubectl apply -f node-pool-default.yaml"

cmd "echo ..."
echo "## - Deploy a sample application to see Karpenter in action"

cat << EOF > deployment-default.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-workload
  labels:
    demo: compute-optimization
spec:
  selector:
    matchLabels:
      app: inflate-workload
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-workload
        demo: compute-optimization
    spec:
      nodeSelector:
        demo: compute-optimization
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-workload
        resources:
          requests:
            cpu: "1"
            memory: 512M
  strategy:
    type: Recreate
EOF

# cmd "cat deployment-default.yaml"
cmd "kubectl apply -f deployment-default.yaml"
cmd "kubectl scale deployment inflate-workload --replicas=10"

cmd "echo ..."
echo "## - Move to Graviton instances"

cat << EOF > node-pool-default.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
  labels:
    demo: compute-optimization
spec:
  template:
    metadata:
      labels:
        demo: compute-optimization
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64","arm64"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["2"]
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 0s
    budgets:
    - nodes: "100%"
EOF

# cmd "cat node-pool-default.yaml"
cmd "kubectl apply -f node-pool-default.yaml"

cmd "echo ..."
echo "## - Optimize the CPU and Memory requests => will produce underutilized nodes"

cat << EOF > deployment-default.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-workload
  labels:
    demo: compute-optimization
spec:
  selector:
    matchLabels:
      app: inflate-workload
  replicas: 10
  template:
    metadata:
      labels:
        app: inflate-workload
        demo: compute-optimization
    spec:
      nodeSelector:
        demo: compute-optimization
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-workload
        resources:
          requests:
            cpu: "256m"
            memory: 512Mi
EOF

# cmd "cat deployment-default.yaml"
cmd "kubectl apply -f deployment-default.yaml"

cmd "echo ..."
echo "## - Move to Spot instances"

cat << EOF > node-pool-default.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
  labels:
    demo: compute-optimization
spec:
  template:
    metadata:
      labels:
        demo: compute-optimization
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand","spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64","arm64"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["2"]
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 0s
    budgets:
    - nodes: "100%"
EOF

# cmd "cat node-pool-default.yaml"
cmd "kubectl apply -f node-pool-default.yaml"

cmd "echo ..."
echo "Cleaning up ..."
kubectl delete deployment inflate-workload > /dev/null 2>&1 || :
kubectl delete --all nodepool > /dev/null 2>&1 || :
kubectl delete --all ec2nodeclass > /dev/null 2>&1 || :
rm -rf *.yaml