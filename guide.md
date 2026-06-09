# `github-actions-templates` — Guide

> **Last verified:** 2026-06-09 against commit `290df85`.
> Observed: `_docker-buildx@v0.1.0` invoked from a real consumer (`NoobCoder1209/DevOpsCourse`) pushed `ghcr.io/noobcoder1209/devopscourse:sha-1294df5` plus a SLSA build-provenance attestation tag (`sha256-11b1c79c4...`). End-to-end loop closed.

This guide walks a first-time reader through running the **demo** for this repo end-to-end.

---

## What "the demo" means here

This repo is a **library of reusable GitHub Actions workflows** — not an application. There's nothing to `docker run` and no service to hit. The demo is:

1. The library is published on GitHub at a tagged version (`v0.1.0`).
2. **Another** repo references one of the library's workflows via `uses:`.
3. That other repo's CI runs and produces a real artifact (a container image, a release, a signed Helm chart, a SARIF upload).

The fastest way to see this work is to either watch the in-repo `smoke` workflow (which self-calls `_docker-buildx`) or look at the dogfooding consumer (`NoobCoder1209/DevOpsCourse`) where the real loop closes.

---

## Prerequisites

You only need these if you want to **run** the demo locally / on a fresh repo. Just to read it, scroll past.

| Tool | Why | How to install |
|---|---|---|
| `git` | clone the repo | most systems already have it |
| `gh` (GitHub CLI) | auth + `gh pr create` + `gh run watch` | `brew install gh` (macOS), then `gh auth login` |
| (optional) `actionlint` | local lint of workflow YAML before pushing | `brew install actionlint` |
| (optional) `shellcheck` | local lint of `scripts/changelog.sh` | `brew install shellcheck` |
| (optional) `python3 + pyyaml` | YAML schema check matching the CI's `yaml-syntax` job | `pip install pyyaml` |

**No Docker, no kind, no kubectl required.** The reusable workflows themselves run on GitHub-hosted runners; you only need a browser to watch them.

### GitHub account requirements

