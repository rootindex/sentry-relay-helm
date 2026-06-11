# sentry-relay

Standalone [Sentry Relay](https://docs.sentry.io/product/relay/) for Kubernetes. Forwards SDK events from inside your cluster to a self-hosted Sentry (or sentry.io) over your private network.

Built per the official [Operating Guidelines](https://docs.sentry.io/product/relay/operating-guidelines/): 2 replicas by default, 2Gi memory per pod, PodDisruptionBudget, health probes on Relay's own healthcheck endpoints, hardened non-root security context (the official image is distroless, uid 65532, and runs with a read-only root filesystem). Relay is HTTP-only by design; TLS terminates at your Ingress.

## Quick start (proxy mode, recommended)

Proxy mode forwards events with minimal processing. No credentials, no registration on the Sentry side.

```bash
helm repo add sentry-relay https://rootindex.github.io/sentry-relay-helm
helm install relay sentry-relay/sentry-relay --set upstream=https://sentry.internal.example.com
```

Point SDK DSNs at the in-cluster service, keeping the key and project id from the DSN your Sentry issued:

```
http://<key>@relay-sentry-relay.<namespace>.svc.cluster.local:3000/<project-id>
```

## Managed mode

Managed mode pulls project configs from the upstream, enabling server-side PII scrubbing and inbound filters at the relay. It needs a stable keypair and a one-time registration.

1. Generate credentials once. The relay image runs as uid 65532, so prepare the mount dir first (add `:z` to the mount on SELinux hosts):

```bash
mkdir relay-config
sudo chown -R 65532:65532 relay-config
docker run --rm -it -v "$PWD/relay-config:/work/.relay" ghcr.io/getsentry/relay config init
```

2. Store them as a Secret (all replicas share the one keypair):

```bash
kubectl create secret generic sentry-relay-credentials --from-file=credentials.json=relay-config/credentials.json
```

3. Register the public key in your Sentry UI: **Organization Settings -> Relays -> New Relay Key**. Until this is done, relay accepts no events AND the readiness probe keeps failing, so register BEFORE installing or `helm install --wait` / `--atomic` will time out. Pods Running but Unready means an auth problem: check `kubectl logs`.

4. Install:

```bash
helm install relay sentry-relay/sentry-relay \
  --set mode=managed \
  --set upstream=https://sentry.internal.example.com \
  --set credentials.existingSecret=sentry-relay-credentials
```

### Credentials rotation

Relay reads credentials only at startup, and editing a Secret in place does not roll pods on its own. The chart adds a `checksum/credentials` annotation (via `lookup`) so a `helm upgrade` after rotation restarts pods, but with plain `kubectl` edits or GitOps template-only renders, run `kubectl rollout restart deployment/<fullname>` yourself. A new keypair also needs re-registration in the Sentry UI, so rotation is inherently a manual ceremony.

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `upstream` | `""` (required) | URL of your Sentry |
| `mode` | `proxy` | `proxy` or `managed` (`static` was removed in Relay 25.9.0) |
| `credentials.existingSecret` | `""` | Secret with `credentials.json`, required for managed mode |
| `config` | `{}` | Deep-merged over the generated `config.yml`, any [Relay option](https://docs.sentry.io/product/relay/options/). Lands in a ConfigMap: no secrets here, use `extraEnv` + `secretKeyRef` with relay env overrides (e.g. `RELAY_UPSTREAM_URL`) instead |
| `replicaCount` | `2` | Ignored when autoscaling is enabled |
| `image.tag` | chart `appVersion` | Relay is CalVer, monthly, versioned with Sentry; keep close to your server release |
| `resources` | 1 CPU / 2Gi | Official minimum is 2GB RAM; 4+ cores above 100 req/s |
| `service.port` | `3000` | |
| `autoscaling.enabled` | `false` | CPU-based HPA; set `targetMemoryUtilizationPercentage` to also scale on memory, usually relay's binding constraint (can flap during upstream outages, complements rather than replaces adequate per-pod memory) |
| `podDisruptionBudget.enabled` | `true` | `minAvailable: 1`, or set `maxUnavailable` (mutually exclusive, `maxUnavailable` wins) |
| `lifecycle` | preStop sleep 5s | Native sleep action, needs Kubernetes >= 1.30; set `null` to disable |
| `ingress.enabled` | `false` | Only needed for traffic from outside the cluster. Any proxy in front of relay must allow 200MB request bodies, e.g. `nginx.ingress.kubernetes.io/proxy-body-size: 200m` |
| `extraEnv`, `extraVolumes`, `extraVolumeMounts` | `[]` | Escape hatches |
| `tests.image` | `busybox:1.37` | Image for the `helm test` pod |

## Notes

- The envelope spool is in-memory by default: events buffered during an upstream outage are lost if a pod restarts. If you enable the disk spool (`config.spool.envelopes.path`), the SQLite spool file MUST be exclusive per pod: a shared PVC across replicas corrupts it (RWX does not help, it is not multi-writer safe). Use a per-pod generic ephemeral volume:

  ```yaml
  config:
    spool:
      envelopes:
        path: /var/lib/relay/spool/envelopes.db
  extraVolumeMounts:
    - name: spool
      mountPath: /var/lib/relay/spool
  extraVolumes:
    - name: spool
      ephemeral:
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 5Gi
  ```

  This survives container crashes but not pod deletion; a truly persistent per-pod spool would need a StatefulSet, which this chart does not provide.
- Upgrades: bump `image.tag` (or chart `appVersion`) monthly alongside your Sentry server; track `ghcr.io/getsentry/relay` with Renovate.
- `ci/` holds the chart-testing install fixture (proxy mode, installable without a live upstream); `examples/` holds non-installable lint/reference values.
