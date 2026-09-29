# Pre-commit Autoupdate - Project Memory

This file contains persistent context for Claude Code sessions on this project.
It will be automatically loaded at the start of every session.

## Project Overview

A pre-commit hook that automatically keeps pre-commit hooks up to date by
running `pre-commit autoupdate` on every commit and staging any changes.

**Key Details:**

- **Purpose:** Auto-update pre-commit hooks on every commit
- **Type:** Pre-commit hook repository (consumed by other repos)
- **CI/CD:** GitHub Actions with release workflow
- **Linting:** Pre-commit hooks for code quality

## Repository Structure

```text
pre-commit-autoupdate/
├── .github/workflows/     # CI/CD workflows
│   ├── pre-commit.yml     # Pre-commit validation
│   ├── release.yml        # Semantic versioning & releases
│   ├── stale.yml          # Stale issue management
│   └── test.yml           # tests/run.sh on Ubuntu and macOS
├── .pre-commit-config.yaml  # This repo's own pre-commit config
├── .pre-commit-hooks.yaml   # Hook definitions for consumers
├── hooks/
│   └── autoupdate.sh      # The autoupdate script
├── tests/
│   └── run.sh             # Hook tests (local repos, no network)
├── README.md
├── CLAUDE.md
└── LICENSE
```

## How This Hook Works

1. User adds this repo to their `.pre-commit-config.yaml`
1. On commit, pre-commit clones this repo and runs `hooks/autoupdate.sh`
1. The script runs `pre-commit autoupdate` in the user's repo
1. If `.pre-commit-config.yaml` changed, it's staged for the commit
1. The commit proceeds with updated hook versions included

## Key Files

### `.pre-commit-hooks.yaml`

This is the manifest file that pre-commit uses to discover available hooks.
It defines the `autoupdate` hook with these properties:

- `always_run: true` - Runs on every commit
- `pass_filenames: false` - Doesn't need file arguments
- `stages: [pre-commit]` - Only runs in pre-commit stage

### `hooks/autoupdate.sh`

The main script that:

1. Parses its own args (`--interval-hours`, `--min-age-days`,
   `--fail-on-update`) and passes the rest to `pre-commit autoupdate`
   (e.g. `--freeze` for SHA pinning)
1. Checks for `.pre-commit-config.yaml` existence
1. Skips if a run with the same args succeeded within `--interval-hours`
   (stamp file at `$(git rev-parse --git-path pre-commit-autoupdate.stamp)`)
1. Runs `pre-commit autoupdate --jobs 8` (unless `--jobs` was passed)
1. With `--min-age-days`, restores the old `rev` line for each repo whose new
   tag's GitHub release is too young, missing, or whose frozen tag moved.
   autoupdate rewrites `rev` lines in place, so line N before matches line N
   after. The repo for a `rev` line is the `repo:` in the same list entry,
   in any key order
1. Stages the config file if it changed, or exits 1 with `--fail-on-update`

Release age comes from GitHub's `published_at`. Git dates can be backdated,
so the hook doesn't read them. Anything unknown holds the bump.

Speed: autoupdate does one network `git fetch` per repo. Sequential fetches
were the main cost (~10s for 6 repos); `--jobs 8` cuts that to ~3.5s.

zCore consumes this hook and needs `--freeze` (SHA pins) support.

## Git Workflow

1. **Create feature branch:** `git checkout -b feature/description`
1. **Make changes** to code or documentation
1. **ALWAYS run pre-commit BEFORE committing:** `pre-commit run --all-files`
1. **Commit with conventional format:** `git commit -m "type: description"`
1. **Push and create PR:** `gh pr create --title "feat: description"`
1. **Merge to main:** Automatic release created based on commits

**Commit Format:** Conventional Commits (enforced by pre-commit hook)

- `feat:` - New feature (triggers minor version bump)
- `fix:` - Bug fix (triggers patch version bump)
- `docs:` - Documentation changes (no version bump)
- `chore:` - Maintenance (no version bump)

## Important Notes

### Testing Changes

Run `tests/run.sh`. It builds local hook repos with real tags and serves
release dates from fixture files through `PCA_GITHUB_API=file://...`, so it
needs no network. CI (`.github/workflows/test.yml`) runs it on Ubuntu and on
macOS's `/bin/bash` 3.2, so keep the hook bash 3.2 compatible: no `mapfile`,
no associative arrays, and `${arr[@]+"${arr[@]}"}` for arrays that may be
empty under `set -u`.

### Versioning

This repo uses semantic versioning. Consumers reference specific versions:

```yaml
rev: v1.0.0
```

Breaking changes should bump the major version.

## References

- @README.md - Usage documentation
- Pre-commit documentation: <https://pre-commit.com/>
- Creating hooks: <https://pre-commit.com/#creating-new-hooks>

---

**Last Updated:** 2026-09-28

This file should be updated whenever:

- Hook behavior changes
- New features are added
- Important context is discovered
