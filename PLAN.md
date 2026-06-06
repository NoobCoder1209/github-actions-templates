# `github-actions-templates` — Execution Plan

> Tier 2 shelf — built opportunistically, not pinned. Inherits shared standards
> from the master plan.

## Goal

A library of **reusable GitHub Actions workflows** other projects can call via
`uses:`. Each workflow is a tightly-scoped, well-documented building block.
Aleksandar's own portfolio repos (`claude-agent-starter`, `markdown-rag`, etc.)
should ideally call back into this repo once they've stabilised — eating one's
own dog food is the strongest signal.

**Sells:** GitHub Actions, CI/CD, DevOps, Docker, Helm, Security Scanning.

## Scope (must-haves)

Five reusable workflows, one composite action, one re-usable starter:

1. **`docker-buildx.yml`** — multi-arch Docker build + push to GHCR (or any
   registry via inputs), with provenance + SBOM (`actions/attest-build-provenance`).
2. **`semver-release.yml`** — on tag `v*.*.*`, generate changelog from commits
   (Conventional Commits), publish a GitHub Release with assets list passed as input.
3. **`helm-oci-push.yml`** — `helm package` + `helm push` to an OCI registry
   (GHCR by default).
4. **`trivy-scan.yml`** — scan a built image for vulnerabilities, fail on
   configurable severity floor.
5. **`snyk-deps.yml`** — Snyk dependency scan for the language matrix
   (Node + Python + Go), takes a `SNYK_TOKEN` secret.

Plus:

6. **Composite action `setup-tools`** at `.github/actions/setup-tools/action.yml`
   that takes a list of tools (`helm`, `kubectl`, `kind`, `terraform`, `tflint`,
   `helm-docs`) and installs the requested ones. Saves boilerplate in consumers.
7. **Starter workflow `starter.yml`** under `workflow-templates/` so other
   `NoobCoder1209` repos can copy a sensible default in two clicks via the
   "New workflow" UI.

Each workflow has a small, honest README section documenting inputs / secrets /
outputs and a copy-pasteable consumer snippet.

## Out of scope