To **consume** the library from your own repo:
- A GitHub account with permission to push to a target repo and create workflow runs.
- For `_snyk-deps` only: a [Snyk](https://snyk.io) account and a `SNYK_TOKEN` secret on the consumer repo. **All four other reusables work with the auto-issued `GITHUB_TOKEN` and need no extra secrets.**

---

## Demo path A — watch the in-repo smoke workflow (fastest, ~30 seconds)

Every push and PR on this repo triggers `.github/workflows/smoke.yml`, which **self-calls** `_docker-buildx.yml` against a fixture Dockerfile. Green smoke = the library's most-used reusable parses, resolves all action references, and successfully builds a multi-arch image.

1. Open the Actions tab: <https://github.com/NoobCoder1209/github-actions-templates/actions/workflows/smoke.yml>
2. Click the latest run on `main`.
3. You should see **one green job**: `docker-buildx-smoke / build`.

Expected output (in the GHA UI):

- **Status:** Success
- **Total duration:** ~25–35 seconds
- **Steps that ran inside the reusable:** Checkout, Set up QEMU, Set up Docker Buildx, Extract metadata (tags, labels), Build and push (push: false, so no registry write), Compute pushed image reference (skipped — push was false).

Screenshot of a real green run: [`docs/screenshots/smoke-green.png`](docs/screenshots/smoke-green.png).

---

## Demo path B — see the dogfooding consumer (full proof)

`NoobCoder1209/DevOpsCourse` is a separate portfolio repo that uses `_docker-buildx@v0.1.0` for its real production-style image build. Watching it closes the full loop: library → real consumer → real artifact in GHCR.

1. **Look at how the consumer wires it up:**
   <https://github.com/NoobCoder1209/DevOpsCourse/blob/main/.github/workflows/build-and-push.yml>

   Specifically the `build` job, which is just:

   ```yaml
   build:
     permissions:
       contents: read
       packages: write
       id-token: write
       attestations: write
     uses: NoobCoder1209/github-actions-templates/.github/workflows/_docker-buildx.yml@v0.1.0
     with:
       image: noobcoder1209/devopscourse
       tag: sha-${{ github.sha }}
       context: .
       dockerfile: Dockerfile
       platforms: linux/amd64
       push: true
       provenance: true
   ```

2. **Look at the resulting image:**
   <https://github.com/NoobCoder1209/DevOpsCourse/pkgs/container/devopscourse>

   You should see at least these tags on the latest version:

   - `latest` — applied because the build was on the default branch
   - `sha-<7-char>` — short-SHA tag passed in by the consumer
   - `sha-<40-char>` — long-SHA tag added automatically by the reusable's `metadata-action`
   - `main` — branch ref tag, also auto-added
   - `sha256-<digest>` — **this one is the SLSA build provenance attestation referrer**, attached as an OCI subject by `actions/attest-build-provenance@v4`. Its presence is concrete proof the supply-chain attestation step ran successfully.

   Screenshot: [`docs/screenshots/dogfood-ghcr-tags.png`](docs/screenshots/dogfood-ghcr-tags.png).

3. **Verify the image is actually pullable** (no auth needed for public GHCR):

   ```bash
   curl -fsSL -H "Authorization: Bearer $(curl -fsSL 'https://ghcr.io/token?scope=repository:noobcoder1209/devopscourse:pull&service=ghcr.io' | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')" \
     "https://ghcr.io/v2/noobcoder1209/devopscourse/tags/list"
   ```

   Expected: a JSON object listing all the tags above.

---

## Demo path C — wire the library into your own repo (~5 minutes)

The final form of the demo: pick **your** repo with a `Dockerfile`, replace its inline buildx config with a `uses:` call.

```bash
# 1. From your repo's working tree, on a feature branch:
git checkout -b feature/use-reusable-buildx
```

2. Drop this into `.github/workflows/build.yml` (replace any existing inline buildx workflow):

   ```yaml
   name: build
   on:
     push:
       branches: [main]
       tags: ['v*.*.*']
     pull_request:
       branches: [main]

   jobs:
     image:
       permissions:
         contents: read
         packages: write
         id-token: write
         attestations: write
       uses: NoobCoder1209/github-actions-templates/.github/workflows/_docker-buildx.yml@v0.1.0
       with:
         image: ${{ github.repository }}     # automatically lowercased by metadata-action's normalisation? NO — see "Common failure modes" below
         platforms: linux/amd64,linux/arm64
         push: ${{ github.event_name != 'pull_request' }}
   ```

3. Commit, push, open PR, watch CI:

   ```bash
   git add .github/workflows/build.yml
   git commit -m "ci: use github-actions-templates _docker-buildx@v0.1.0"
   git push -u origin feature/use-reusable-buildx
   gh pr create --title "ci: use _docker-buildx reusable" --fill
   gh pr checks --watch
   ```

4. Merge the PR. The build will fire on `main` and push to `ghcr.io/<your-repo-lowercased>` with all the auto-applied tags.

Five copy-pasteable callers (one per reusable) live under [`examples/`](examples/) — start there.

---

## Repo layout — what every directory does

```
.
├── .github/
│   ├── workflows/                  # 7 workflow files
│   │   ├── _docker-buildx.yml      # reusable: multi-arch build + push + SLSA attestation
│   │   ├── _semver-release.yml     # reusable: tag-driven GitHub Release with changelog
│   │   ├── _helm-oci-push.yml      # reusable: helm package + push to OCI registry
│   │   ├── _trivy-scan.yml         # reusable: image scan, SARIF upload, gating fail
│   │   ├── _snyk-deps.yml          # reusable: language-aware Snyk dep scan
│   │   ├── lint.yml                # CI: actionlint + shellcheck + yaml-syntax
│   │   └── smoke.yml               # CI: self-calls _docker-buildx against the fixture
│   └── actions/setup-tools/        # composite action: installs helm/kubectl/kind/terraform/tflint/helm-docs into PATH
├── examples/                       # 5 copy-pasteable consumer workflows, one per reusable
│   ├── docker-buildx/
│   ├── semver-release/
│   ├── helm-oci-push/
│   ├── trivy-scan/
│   └── snyk-deps/
├── workflow-templates/             # registers a starter in GitHub's "New workflow" UI
│   ├── starter.yml                 # the workflow body
│   ├── starter.properties.json     # name, description, icon, categories
│   └── starter.svg                 # 24x24 icon
├── scripts/
│   └── changelog.sh                # Conventional-Commits bucketing; used by _semver-release
├── fixtures/
│   └── docker/Dockerfile           # tiny alpine multi-arch fixture for smoke.yml
├── docs/
│   ├── phase-2-design.md           # locked input/secret/output/perm contract for all 5 reusables
│   └── screenshots/                # PNGs referenced from this guide and README
├── README.md                       # public-facing intro: catalogue, quick start, perms cheat-sheet
├── PLAN.md                         # original execution plan (kept for posterity)
├── guide.md                        # this file
└── LICENSE                         # MIT
```

### Why some files have leading underscores

Workflow files prefixed with `_` (e.g. `_docker-buildx.yml`) are **reusable callees only** — they declare `on: workflow_call:` and aren't manually triggerable. The underscore is convention, not enforcement; GHA itself doesn't care about the filename.

---

## Environment variables and secrets

### What this repo itself needs

Nothing. The lint and smoke workflows run with the auto-issued `GITHUB_TOKEN`.

### What a **consumer** of this repo needs

| Reusable | Required secret | Where to put it |
|---|---|---|
| `_docker-buildx.yml` | none for GHCR (default). Override via `secrets.registry_username` + `secrets.registry_password` for non-GHCR registries. | Settings → Secrets and variables → Actions |
| `_semver-release.yml` | none (uses `GITHUB_TOKEN`) | n/a |
| `_helm-oci-push.yml` | none for GHCR. Override secrets same as docker-buildx for non-GHCR. | Settings → Secrets and variables → Actions |
| `_trivy-scan.yml` | none | n/a |
| `_snyk-deps.yml` | **`snyk_token` is required.** Get one from <https://app.snyk.io/account>. | Settings → Secrets and variables → Actions, name it `SNYK_TOKEN`, then pass via `secrets: { snyk_token: ${{ secrets.SNYK_TOKEN }} }` |

### Caller-side permissions (this is critical and gets people stuck)

Reusable workflows can only **receive** permissions the caller already holds — GHA enforces this **statically** at pre-flight, not at runtime. Even if you pass `push: false`, the calling job must grant the same elevated permissions the callee declares.

| Reusable | Calling job must grant |
|---|---|
| `_docker-buildx.yml` | `contents: read`, `packages: write`, `id-token: write`, `attestations: write` |
| `_semver-release.yml` | `contents: write` |
| `_helm-oci-push.yml` | `contents: read`, `packages: write` |
| `_trivy-scan.yml` | `contents: read`, `security-events: write`, `packages: read` |
| `_snyk-deps.yml` | `contents: read`, `security-events: write`, `actions: read` |

---

## How to verify the demo actually worked

| Demo path | Success looks like |
|---|---|
| **A (smoke)** | <https://github.com/NoobCoder1209/github-actions-templates/actions/workflows/smoke.yml> shows a green checkmark on the latest `main` commit. The job `docker-buildx-smoke / build` finishes in ~25–35s. The build summary shows a `fixtures/docker` row with `0% cache hit` (clean build) and `✅ completed`. |
| **B (dogfood consumer)** | <https://github.com/NoobCoder1209/DevOpsCourse/pkgs/container/devopscourse> shows tags including `latest`, `sha-<short>`, `sha-<long>`, `main`, **and a `sha256-...` attestation referrer**. The attestation tag is the supply-chain artifact — its absence means the `attest-build-provenance` step skipped or failed. |
| **C (your own consumer)** | After merging your PR, your repo's Actions tab shows a green build run; your repo's Packages page (or the registry you targeted) shows a freshly-pushed image with the same tag pattern as path B. |

---

## Common failure modes and their fixes

These are real failures we hit while building / dogfooding the library. If one of them is biting you, this list saves an hour of bisecting.

### `startup_failure` with zero jobs created and no logs

**Symptom:** Workflow run shows `Status: completed`, `conclusion: startup_failure`, but the API returns `"jobs": []` and the logs endpoint is `404`. Nothing in the GHA UI explains it.

**Cause 1 (most common):** A `${{ github.X }}` expression in an input `default:` value of a `workflow_call` workflow.

```yaml
# WRONG — github context is not available at workflow validation time
on:
  workflow_call:
    inputs:
      tag:
        type: string
        default: ${{ github.sha }}    # validation-time crash
```

**Fix:** default to empty string, then resolve at runtime in `env:` or `with:` where the github context is live.

```yaml
on:
  workflow_call:
    inputs:
      tag:
        type: string
        default: ""
# ...
- env:
    TAG: ${{ inputs.tag != '' && inputs.tag || github.sha }}
  run: echo "$TAG"
```

**Cause 2:** Caller doesn't grant a permission the callee requests.

GHA checks the callee's job-level `permissions:` block **statically**: every permission the callee declares must already be granted by the calling job. The runtime path doesn't matter — even if `push: false` means `_docker-buildx` won't actually use `packages: write`, the callee still **declares** it, and the caller must still grant it.

**Fix:** copy the entire permissions block from the [permissions cheat-sheet above](#caller-side-permissions-this-is-critical-and-gets-people-stuck) into your calling job.

### Image is built but never pushed (no GHCR entry)

**Symptom:** Build job is green, build summary shows the image, but `https://github.com/<owner>/<repo>/pkgs/container/<image>` is empty or 404.

**Cause:** Forgot `push: true` (it defaults to `true` but is easy to overwrite to `false` from a copy-paste of the smoke workflow), or the calling job lacks `packages: write`.

**Fix:** Confirm `with: { push: true }` on the calling job, and `permissions: { packages: write }` is granted.

### GHCR rejects the push with `denied: insufficient_scope`

**Symptom:** Build runs but the push step fails authenticating to `ghcr.io`.

**Cause:** GHCR rejects mixed-case in image paths. If your repo is `NoobCoder1209/MyApp`, then `image: ${{ github.repository }}` resolves to `NoobCoder1209/MyApp` (mixed case), which GHCR refuses.

**Fix:** Pre-lowercase the image name. Hard-code it (`image: noobcoder1209/myapp`) or compute it in a step before calling the reusable. GHA expression language doesn't have a `tolower()` function, so a hard-coded lowercase value is the cleanest workaround.

### `_helm-oci-push` fails reading `Chart.yaml`

**Symptom:** "Chart.yaml not found at ./chart/Chart.yaml" or chart name resolves to `"my-chart"` (with quotes) breaking the push reference.

**Cause 1:** The chart isn't at `./chart/` — pass the right path via `with: { chart_dir: ./path/to/chart }`.

**Cause 2:** The previous awk-based parser couldn't handle quoted values. Fixed in `v0.1.0` by parsing through `helm show chart` instead.

### `_snyk-deps` fails with `Authorization failure`

**Cause:** The consumer didn't pass `secrets: { snyk_token: ${{ secrets.SNYK_TOKEN }} }`, or the `SNYK_TOKEN` secret doesn't exist on the repo.

**Fix:** Add the secret in repo Settings → Secrets and variables → Actions, then ensure the consumer workflow passes it through:

```yaml
uses: NoobCoder1209/github-actions-templates/.github/workflows/_snyk-deps.yml@v0.1.0
with:
  language: node
secrets:
  snyk_token: ${{ secrets.SNYK_TOKEN }}
```

### `_trivy-scan`'s `vulnerabilities_found` output is empty

**Cause:** Pre-`v0.1.0` the gating step wired its output incorrectly. **Fixed in `v0.1.0`.** If you're somehow on a pre-`v0.1.0` ref, pin to `@v0.1.0`.

### Workflow templates UI starter doesn't appear

**Symptom:** When you go to "New workflow" in some repo, the starter from this library doesn't show up.

**Cause:** GitHub's workflow-templates UI surfaces starters **owned by the same user/org** as the repo creating the new workflow. Cross-org/cross-user discovery isn't a feature.

**Fix:** Either fork this repo into your own org or just copy `workflow-templates/starter.yml` directly.

---

## Where to go next

- **Try it:** wire `_docker-buildx@v0.1.0` into one of your own repos (demo path C above).
- **Read the contract:** [`docs/phase-2-design.md`](docs/phase-2-design.md) has the locked input/secret/output spec for every reusable.
- **See more callers:** [`examples/`](examples/) has one consumer per reusable.
- **Open an issue:** if any of the failure modes above bit you and aren't covered, please open an issue at <https://github.com/NoobCoder1209/github-actions-templates/issues> so the next reader doesn't hit the same wall.
