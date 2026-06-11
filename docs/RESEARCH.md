# Sentry Relay on Kubernetes: Helm Chart Research

Researched 2026-06-11 via Artifact Hub API, GitHub/GitLab APIs, Sourcegraph, Docker Hub/GHCR, OperatorHub, TrueCharts/Bitnami/k8s-at-home indexes, Codeberg/Sourcehut, official Sentry docs. 20 agents, every candidate's Chart.yaml/values/templates inspected at source.

## TL;DR

**No maintained, production-grade standalone Relay Helm chart exists anywhere.** Four standalone charts were found; all frozen or abandoned. The one actively maintained chart (sentry-kubernetes/charts) bundles Relay but hardcodes its upstream to the in-cluster Sentry. **Build-or-fork is the #1 option, not a fallback.**

## Ranked Options

| # | Option | Source | Upstream configurable | Credentials persistence | Last activity | Verdict |
|---|--------|--------|----------------------|--------------------------|---------------|---------|
| 1 | **Build from scratch** (or vendor/fork dasmeta) | Reference manifests: [sentry-docs#4975](https://github.com/getsentry/sentry-docs/issues/4975) | Yes | Yes (proper Secret) | n/a | ~200 lines: Deployment + Secret + ConfigMap + Service + HPA + PDB. You own it |
| 2 | **dasmeta/sentry-relay** | [github.com/dasmeta/helm](https://github.com/dasmeta/helm/tree/main/charts/sentry-relay) / [Artifact Hub](https://artifacthub.io/packages/helm/dasmeta/sentry-relay) | Yes (free-form `upstream`) | Stable, but secret_key lands in a **ConfigMap**, no `existingSecret` | Frozen since Oct 2024 (2026 bumps were repo tooling) | Only standalone chart on Artifact Hub. All 3 modes, proxy default. Relay image pinned 24.10.0 (~19mo stale). No config.yml passthrough. README marks non-SaaS use "untested" |
| 3 | **Yurzs/chart-sentry-relay** | [github.com/Yurzs/chart-sentry-relay](https://github.com/Yurzs/chart-sentry-relay) | Yes (README shows self-hosted example) | Best model on paper (`credentials.existingSecret`), but no generation path: default managed install crashloops | 2025-11-25, one-day Copilot-generated, 0 stars | GHCR OCI pull 403 (broken release pipeline), install from git only. Relay 25.5.1. Has `extraConfig` passthrough. Also supports capture mode |
| 4 | **bonch.dev/sentry-relay-helm** | [gitlab.com/bonch.dev/kubernetes/charts/sentry-relay-helm](https://gitlab.com/bonch.dev/kubernetes/charts/sentry-relay-helm) | Yes | Stable but plaintext ConfigMap; empty defaults crashloop | 2024-03-24, dead | DaemonSet-only, default affinity pins to control-plane nodes, relay 22.11.0 (~3.5y stale). Raw config passthrough. Chart.yaml identity is broken (name "sentry", version 17.9.0) |
| 5 | **dossierdata/sentry-relay** | [github.com/dossierdata/sentry-relay](https://github.com/dossierdata/sentry-relay) | Yes | **Broken for managed**: initContainer regenerates creds into emptyDir every pod start | 2023-02-16, no license | Published tgz mispackaged (renders every resource twice). Relay 22.8.0. Reference material only |
| 6 | **sentry-kubernetes/charts `sentry`** (bundled) | [github.com/sentry-kubernetes/charts](https://github.com/sentry-kubernetes/charts) | **No**: upstream template-hardcoded to in-cluster `{release}-web` ([_helper-sentry-relay.tpl L12](https://github.com/sentry-kubernetes/charts/blob/develop/charts/sentry/templates/relay/_helper-sentry-relay.tpl)) | emptyDir + regenerated per pod (works in-bundle only via `SENTRY_RELAY_OPEN_REGISTRATION=True`) | **Active** (chart 32.1.0, 2026-06-09, relay 26.5.0, 1368★) | Healthiest chart in the space but fails standalone use: `processing.enabled: true` hardcoded to stack Kafka/Redis; relay-only render fails ([#1919](https://github.com/sentry-kubernetes/charts/issues/1919) closed not_planned). Unsupported escape hatches exist (`relay.args: ["run","--upstream",...]`, `relay.env`) but still require deploying the whole stack |

## Disqualified / Dead

- **sprisa/sentry-k8s**: full stack, 5 days old, upstream hardcoded, `relay.mode` is dead config, emptyDir creds
- **pluralsh/plural-artifacts**: Plural wrapper of sentry-kubernetes chart, untouched since May 2024
- **operasoftware/sentry-helm-charts**: 686-commits-behind snapshot, dead Nov 2022
- **windycom/sentry-charts**: abandoned fork (May 2023)
- **kanadaj/sentry-operator**: deploys full stack; reconcile loop overwrites relay creds in a ConfigMap
- **digitalsoba/sentry-relay-kubernetes**: empty 2021 stub, zero manifests
- **starixvn/NEXOPS_helm-charts_sentry** (GitLab): appears to be a sentry-kubernetes chart copy, not relay-specific, not deep-inspected
- **Bitnami / TrueCharts / k8s-at-home / OperatorHub / Codeberg / Sourcehut / Docker Hub OCI / GitLab.com**: swept, zero Sentry Relay packaging (Bitnami request closed not-planned: [bitnami/charts#34790](https://github.com/bitnami/charts/issues/34790))

Residual risk: GitHub code-search API rejected anonymous queries (401/429); the vector fell back to Sourcegraph + repo-name search. A relay chart buried in an unindexed misc monorepo could theoretically have been missed, but Sourcegraph's YAML index of `getsentry/relay` surfaced nothing beyond the above.

## Build From Scratch (#1)

Best reference: [sentry-docs#4975](https://github.com/getsentry/sentry-docs/issues/4975), a complete raw-manifest example (Secret with credentials.json, ConfigMap with config.yml, Deployment with relay healthcheck probes, Service, Ingress, PDB).

Encode the official [Operating Guidelines](https://docs.sentry.io/product/relay/operating-guidelines/): 2+ replicas, 2GB RAM min, 4+ cores above 100 req/s. Relay is HTTP-only by design, TLS terminates at Ingress (Sentry staff, [sentry#68034](https://github.com/getsentry/sentry/issues/68034)). Consider a PVC for the on-disk envelope spool/buffer if you need durability through upstream outages. Sentry's own SaaS PoPs: nginx → relay → Envoy on GKE ([blog](https://blog.sentry.io/sentry-points-of-presence-how-we-built-a-distributed-ingestion/)).

Pragmatic middle path: vendor dasmeta's chart (cleanest structure) into your own repo, move credentials into a Secret, set `image.tag` to your Sentry's CalVer release, track `ghcr.io/getsentry/relay` with Renovate (monthly CalVer releases alongside Sentry).

## Sentry-Side Prerequisite (no chart can do this)

**Managed mode** (PII scrubbing, inbound filters, project configs at the edge):
1. Generate a stable keypair ONCE: `relay config init` (creates config.yml + credentials.json; or `relay credentials generate`). Docker: `docker run --rm -it -v "$(pwd)"/config/:/work/.relay/ ghcr.io/getsentry/relay config init`. Mount as a Kubernetes Secret; all replicas share the keypair.
2. Self-hosted Sentry UI: **org Settings → Relays → New Relay Key**, paste public key. Identical on self-hosted, no plan gating.
3. Server side: `SENTRY_RELAY_OPEN_REGISTRATION = True` is the default; internal/processing relays use `relay.static_auth` in conf.yml (`SENTRY_RELAY_WHITELIST_PK` is deprecated).

If auth fails in managed mode, Relay accepts NO events. This is why per-pod regenerated credentials are a kill criterion.

**Proxy mode skips everything above**: no registration, no credentials, forwards with minimal processing (rate limiting still applies). For a private-network forwarding relay to your own Sentry, proxy mode is the low-friction default.

**Static mode is deprecated** (Relay >= 25.9.0; config-dir scrubbing rules must move to the Sentry UI). Any self-hosted Sentry >= 20.6.0 supports external managed relays.

## If Your Sentry Already Runs on sentry-kubernetes/charts (same cluster)

You may not need a second relay: the chart deploys one by default (`relay.enabled: true`, managed mode) and its nginx/ingress already routes all ingest paths to it. Expose that Service over the private network and point SDKs at it. Caveat: recurring managed-mode registration/keepalive failures are documented in that exact setup ([#224](https://github.com/sentry-kubernetes/charts/issues/224), [#517](https://github.com/sentry-kubernetes/charts/issues/517), [#175](https://github.com/sentry-kubernetes/charts/issues/175), [#1250](https://github.com/sentry-kubernetes/charts/issues/1250)); community workaround is switching `relay.mode` to proxy. For a relay in a DIFFERENT cluster pointing back at it, this chart does not work as designed; see ranked options.

## Official Status

No official Sentry Helm chart or k8s manifest for Relay exists. Sentry ships the Docker image (`ghcr.io/getsentry/relay`) and binaries only; self-hosted support is explicitly docker-compose-only ([self-hosted#2607](https://github.com/getsentry/self-hosted/issues/2607): "We only offer support for docker-compose-based setups"). Naming trap: the "sentry-kubernetes" org is community-run, unaffiliated with Sentry; the chart literally named `sentry-kubernetes` is a k8s event-reporter agent, not Relay.

## Recommendation

Proxy-mode relay, own chart: vendor dasmeta or write ~200 lines from the sentry-docs#4975 manifests. Credentials Secret only if/when moving to managed mode (plus the one-time Settings → Relays registration). 2+ replicas, PDB, image tag matched to your Sentry release. Do not adopt any existing standalone chart as a live dependency; all four are effectively dead.