- No private/proprietary registries (GHCR + Docker Hub only as defaults)
- No release-please / semantic-release dependency (keep it simple — script the changelog inline)
- No Slack notification workflows (defer; needs a webhook secret = friction)
- No Kubernetes deploy workflows (Argo CD's job, not a one-shot workflow)
- No multi-cloud auth flows (keep examples to GHCR; OIDC examples for AWS/GCP are a v2 stretch)

## Tech stack

- **Language:** YAML (workflows) + Bash (scripts called by workflows)
- **Tested with:** `act` locally (optional), real GitHub runs via the dogfooding repos
- **Linting:** `actionlint` for syntax + ShellCheck for embedded bash
- **CI on this repo itself:** runs `actionlint`, lints any sample workflows,
  and runs a self-call smoke test (a workflow in this repo that calls one of
  the reusable workflows on a fixture)

## File tree

```
github-actions-templates/
  README.md                         ← top-level catalogue + when to use what
  PLAN.md
  LICENSE
  .gitignore
  .github/
    workflows/
      _docker-buildx.yml            ← `_` prefix marks reusable callables
      _semver-release.yml
      _helm-oci-push.yml
      _trivy-scan.yml
      _snyk-deps.yml
      lint.yml                      ← actionlint + shellcheck on this repo
      smoke.yml                     ← exercises one of the reusables on a fixture
    actions/
      setup-tools/
        action.yml
        README.md
  workflow-templates/               ← surfaced via GitHub's "New workflow" UI
    starter.yml
    starter.svg
    starter.properties.json
  examples/
    docker-buildx/.github/workflows/build.yml
    semver-release/.github/workflows/release.yml
    helm-oci-push/.github/workflows/publish-chart.yml
    trivy-scan/.github/workflows/scan.yml
    snyk-deps/.github/workflows/snyk.yml
  scripts/
    changelog.sh                    ← used by semver-release
  fixtures/
    docker/
      Dockerfile                    ← tiny static-busybox image for smoke tests
  docs/
    screenshots/
      ci-passing.png
```

## Step-by-step build

### 1. `_docker-buildx.yml` — reusable

Inputs:
- `image` — full image name (e.g. `ghcr.io/${{ github.repository }}/api`)
- `tag` — tag to push (default `${{ github.sha }}`)
- `platforms` — default `linux/amd64,linux/arm64`
- `context` / `dockerfile` — defaults to repo root + `./Dockerfile`
- `push` — boolean, default `true`
Secrets:
- `registry_username`, `registry_password` (or use the GHCR-default with `${{ github.token }}`)

Steps:
1. Checkout
2. Setup QEMU + Buildx
3. Login to registry
4. `docker/build-push-action@v6` with cache + provenance
5. Optional `actions/attest-build-provenance@v1` for SLSA attestations

### 2. `_semver-release.yml` — reusable

Inputs:
- `assets` — newline-separated list of file globs to attach
- `body_path` — optional path to a pre-baked release body (else auto-generated)

Steps:
1. Checkout with full history (`fetch-depth: 0`)
2. Run `scripts/changelog.sh $PREV_TAG $NEW_TAG > CHANGELOG_FRAGMENT.md`
3. `softprops/action-gh-release@v2` with `files:` from inputs

`scripts/changelog.sh`:
- Lists `git log $1..$2 --pretty=...`
- Buckets into `feat:` / `fix:` / `chore:` (Conventional Commits)
- Falls back to a flat list if there are zero conv-commits

### 3. `_helm-oci-push.yml` — reusable

Inputs:
- `chart_dir` — default `./chart`
- `registry` — default `oci://ghcr.io/${{ github.repository_owner }}`
- `chart_name` — defaults to `Chart.yaml`'s name (read by the workflow)

Steps:
1. Setup Helm (use the `setup-tools` composite action)
2. `helm package $chart_dir`
3. Login to OCI registry
4. `helm push *.tgz $registry`

### 4. `_trivy-scan.yml` — reusable

Inputs:
- `image` — full image ref (already pushed)
- `severity` — comma-separated list (default `CRITICAL,HIGH`)
- `exit_code` — `0` (warn-only) or `1` (fail) — default `1`

Steps:
1. `aquasecurity/trivy-action@master` with the inputs
2. Upload `trivy-results.sarif` to GitHub Security tab via `github/codeql-action/upload-sarif@v3`

### 5. `_snyk-deps.yml` — reusable

Inputs:
- `language` — `node`|`python`|`go`
- `severity_threshold` — default `high`
Secrets:
- `snyk_token`

Steps:
1. Setup the right runtime
2. `snyk/actions/<lang>@master` with the threshold and `--sarif-file-output`
3. Upload SARIF

### 6. Composite action `setup-tools`

Input `tools` (comma-separated). Inside, conditional install steps for each
known tool using the most reliable installer (e.g. `azure/setup-helm@v4`,
`hashicorp/setup-terraform@v3`, `helm/kind-action@v1`, `terraform-linters/setup-tflint@v4`,
`norwoodj/helm-docs@v1.13` — pick versions during build).

### 7. Starter workflow

`workflow-templates/starter.yml` with `name`, `iconName`, suggested triggers
(push + PR), and a single job that calls `_docker-buildx.yml` with sensible
defaults — meant for any of Aleksandar's app repos. The accompanying
`starter.properties.json` controls how it appears in the "New workflow" UI.

### 8. Lint workflow on this repo

`.github/workflows/lint.yml`:
- `actionlint` via `reviewdog/action-actionlint@v1`
- `shellcheck` via `ludeeus/action-shellcheck@v2` for `scripts/`
- Validate `workflow-templates/starter.properties.json` against GitHub's schema

### 9. Smoke workflow

`.github/workflows/smoke.yml`:
- Job `docker-buildx-smoke`: calls `_docker-buildx.yml` on `fixtures/docker/Dockerfile`
  with `push: false`. Fast, free.
- Document in README that this is the canary that proves the reusable
  workflow's contract hasn't drifted.

### 10. README (top-level)

1. **Title** — *github-actions-templates — Reusable workflows for the things every repo redoes*
2. **Demo** — `docs/screenshots/ci-passing.png` of the smoke workflow run
3. **Catalogue** — table of (workflow / purpose / inputs / secrets) with a
   one-line "When to use it"
4. **Skills demonstrated** — GitHub Actions, CI/CD, DevOps, Docker, Helm, Security Scanning
5. **Quick start** — copy snippet for the docker-buildx case:
   ```yaml
   name: Build
   on: [push]
   jobs:
     build:
       uses: NoobCoder1209/github-actions-templates/.github/workflows/_docker-buildx.yml@v0.1.0
       with:
         image: ghcr.io/${{ github.repository }}/api
   ```
6. **Versioning** — pin to a tag, never `@main`, and how to upgrade
7. **License** — MIT

### 11. Polish + flip public

Confirm at least one example actually works (run smoke workflow). Tag `v0.1.0`.
Topics: `github-actions`, `ci-cd`, `devops`, `docker`, `helm`, `security`,
`reusable-workflows`. Flip public.

## Verification

- [ ] `actionlint` passes
- [ ] Smoke workflow run on this repo is green
- [ ] At least one of Aleksandar's other portfolio repos imports a reusable
      from here once both are live (dogfooding) — bonus, not a blocker
- [ ] All five reusable workflows have an `examples/<name>/.github/workflows/...`
      consumer demo
- [ ] No hardcoded secrets, no secret values committed
- [ ] No SAP-specific registry / org references
- [ ] Tagged `v0.1.0` so consumers can pin
- [ ] Topics + description set

## Stretch (defer)

- AWS OIDC auth helper workflow
- GCP Workload Identity Federation auth helper
- A `release-please` integration as an alternative to the inline changelog
- Slack notification reusable
- Cosign signing of pushed images

v2 — out of v1 scope.
