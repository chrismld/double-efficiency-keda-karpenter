# Create an EKS Cluster using Terraform

You'll create an Amazon EKS cluster using the [EKS Blueprints for Terraform project](https://github.com/aws-ia/terraform-aws-eks-blueprints). The Terraform template included in this repository is going to create a VPC, an EKS control plane, and a Kubernetes service account along with the IAM role and associate them using IAM Roles for Service Accounts (IRSA) to let Karpenter launch instances. Additionally, the template configures the Karpenter node role to the `aws-auth` configmap to allow nodes to connect, and creates an On-Demand managed node group for the `kube-system` and `karpenter` namespaces.

To create the cluster, clone this repository and open the `cluster/terraform` folder. Then, run the following commands:

```
helm registry logout public.ecr.aws
export TF_VAR_region=$AWS_REGION
terraform init
terraform apply -target="module.vpc" -auto-approve
terraform apply -target="module.eks" -auto-approve
terraform apply --auto-approve
```

Before you continue, you need to enable your AWS account to launch Spot instances if you haven't launch any yet. To do so, create the [service-linked role for Spot](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html#service-linked-roles-spot-instance-requests) by running the following command:

```
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
```

You might see the following error if the role has already been successfully created. You don't need to worry about this error, you simply had to run the above command to make sure you have the service-linked role to launch Spot instances:

```
An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
```

Once complete (after waiting about 15 minutes), run the following command to update the `kube.config` file to interact with the cluster through `kubectl`:

```
aws eks --region $AWS_REGION update-kubeconfig --name karpenter-blueprints
```

You need to make sure you can interact with the cluster and that the Karpenter pods are running:

```
$> kubectl get pods -n karpenter
NAME                       READY STATUS  RESTARTS AGE
karpenter-5f97c944df-bm85s 1/1   Running 0        15m
karpenter-5f97c944df-xr9jf 1/1   Running 0        15m
```

You can now proceed to deploy the default Karpenter NodePool, and deploy any blueprint you want to test.