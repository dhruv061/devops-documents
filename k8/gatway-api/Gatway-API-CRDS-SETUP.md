# Step 1: Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Step 2: Install NGINX Gateway Fabric (OCI)
helm install ngf oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --version 1.5.0 \
  --wait
  
# Step 3: Verify
kubectl get pods -n nginx-gateway
kubectl get gatewayclass
