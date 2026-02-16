---
name: supply_chain_security
description: Docker image signing (Cosign), SBOM generation, SLSA provenance attestation, GHCR registry management.
when_to_use:
  - Modifying build-push-artifacts.yml
  - Rotating Cosign keys
  - Adding new Docker images to the pipeline
  - Supply chain audit
  - Verifying image integrity
---

# Supply Chain Security

## Pipeline (build-push-artifacts.yml)

For each image (CMS, Admin, Kiosk):

1. **Build** — `docker/build-push-action@v5` with GHA cache
2. **Push** — to `ghcr.io/<owner>/<image>:latest` and `:<sha>`
3. **Sign** — Cosign with `COSIGN_PRIVATE_KEY` + `COSIGN_PASSWORD`
4. **SBOM** — `anchore/sbom-action@v0` (CycloneDX JSON format)
5. **Attest SBOM** — Cosign attestation with `--type cyclonedx`
6. **SLSA** — `actions/attest-build-provenance@v2` with real image digest

## Critical implementation details

### Lowercase owner

Docker/GHCR requires lowercase tags. GitHub `repository_owner` may have uppercase letters.

```yaml
env:
  OWNER: ${{ github.repository_owner }}

steps:
  - name: Lowercase owner
    id: owner
    run: echo "lc=${OWNER,,}" >> $GITHUB_OUTPUT
```

Then use `${{ steps.owner.outputs.lc }}` everywhere instead of `${{ github.repository_owner }}`.

### SLSA digest

Use the real Docker image digest from the build step output, NOT the git commit SHA:

```yaml
# CORRECT
subject-digest: ${{ steps.build-cms.outputs.digest }}

# WRONG (git SHA is not an image digest)
subject-digest: sha256:${{ github.sha }}
```

### Cosign key management

- Private key: VPS `/opt/resto/shared/cosign/cosign.key` + GitHub secret `COSIGN_PRIVATE_KEY`
- Password: GitHub secret `COSIGN_PASSWORD`
- Public key: VPS `/opt/resto/shared/cosign/cosign.pub` + GitHub secret `COSIGN_PUBLIC_KEY`
- Verify key+password match: `COSIGN_PASSWORD=<pw> cosign public-key --key cosign.key`

### Secret safety

NEVER write secrets to `$GITHUB_OUTPUT`. Reference `${{ secrets.* }}` directly in step `env:` blocks.

## Verification

```bash
# Verify image signature
cosign verify --key cosign.pub ghcr.io/<owner>/<image>:<tag>

# Verify SBOM attestation
cosign verify-attestation --key cosign.pub --type cyclonedx ghcr.io/<owner>/<image>:<tag>

# List GHCR packages
gh api user/packages/container/<image>/versions
```

## Key rotation

1. Generate new Cosign keypair on VPS: `cosign generate-key-pair`
2. Update GitHub secrets: `COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`, `COSIGN_PUBLIC_KEY`
3. Old images remain verifiable with old public key
4. New pushes signed with new key
5. Update VPS: `/opt/resto/shared/cosign/`

## Deliverables

- Build pipeline passes (all 3 images: build, push, sign, SBOM, attest, SLSA)
- Image signature verifiable with public key
- No secrets in workflow logs or step outputs
