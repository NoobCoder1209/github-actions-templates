# Phase 2 — Design Checklist (`github-actions-templates`)

This is the contract Phase 3 builds against. Every filename, input default, permission, and version pin below is locked.

## Conventions (apply to all 5 reusables)

- **Filenames:** leading underscore (`_*.yml`) marks them as reusable-only.
- **Trigger:** `on: workflow_call` only.
- **Top-level permissions:** none. **Per-job permissions:** explicit minimum.
- **Secrets block:** explicit `secrets:` (never `inherit`).
- **Action pinning:** documented major (e.g. `@v6`) except `aquasecurity/trivy-action@v0.36.0` which has no floating major tag.
- **Step IDs:** lowercase-kebab. `id: meta`, `id: build`, `id: scan`.
- **Caller perms:** every example has a `permissions:` block at job level — callers must re-declare elevated perms (`id-token`, `attestations`, `packages`).

---

## 1. `_docker-buildx.yml`

**Path:** `.github/workflows/_docker-buildx.yml`
**Purpose:** Multi-arch image build, optional push to GHCR, build provenance attestation.

### Inputs

| name | type | required | default | description |
|---|---|---|---|---|
| `image` | string | yes | — | Image name without registry/tag, e.g. `myorg/myapp`. |
| `tag` | string | no | `${{ github.sha }}` | Primary tag. |
| `platforms` | string | no | `linux/amd64,linux/arm64` | Comma-separated buildx platforms. |
| `context` | string | no | `.` | Build context path. |
| `dockerfile` | string | no | `Dockerfile` | Dockerfile path relative to context. |
| `push` | boolean | no | `true` | When false, builds only. |
| `registry` | string | no | `ghcr.io` | Registry hostname. |
| `provenance` | boolean | no | `true` | Emit SLSA provenance attestation. |
| `build-args` | string | no | `''` | Newline-separated `KEY=VALUE` build args. |

### Secrets

| name | required | description |
|---|---|---|
| `registry_username` | no | Override for non-GHCR registry. Defaults to `${{ github.actor }}`. |
| `registry_password` | no | Override for non-GHCR registry. Defaults to `${{ github.token }}`. |

### Outputs

| name | description |
|---|---|
| `image_ref` | Full pushed reference incl. digest. |
| `tags` | Newline list of all tags applied. |
| `digest` | Image digest. |

### Callee job permissions

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
  attestations: write
```

### Action versions

`actions/checkout@v6`, `docker/setup-qemu-action@v4`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7`, `actions/attest-build-provenance@v4`.

---

## 2. `_semver-release.yml`

**Path:** `.github/workflows/_semver-release.yml`
**Purpose:** On `v*.*.*` tag push, generate Conventional-Commits changelog and publish a GitHub Release.

### Inputs

| name | type | required | default | description |
|---|---|---|---|---|
| `assets` | string | no | `''` | Newline-separated globs to attach. |
| `body_path` | string | no | `''` | File used as release body. Empty = generated changelog. |
| `prerelease` | boolean | no | `false` | |
| `draft` | boolean | no | `false` | |
| `tag_name` | string | no | `${{ github.ref_name }}` | |
| `previous_tag` | string | no | `''` | Override for changelog range. |

### Secrets

None.

### Outputs

`release_url`, `release_id`, `previous_tag`.

### Callee job permissions

```yaml
permissions:
  contents: write
```

### Action versions

`actions/checkout@v6` (with `fetch-depth: 0`, `fetch-tags: true`), `softprops/action-gh-release@v3`.

---

## 3. `_helm-oci-push.yml`

**Path:** `.github/workflows/_helm-oci-push.yml`
**Purpose:** `helm package` + `helm push` to OCI registry (GHCR default).

### Inputs

| name | type | required | default | description |
|---|---|---|---|---|
| `chart_dir` | string | no | `./chart` | Directory containing `Chart.yaml`. |
| `registry` | string | no | `oci://ghcr.io/${{ github.repository_owner }}` | OCI registry URL. |
| `chart_version` | string | no | `''` | Override chart version. |
| `app_version` | string | no | `''` | Override appVersion. |
| `lint` | boolean | no | `true` | Run `helm lint` before packaging. |
| `sign` | boolean | no | `false` | Reserved for future cosign signing. |

### Secrets

`registry_username` (default `${{ github.actor }}`), `registry_password` (default `${{ github.token }}`).

### Outputs

`chart_name`, `chart_version`, `chart_ref`.

### Callee job permissions

```yaml
permissions:
  contents: read
  packages: write
```

### Action versions / tools

`actions/checkout@v6`, composite `./.github/actions/setup-tools` with `tools: helm`, then native `helm` CLI for lint/package/registry login/push.

---

## 4. `_trivy-scan.yml`

**Path:** `.github/workflows/_trivy-scan.yml`
**Purpose:** Image scan + SARIF upload + gating fail.

### Inputs

