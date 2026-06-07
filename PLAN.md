# `github-actions-templates` — Execution Plan

## How to use this plan

You are the build session for this repo. Read this file end-to-end, then start executing immediately.

**Working agreement:**

1. **Start without waiting.** Begin Phase 1 in the *Subagent playbook* below.
2. **Always ask the user about business decisions and business logic.** Which 5 reusable workflows are most useful, default registries, severity thresholds, README copy.
3. **Ask the user when you are genuinely blocked.**
4. **Do not ask the user about engineering details.** Workflow file naming, action versions, internal helper scripts — your call.
5. **Use subagents aggressively.** Default to the playbook below.
6. **TaskCreate / TaskUpdate everything.**
7. **Pattern 3 only.** No external infra to demo. Verification is a green smoke workflow run on the repo itself.
8. **Follow shared standards** (MIT, README, CI, topics, private until verified).
9. **All `Agent` tool calls must pass `model: "opus"`.**
10. **Off-limits forever:** SAP-internal Piper / Cumulus references. These are generic GitHub Actions only.

## Subagent playbook (this repo)

YAML-heavy, lots of moving actions. 3 in research, 2 in review.

**Phase 1 — Research (parallel):**
- `Explore` (Opus): "Find current best practices for reusable workflows in GitHub Actions: input/output shapes, secret passing, workflow_call triggers, version pinning. Return a 200-word summary."
- `Explore` (Opus): "Find the canonical multi-arch Docker build workflow with `docker/setup-buildx-action`, `docker/build-push-action`, GHCR login, provenance attestation. Return a complete reusable workflow."
- `Explore` (Opus): "Find Trivy + Snyk current-version GitHub Actions for SARIF + GitHub Security tab upload. Return both reusable-workflow snippets and any required permissions."

**Phase 2 — Design (single):**
- `Plan` (Opus): "Given research and this PLAN.md, propose the exact 5 reusable workflow filenames, their inputs/secrets/outputs, and an example consumer per workflow. Return as a checklist."

**Phase 3 — Build:** main session writes the YAML + scripts. `Explore` for specific action questions.

**Phase 4 — Review (parallel):**
- `code-reviewer` (Opus): "Review for: actionlint correctness, no secrets committed, version pinning (no `@main`), SARIF upload permissions, ShellCheck on embedded bash. High effort."
- `tester` (Opus): "Run the smoke workflow on this repo against `fixtures/docker/Dockerfile`. Confirm green. Verify each example consumer is self-contained."

**Phase 5 — Polish:** capture CI-passing screenshot, tag `v0.1.0`, ask user before flipping public.

---

## Goal

A library of **reusable GitHub Actions workflows** other projects can call via
`uses:`. Each tightly-scoped, well-documented. Aleksandar's own portfolio repos
should ideally `uses:` this once both are stable — best signal.

**Sells:** GitHub Actions, CI/CD, DevOps, Docker, Helm, Security Scanning.

## Business decisions to ask the user about

- **Which 5 reusables to ship in v1** — recommend `_docker-buildx`, `_semver-release`, `_helm-oci-push`, `_trivy-scan`, `_snyk-deps`. Confirm or swap.
- **Default container registry** — recommend GHCR (uses `${{ github.token }}`, no extra secrets). Alternatives: Docker Hub.
- **Default severity threshold for security scans** — recommend `CRITICAL,HIGH` for Trivy and `high` for Snyk. Confirm.
- **Publish workflow templates to the GitHub "New workflow" UI** — recommend yes (free signal, low cost).
- **Tag scheme** — recommend `vMAJOR.MINOR.PATCH` semver (start `v0.1.0`).

## Scope (must-haves)

Five reusable workflows, one composite action, one starter:

1. `_docker-buildx.yml` — multi-arch build + push to GHCR + provenance/SBOM.
2. `_semver-release.yml` — on tag `v*.*.*`, generate changelog (Conventional Commits), publish GitHub Release with assets.
3. `_helm-oci-push.yml` — `helm package` + `helm push` to OCI registry (GHCR default).
4. `_trivy-scan.yml` — scan a built image, fail on configurable severity floor.
5. `_snyk-deps.yml` — Snyk dep scan for `node|python|go`.
6. Composite action `setup-tools` — installs requested tools (`helm`, `kubectl`, `kind`, `terraform`, `tflint`, `helm-docs`).
7. `workflow-templates/starter.yml` for the "New workflow" UI.

## Out of scope

