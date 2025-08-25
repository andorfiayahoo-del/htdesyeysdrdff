# Troubleshooting

### Verify log missing
- Ensure you pushed via `git vpush` (alias) or ran `tools/ops/verify-remote.ps1` manually.

### Unity never shows busy
- Unity must be open in an interactive desktop session. Focus detection uses user32; headless/SSH won't work.

### Validator not green
- `match.json` with `mismatched>0` or `missing>0`: revert the canary commit, run `patch-minforce.ps1` again.

### On wrong branch
- Checkout `main` before running ops: `git checkout main && git pull --rebase`.

### `vpush` alias missing
- Fallback: `git push -u origin main`, then run `tools/ops/verify-remote.ps1` to write logs.

### EOL warnings
- Expected once-off while normalization settles; docs enforced as LF by `.gitattributes`.
