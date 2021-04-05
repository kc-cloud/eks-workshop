# Create Cluster as described in cluster-config.yml
./create-cluster.sh
#Get Stack name that was used to create the kCluste
STACK_NAME=$(eksctl get nodegroup --cluster kCluster -o json | jq -r '.[0].StackName')
#Extract the Worker nodes' role
ROLE_NAME=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.ResourceType=="AWS::IAM::Role") | .PhysicalResourceId')
#Add the role name to environment variable
echo "export ROLE_NAME=${ROLE_NAME}" | tee -a ~/.bash_profile

## Get the User ARN to map to the EKS user
USER_ARN=$(aws sts get-caller-identity | jq -r '.Arn')

## Map user to the admin user
eksctl create iamidentitymapping --cluster kCluster --arn ${USER_ARN} --group system:masters --username admin

## Deploy Official k8s Dashboard
EKS_STATUS_TOKEN=$(aws eks get-token --cluster-name kCluster | jq -r '.status.token')
export DASHBOARD_VERSION="v2.2.0"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml
kubectl proxy --port=8080 --address=0.0.0.0 --disable-filter=true 
http://localhost:8080/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

## INSTALL KUBE-OPS-VIEW to learn about the various auto-scaling options for your EKS cluster
helm install kube-ops-view stable/kube-ops-view --set service.type=LoadBalancer --set rbac.create=True

## Deploy the Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.4.1/components.yaml
kubectl get apiservice v1beta1.metrics.k8s.io -o json | jq '.status'

## CONFIGURE CLUSTER AUTOSCALER (CA)
## Associate an IAM role with a service account to provide AWS permissions to the containers in any pod that uses that service account
### Enabling IAM roles for service accounts on your cluster
eksctl utils associate-iam-oidc-provider --cluster kCluster --approve
aws iam create-policy --policy-name k8s-asg-policy --policy-document file://k8s-autoscale-policy.json
eksctl create iamserviceaccount \
    --name cluster-autoscaler \
    --namespace kube-system \
    --cluster kCluster \
    --attach-policy-arn "arn:aws:iam::452706865406:policy/k8s-asg-policy" \
    --approve \
    --override-existing-serviceaccounts
### Deploy Autoscaler
kubectl apply -f cluster-autoscaler-autodiscover.yaml

### To prevent CA from removing nodes where its own pod is running
kubectl -n kube-system \
    annotate deployment.apps/cluster-autoscaler \
    cluster-autoscaler.kubernetes.io/safe-to-evict="false"
### update the autoscaler image
export K8S_VERSION=$(kubectl version --short | grep 'Server Version:' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | cut -d. -f1,2)
export AUTOSCALER_VERSION=$(curl -s "https://api.github.com/repos/kubernetes/autoscaler/releases" | grep '"tag_name":' | sed 's/.*-\([0-9][0-9\.]*\).*/\1/' | grep -m1 ${K8S_VERSION})

kubectl -n kube-system \
    set image deployment.apps/cluster-autoscaler \
    cluster-autoscaler=us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v${AUTOSCALER_VERSION}
### Deploy nginx
kubectl apply -f nginx-autoscale-demo.yml
### Increase the number of pods .. which will end-up signaling autoscale to scale-out nodes
kubectl scale --replicas=10 deployment/nginx-to-scaleout

# RBAC
## 1. Create a namespace
## 2. Deploy app to the namespace
## 3. create IAM user, obtain the access key and secrets key
## 4. get aws-auth into a file
kubectl get configmap -n kube-system aws-auth -o yaml > aws-auth.yaml
## 5. add a user map to map the aws user to the k8s user
### data:
###   mapUsers: |
###     - userarn: arn:aws:iam::${ACCOUNT_ID}:user/rbac-user
###       username: rbac-user
## 6. This user doesnt have any permission within the k8s cluster
