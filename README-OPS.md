# Ops Guide

This repo contains automation for applying patches and publishing logs.

## Key scripts (relative links)

- Router: tools\inbox-router\inbox-router.ps1  (v1.7.12)
- Log collector: tools/ops/collect-logs.ps1

## Logs in the repo (auto-pushed)

- Collected under: ops/logs/
- Files named like:
  - patch-router_YYYYMMDD-HHMMssZ.log
  - patch-archiver_YYYYMMDD-HHMMssZ.log
- Machine summary: ops/ops-manifest.json

The collector tails a bounded number of lines from local logs and commits/pushes them here.

## Local runtime (outside repo)

- Router log: C:\Users\ander\patch-router.log
- Archiver log: C:\Users\ander\patch-archiver.log

## Manual use

- Run collector once:
      pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\ops\collect-logs.ps1
- Install scheduled collection (every 5 minutes):
      pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\ops\collect-logs.ps1 -InstallScheduledTask
