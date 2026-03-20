---
created: 2026-03-19T20:48:30.550Z
title: Install GitHub Actions self-hosted runner on VPS
area: tooling
files:
  - project/scripts/runner-setup.sh
  - project/.github/workflows/cd-deploy.yml
---

## Problem

The CD pipeline (`cd-deploy.yml`) has multiple jobs with `runs-on: [self-hosted, vps-primary]` but no self-hosted runner is installed on the VPS. This means automated deployments triggered by git push do not work — every deploy is currently manual.

The runner setup script was created in this session at `project/scripts/runner-setup.sh` and is ready to use, but requires a single-use runner registration token from GitHub.

## Solution

1. Go to https://github.com/zerAda/RestaurantAgentAutomation/settings/actions/runners/new
2. Copy the one-time registration token (valid 1 hour)
3. Run: `make runner-setup TOKEN=<token>` from the local project
   - Or directly on VPS: `bash /opt/resto/current/scripts/runner-setup.sh --token <token>`
4. Verify at GitHub → Settings → Actions → Runners (should show "vps-primary" as idle)

Once installed, pushing to `main` will auto-trigger: CI → build → CD deploy to VPS.
