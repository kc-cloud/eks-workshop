## Download Istio
echo 'export ISTIO_VERSION="1.9.0"' >> ${HOME}/.bash_profile
source ${HOME}/.bash_profile
cd $ISTIO_HOME
curl -L https://istio.io/downloadIstio | sh -
cd istio-${ISTIO_VERSION}
cp -v bin/istioctl /usr/local/bin/
istioctl version --remote=false

## Istio is installed in the istio-system namespace
istioctl manifest apply --set profile=demo

## Injecting the Istio sidecar into a pod to take Istio’s features
### Enable Istio to automatically inject the Sidecar Proxy into a namespace
kubectl create namespace bookinfo
kubectl label namespace bookinfo istio-injection=enabled
kubectl get ns bookinfo --show-labels

## Deploy the sample application into the namespace
kubectl -n bookinfo apply -f samples/bookinfo/platform/kube/bookinfo.yaml

## Make the application accessible from outside of Kubernetes cluster
### Create an Istio Gateway for this purpose.
kubectl -n bookinfo apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
### Extract the URL
export GATEWAY_URL=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://${GATEWAY_URL}/productpage"
