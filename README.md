# Claude Apps Gateway — Hands-On Lab

The companion repository for the **[Learn the Claude Apps Gateway (Hands-On)](https://devoriales.com](https://devoriales.com/quiz/24/learn-the-claude-apps-gateway-hands-on)**
course on devoriales.com.

You'll stand up a self-hosted
[Claude apps gateway](https://code.claude.com/docs/en/claude-apps-gateway)
behind Keycloak (OIDC), backed by PostgreSQL, entirely on your own machine —
then add RBAC, spend caps, and OpenTelemetry telemetry, one lesson at a time.

> The lesson text lives on devoriales.com. **This repo is the lab you run
> alongside it** — clone it first, then follow the course.

## What you'll build

```
Browser / claude CLI  --https-->  Claude apps gateway  --OIDC-->  Keycloak
                                         |
                                         +--> PostgreSQL (auth state, spend)
                                         +--> OTLP -----> otel-collector
                                         +--> inference -> Anthropic API
                                                            (Bedrock: bonus lesson)
```

## Prerequisites

- Docker and Docker Compose (or Podman — see Lesson 2)
- The native `claude` CLI, **2.1.207 or later** (`claude update`)
- An Anthropic API key
- `curl` and `jq` for the validation scripts
- macOS or Linux (the gateway server binary doesn't run on Windows; WSL2 works)

Pinned component versions are tracked in
[`VERSION_MANIFEST.md`](VERSION_MANIFEST.md) — every version there is a current
GA release, verified directly against the vendor's registry.

## Quick start

```bash
git clone https://github.com/devoriales/claude-apps-gateway-lab.git
cd claude-apps-gateway-lab

cp .env.example .env
# edit .env: set ANTHROPIC_API_KEY and GATEWAY_JWT_SECRET (openssl rand -base64 32)

docker compose up -d
./checks/lesson-01-check.sh
```

Then open the course on devoriales.com and start at Lesson 1.

## How this repo works with the course

Each lesson on devoriales tells you what to change here, then has you verify it:

- **`checks/lesson-NN-check.sh`** — run the matching script at the end of each
  lesson to confirm your stack is in the expected state before moving on.
- **`solutions/lesson-NN/`** — a complete snapshot of the stack at the end of
  each lesson. Use it to catch up or unstick yourself, not as a shortcut past
  the learning.

The lessons walk you through building and editing these files — the goal is to
understand *why* each line of config exists, not just to run it.

## Repo layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | The lab stack — grows one service per lesson |
| `.env.example` | Copy to `.env` and fill in your keys before starting |
| `gateway/` | Gateway `Dockerfile`, `gateway.yaml`, and the Bedrock variant |
| `keycloak/` | Realm export — users, groups, and the OIDC client |
| `otel-collector-config.yaml` | OpenTelemetry Collector config (Lesson 9) |
| `checks/` | One `lesson-NN-check.sh` per lesson — verify you're on track |
| `solutions/` | End-of-lesson snapshots of the whole stack, for catching up |
| `VERSION_MANIFEST.md` | Verified GA versions for every pinned component |

## A note on the credentials in this repo

Everything credential-shaped here — Keycloak admin login, the OIDC client
secret in `keycloak/realm-export.json`, the sample user passwords — is a
**dev-only placeholder for a stack that runs on `localhost`**. It is safe to
read and safe to run locally, and it is **never** suitable for a real
deployment. Your own secrets (`ANTHROPIC_API_KEY`, AWS keys) go in `.env`,
which is gitignored — never commit it.

## License / use

This lab accompanies a free devoriales.com course and is provided for learning.
