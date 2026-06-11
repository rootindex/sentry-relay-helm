# sentry-relay-helm

A standalone [Sentry Relay](https://docs.sentry.io/product/relay/) Helm chart for Kubernetes.

Run Relay inside your cluster and forward events to a self-hosted Sentry (or sentry.io) over your private network. This fills a real gap: there is no official Sentry Helm chart for Relay, and the community charts that bundle Relay hardcode it to an in-cluster Sentry stack.

## Install

```bash
helm repo add sentry-relay https://rootindex.github.io/sentry-relay-helm
helm install relay sentry-relay/sentry-relay --set upstream=https://sentry.internal.example.com
```

That is a complete proxy-mode install: no credentials, no registration on the Sentry side. Point SDK DSNs at the relay service and you are ingesting.

Full documentation, managed mode setup, and all values: [charts/sentry-relay/README.md](charts/sentry-relay/README.md).

## Highlights

- Proxy mode by default, managed mode (edge PII scrubbing) fully supported
- Built per the official [Operating Guidelines](https://docs.sentry.io/product/relay/operating-guidelines/): 2 replicas, 2Gi per pod, PodDisruptionBudget, Relay's own healthcheck probes
- Hardened out of the box: non-root distroless image, read-only root filesystem, all capabilities dropped, seccomp RuntimeDefault, no service account token
- Any [Relay option](https://docs.sentry.io/product/relay/options/) via a deep-merged `config` value
- Fail-fast validation: missing upstream, managed mode without credentials, and removed modes are template-time errors

## Why this exists

Researched June 2026: every public standalone Relay chart was frozen or abandoned, and the actively maintained sentry-kubernetes umbrella chart cannot point its bundled relay at an external Sentry (closed as not planned upstream). The research notes live in [docs/RESEARCH.md](docs/RESEARCH.md).

## License

[Apache-2.0](LICENSE)

This project is not affiliated with or endorsed by Sentry (Functional Software, Inc.). "Sentry" and "Relay" refer to their products; the chart deploys the official `ghcr.io/getsentry/relay` image unmodified.
