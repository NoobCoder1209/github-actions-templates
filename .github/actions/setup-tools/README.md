# setup-tools

Composite action that installs a curated set of CLI tools into the current job's `PATH`.

## Inputs

| name | required | default | description |
|---|---|---|---|
| `tools` | yes | — | Comma-separated list. Supported: `helm`, `kubectl`, `kind`, `terraform`, `tflint`, `helm-docs`. Unknown values fail the action. |
| `helm-version` | no | `latest` | Helm version pin. |
| `kubectl-version` | no | `latest` | kubectl version pin. |
| `kind-version` | no | `v0.27.0` | kind version pin. |
| `terraform-version` | no | `latest` | Terraform version pin. |
| `tflint-version` | no | `latest` | tflint version pin. |
| `helm-docs-version` | no | `v1.14.2` | helm-docs version pin. |

## Example

```yaml
- uses: NoobCoder1209/github-actions-templates/.github/actions/setup-tools@v0.1.0
  with:
    tools: helm,kubectl,helm-docs
    helm-version: v3.16.4
```

## Why a composite, not a reusable workflow

Reusable workflows run on a separate runner, so installed binaries aren't visible to the calling job. A composite action installs into the calling job's `PATH` — which is what you want for "set up tooling, then keep going".