| name | type | required | default | description |
|---|---|---|---|---|
| `image` | string | yes | — | Full image reference. |
| `severity` | string | no | `CRITICAL,HIGH,MEDIUM` | Severity floor. |
| `ignore_unfixed` | boolean | no | `true` | |
| `exit_code` | string | no | `1` | Gate exit code; `0` to scan-only. |
| `scan_type` | string | no | `image` | |
| `vuln_type` | string | no | `os,library` | |
| `category` | string | no | `trivy` | SARIF category. |

### Secrets

None.

### Outputs

`sarif_path`, `vulnerabilities_found`.

### Callee job permissions

```yaml
permissions:
  contents: read
  security-events: write
  packages: read
```

### Action versions

`actions/checkout@v6`, `aquasecurity/trivy-action@v0.36.0`, `github/codeql-action/upload-sarif@v4`.

### Two-pass pattern

1. SARIF report (always uploads): `exit-code: '0'`.
2. Gating: `exit-code: ${{ inputs.exit_code }}`, `format: table`.

---

## 5. `_snyk-deps.yml`

**Path:** `.github/workflows/_snyk-deps.yml`
**Purpose:** Snyk dependency scan for `node|python|go`.

### Inputs

| name | type | required | default | description |
|---|---|---|---|---|
| `language` | string | yes | — | `node`, `python`, `go`. |
| `severity_threshold` | string | no | `medium` | `low|medium|high|critical`. |
| `args` | string | no | `--all-projects` | Extra Snyk CLI args. |
| `runtime_version` | string | no | `''` | Optional runtime pin. |
| `category` | string | no | `snyk` | SARIF category. |

### Secrets

`snyk_token` (required).

### Outputs

`sarif_path`, `issues_found`.

### Callee job permissions

```yaml
permissions:
  contents: read
  security-events: write
```

### Action versions

`actions/checkout@v6`, `actions/setup-node@v6` / `actions/setup-python@v6` / `actions/setup-go@v6`, `snyk/actions/{node,python,golang}@v1`, `github/codeql-action/upload-sarif@v4`.

### Continue-on-error pattern

Snyk step has `continue-on-error: true` + `id: snyk` + `--sarif-file-output=snyk.sarif`. Upload-sarif runs `if: always()`. Final gate step `exit ${{ steps.snyk.outcome == 'failure' && '1' || '0' }}`.

---

## 6. Composite action `setup-tools`

**Path:** `.github/actions/setup-tools/action.yml`
**Type:** Composite (NOT reusable workflow — needs to install into the calling job's PATH).

### Inputs

| name | required | default | description |
|---|---|---|---|
| `tools` | yes | — | Comma-separated. Unknown values fail. |
| `helm-version` | no | `latest` | |
| `kubectl-version` | no | `latest` | |
| `kind-version` | no | `v0.27.0` | |
| `terraform-version` | no | `latest` | |
| `tflint-version` | no | `latest` | |
| `helm-docs-version` | no | `v1.14.2` | |

### Supported tools

- `helm` → `azure/setup-helm@v5`
- `kubectl` → `azure/setup-kubectl@v5`
- `kind` → `helm/kind-action@v1`
- `terraform` → `hashicorp/setup-terraform@v4`
- `tflint` → `terraform-linters/setup-tflint@v6`
- `helm-docs` → `curl | tar` from GitHub releases

---

## 7. Workflow templates UI

`workflow-templates/starter.yml` — minimal example calling `_docker-buildx`.
`workflow-templates/starter.properties.json` — name, description, iconName, categories, filePatterns.
`workflow-templates/starter.svg` — small inline SVG (24×24).

---

## 8. `lint.yml`

Three jobs:
1. `actionlint` via `reviewdog/action-actionlint@v1` (with `actionlint_flags: -shellcheck=` to avoid double-reporting)
2. `shellcheck` via `ludeeus/action-shellcheck@v2` for `scripts/`
3. `yaml-syntax` — python `yaml.safe_load` over all workflow YAMLs

---

## 9. `smoke.yml`

Self-call `_docker-buildx.yml` against `fixtures/docker/Dockerfile` with `push: false`, `provenance: false`, `linux/amd64`.

---

## 10. `scripts/changelog.sh`

Args: `<PREV_TAG> <NEW_TAG>`. Markdown output buckets `feat`/`fix`/`chore|build|ci|docs|test|refactor|perf|style`/Other. Bash with `set -euo pipefail`, `awk` for bucketing.

---

## Cross-cutting checklist for Phase 3

- [ ] Every reusable: `name:`, `on: workflow_call:`, explicit `inputs:`/`secrets:`/`outputs:`.
- [ ] No `permissions: write-all`. Per-job minimum.
- [ ] No `@main`, no `@master`.
- [ ] Examples each have `permissions:` at calling job — copy-pasteable.
- [ ] `uses:` in examples points to `NoobCoder1209/github-actions-templates/.../@v0.1.0` (Phase 5 tag).
- [ ] `scripts/changelog.sh` executable; shellcheck clean at `severity: warning`.
- [ ] `actionlint` passes on lint.yml itself.
- [ ] `smoke.yml` green = release gate.
