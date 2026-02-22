## Gateway API: Full Setup Guide and Example

This folder contains a complete guide to the Kubernetes Gateway API, its core components, and a minimal demo that shows how to expose a simple app via a Gateway and an HTTPRoute.

Contents
- `demo/` - manifests and quick demo README

What this guide covers
- Concepts and components: GatewayClass, Gateway, HTTPRoute, Services/backends, Certificates (cert-manager), and controllers.
- Prerequisites and recommended controllers.
- Step-by-step demo using a small HTTP echo app and a Gateway + HTTPRoute.

High-level contract
- Inputs: a Kubernetes cluster (v1.20+ recommended) and a Gateway controller installed (Contour, Kong, HAProxy, etc.).
- Output: an HTTP route that exposes a demo service via the cluster's gateway.
- Error modes: missing controller, GatewayClass mismatch, RBAC/namespace mismatch.

Quick notes
- The Gateway API defines CRDs only — you must install a Gateway controller (Contour, Kong, HAProxy, or another controller) that implements the API and provides data-plane (Envoy, HAProxy, etc.).
- In the demo manifests `gatewayClassName` is set to a placeholder (`contour`). Replace this with the name provided by your controller.

Useful links
- Gateway API project: https://gateway-api.sigs.k8s.io/
- Gateway API CRDs: https://github.com/kubernetes-sigs/gateway-api
- Contour (example controller): https://projectcontour.io/

See `demo/README.md` for the hands-on example and manifests.

Next steps and follow-ups
- Add TLS via `cert-manager` and a Certificate/Secret referenced by the Gateway listener.
- Show how to package the demo as a Helm chart and deploy with ArgoCD (this repo already contains an `artha-helm-chart` which can be extended).

End of guide overview.
