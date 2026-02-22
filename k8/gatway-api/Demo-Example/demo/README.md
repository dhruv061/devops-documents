# Demo: Gateway + HTTPRoute example

This demo creates a namespace, a simple HTTP echo Deployment, a Service, a Gateway, and an HTTPRoute that forwards traffic to the Service.

Prerequisites
- Kubernetes cluster (1.20+ recommended).
- Gateway API CRDs installed.
- A Gateway controller installed and running (Contour, Kong, HAProxy, etc.). The controller will typically register a GatewayClass name — replace `contour` in the example with the name shown by your controller.

What to apply (order matters)
1. `namespace.yaml`
2. `deployment.yaml`
3. `service.yaml`
4. `gateway.yaml`
5. `httproute.yaml`

Apply all manifests with:

```bash
kubectl apply -f demo/namespace.yaml
kubectl apply -f demo/deployment.yaml
kubectl apply -f demo/service.yaml
kubectl apply -f demo/gateway.yaml
kubectl apply -f demo/httproute.yaml
```

How to test
- Wait until the Gateway's listener becomes Ready and the controller reports an address. You can check status with:

```bash
kubectl get gateway -n demo-gateway
kubectl describe gateway demo-gateway -n demo-gateway
```

- The controller will usually publish an external IP or hostname. Use that address to curl the root path `/`:

```bash
curl http://<gateway-address>/
```

If the controller exposes a host-based configuration (for example you set `hosts` in HTTPRoute), use the Host header or DNS accordingly.

Troubleshooting
- If the HTTPRoute is not attached to the Gateway, check `allowedRoutes` and `parentRefs` fields.
- If the Gateway has no addresses, ensure your controller is running and has a corresponding GatewayClass.
- Replace `gatewayClassName: contour` with the class name provided by your controller.
