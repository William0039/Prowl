# Local Amp-compatible Prowl

This fork keeps `main` aligned with `onevcat/Prowl`. The upstream contribution is
`fix/amp-state-detection`; `local/amp-build-workflow` adds local build tooling and
disables Sparkle in Debug builds so official update packages cannot replace the patch.
Do not include the local maintenance commit in the upstream pull request.

## Build an official release with the patch

From the `local/amp-build-workflow` checkout, run:

```bash
bash scripts/build-amp-fork.sh v2026.10.6
```

Omit the tag to select the latest official GitHub release. GitHub CLI authentication,
Xcode, mise, Bash 4+, and Python 3.10+ are required. The script creates a fresh Git
worktree, applies the scoped patch and local tooling, runs `make check` and `make test`, and builds
the Debug app. A conflict or failed check stops before changing any installed app.
The failed worktree is retained for diagnosis; do not force-apply a conflicting patch.

Releases predating the upstream repository-icon lint fix receive that official commit
before checks. Once a release contains it, the script skips the compatibility backport.
No lint rules or failed tests are bypassed.

Successful builds live under `~/Library/Application Support/Prowl-Amp-Fork/versions/`.
Run the printed `launch.sh` to use a separate data directory and CLI socket. Use only
one custom Debug instance at a time. Exit that instance normally before switching
versions; the script never terminates the official app or any agent sessions.
Keep the previous successful version until the new version passes live acceptance.

## Maintain and retire the patch

Fetch `upstream/main` and merge it into the fix branch without rewriting published
history. Run the checks again, then merge the fix branch into the maintenance branch.
Append follow-up Amp fix commits to the script's `patch_commits` array in order.
Only these explicit commits are applied to a release tag, not unrelated upstream work.
The local maintenance changes are applied separately from their three owned paths.
Never force-push, auto-publish a release, or bypass a failed test.

The build script does not push or modify the fork's `main`. Synchronize `main` with
an explicit fast-forward after reviewing upstream changes. If an official release
includes the fix, verify Amp states there and return to the official application;
remove the local patch rather than maintaining duplicate behavior indefinitely.
