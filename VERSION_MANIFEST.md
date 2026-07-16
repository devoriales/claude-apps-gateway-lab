# Version Manifest

Verified: 2026-07-11 (re-checked 2026-07-12)

Every version below was confirmed directly against the vendor's registry or
release API — not inferred from search summaries, which returned at least one
stale/wrong answer during verification (see note under PostgreSQL). All are
current GA releases; no beta, RC, or nightly builds.

| Component | Version | Image / binary reference | Verified against |
|---|---|---|---|
| Claude Code (`claude` binary) | 2.1.207 (locally installed; gateway requires >= 2.1.195) | native binary, standalone install | `claude --version` on this machine |
| Keycloak | 26.7.0 | `quay.io/keycloak/keycloak:26.7.0` | `quay.io` API tag list for `keycloak/keycloak` — `26.7.0` is the newest non-nightly tag |
| PostgreSQL | 18.4 | `postgres:18.4-alpine` (`postgres:18-alpine` resolves to the same digest) | Docker Hub registry API for `library/postgres` — confirmed `18-alpine` and `18.4-alpine` exist, same digest, pushed 2026-07-08 |
| OpenTelemetry Collector (contrib) | 0.156.0 | `otel/opentelemetry-collector-contrib:0.156.0` | Docker Hub tag list (pushed 2026-07-07) **and** GitHub Releases API for `open-telemetry/opentelemetry-collector-releases`, tag `v0.156.0`, `prerelease: false`, published 2026-07-07T14:25:15Z |
| Podman (reference only, Lesson 2) | 6.0.1 | n/a — student's own package manager | `github.com/containers/podman` releases page, latest non-RC release |

## Verification note: don't trust a single source

A WebFetch summary of the Docker Hub postgres tags page initially reported
`17-alpine` as the newest tag. A direct query against the Docker Hub registry
API (`hub.docker.com/v2/repositories/library/postgres/tags`) showed
`18-alpine` and `18.4-alpine` both exist and are current, pushed 2026-07-08 —
one release cycle ahead of what the page summary claimed. Every version in
this manifest was cross-checked against a registry/release API directly, not
just a rendered page or search snippet.

## What this gates

Lesson text and all `docker-compose.yml` / `gateway.yaml` / `Dockerfile` image
tags must match this manifest exactly. If any of these components ship a new
GA release before the course is finalized, re-run the verification steps above
and update both this file and the lab configs together — never let lesson
prose and pinned tags drift apart.