- No private/proprietary registries
- No release-please / semantic-release dependency
- No Slack notifications
- No Kubernetes deploy workflows
- No multi-cloud auth flows (defer AWS/GCP OIDC examples)

## Tech stack

- **Language:** YAML + bash
- **Tested with:** `act` locally (optional), real GitHub runs via dogfood repos
- **Linting:** `actionlint` + `shellcheck`
- **CI on this repo:** `actionlint` + sample-workflow lint + self-call smoke

## File tree

```
github-actions-templates/
  README.md
  PLAN.md
  LICENSE
  .gitignore
  .github/
    workflows/
      _docker-buildx.yml
      _semver-release.yml
      _helm-oci-push.yml
      _trivy-scan.yml
      _snyk-deps.yml
      lint.yml
      smoke.yml
    actions/
      setup-tools/
        action.yml
        README.md
  workflow-templates/
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
    changelog.sh
  fixtures/docker/Dockerfile
  docs/screenshots/ci-passing.png
```

## Step-by-step build

### 1. `_docker-buildx.yml`

Inputs: `image`, `tag` (default `${{ github.sha }}`), `platforms` (default `linux/amd64,linux/arm64`), `context`, `dockerfile`, `push`. Secrets: `registry_username`, `registry_password` (default `${{ github.token }}` for GHCR).

Steps: checkout, QEMU, Buildx, registry login, `docker/build-push-action@v6` with cache + provenance, optional `actions/attest-build-provenance@v1`.

### 2. `_semver-release.yml`

Inputs: `assets` (newline-separated globs), `body_path` optional.

Steps: checkout `fetch-depth: 0`, run `scripts/changelog.sh $PREV_TAG $NEW_TAG`, `softprops/action-gh-release@v2`.

`scripts/changelog.sh`: `git log --pretty`, bucket `feat:`/`fix:`/`chore:`, fall back to flat list.

### 3. `_helm-oci-push.yml`

Inputs: `chart_dir` (default `./chart`), `registry` (default `oci://ghcr.io/${{ github.repository_owner }}`), `chart_name` (read from Chart.yaml).

Steps: setup helm via `setup-tools`; package; OCI login; push.

### 4. `_trivy-scan.yml`

Inputs: `image`, `severity` (default `CRITICAL,HIGH`), `exit_code` (default `1`).

Steps: `aquasecurity/trivy-action@master`; upload SARIF via `github/codeql-action/upload-sarif@v3`.

### 5. `_snyk-deps.yml`

Inputs: `language` (`node|python|go`), `severity_threshold` (default `high`). Secret: `snyk_token`.

Steps: setup runtime; `snyk/actions/<lang>@master`; upload SARIF.

### 6. Composite action `setup-tools`

Input `tools` (comma-separated). Conditional install steps for known tools.

### 7. Starter workflow

`workflow-templates/starter.yml` calling `_docker-buildx.yml` with sensible defaults. `starter.properties.json` for the New-workflow UI.

### 8. Lint workflow

`actionlint` via `reviewdog/action-actionlint@v1`; `shellcheck` via `ludeeus/action-shellcheck@v2` for `scripts/`.

### 9. Smoke workflow

Job `docker-buildx-smoke` calling `_docker-buildx.yml` on `fixtures/docker/Dockerfile` with `push: false`.

### 10. README

1. Title — *github-actions-templates — Reusable workflows for the things every repo redoes*
2. Demo — `docs/screenshots/ci-passing.png`
3. Catalogue — table (workflow / purpose / inputs / secrets / when to use)
4. Skills demonstrated — GitHub Actions, CI/CD, DevOps, Docker, Helm, Security Scanning
5. Quick start — copy snippet for docker-buildx case
6. Versioning — pin to a tag, never `@main`
7. License — MIT

### 11. Polish + flip public

Smoke green. Tag `v0.1.0`. Topics: `github-actions`, `ci-cd`, `devops`, `docker`, `helm`, `security`, `reusable-workflows`. Ask user before flipping.

## Verification

- [ ] `actionlint` clean
- [ ] Smoke workflow green
- [ ] At least one example consumer per reusable
- [ ] No hardcoded secrets
- [ ] No SAP-specific registry / org references
- [ ] Tagged `v0.1.0`
- [ ] Topics + description set

## Stretch (defer)

- AWS OIDC / GCP WIF auth helper workflows
- `release-please` integration
- Slack notification reusable
- Cosign signing of pushed images
