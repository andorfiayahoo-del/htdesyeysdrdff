# Troubleshooting

### Verify log missing
- Ensure you pushed via `git vpush` (alias) or ran `tools/ops/verify-remote.ps1` manually.

### Unity never shows busy
- Unity must be open in an interactive desktop session. Focus detection uses user32; headless/SSH won't work.

### Validator not green
- `match.json` uses arrays for `mismatched`/`missing`. Treat non-empty arrays as failures.
- If non-empty, revert the canary commit and re-run `patch-minforce.ps1`.

### On wrong branch
- Checkout `main` before running ops: `git checkout main && git pull --rebase`.

### `vpush` alias missing
- Fallback: `git push -u origin main`, then run `tools/ops/verify-remote.ps1` to write logs.

### EOL warnings
- Expected once-off while normalization settles; docs enforced as LF by `.gitattributes`.
