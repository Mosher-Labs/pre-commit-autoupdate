# pre-commit-autoupdate

![GitHub branch status][branch status]
![GitHub Issues][issues]
![GitHub last commit][last commit]
![GitHub repo size][repo size]
![GitHub License][license]
![GitHub Sponsors][sponsors]

[branch status]: https://img.shields.io/github/checks-status/mosher-labs/pre-commit-autoupdate/main
[issues]: https://img.shields.io/github/issues/mosher-labs/pre-commit-autoupdate
[last commit]: https://img.shields.io/github/last-commit/mosher-labs/pre-commit-autoupdate
[repo size]: https://img.shields.io/github/repo-size/mosher-labs/pre-commit-autoupdate
[license]: https://img.shields.io/github/license/mosher-labs/pre-commit-autoupdate
[sponsors]: https://img.shields.io/github/sponsors/mosher-labs

## Introduction

A pre-commit hook that automatically keeps your pre-commit hooks up to date.
On every commit, this hook runs `pre-commit autoupdate` and stages any changes
to `.pre-commit-config.yaml` so they're included in your commit.

### Key Features

- Automatically updates all pre-commit hooks to their latest versions
- Stages updated `.pre-commit-config.yaml` for inclusion in the current commit
- Works silently when no updates are available
- Zero configuration required
- Optional pinning to commit SHAs (`--freeze`)
- Optional throttling so the network check doesn't run on every commit

### How It Works

1. You run `git commit`
1. This hook runs `pre-commit autoupdate`
1. If any hooks were updated, the changes are automatically staged
1. Your commit includes the updated hook versions
1. On your next commit, the new hook versions will be used

## Usage

Add this hook to your `.pre-commit-config.yaml`:

```yaml
repos:
  # ... your other hooks ...
  - repo: https://github.com/mosher-labs/pre-commit-autoupdate
    rev: v1.0.0  # Use the latest release
    hooks:
      - id: autoupdate
```

Then install the hooks:

```bash
pre-commit install
```

### Options

Pass options with `args`. Anything the hook doesn't recognize is passed
through to `pre-commit autoupdate`.

- `--freeze`: pin `rev` to a commit SHA instead of a tag. The tag is kept
  as a `# frozen: vX.Y.Z` comment
- `--interval-hours N`: skip the check if it ran less than `N` hours ago.
  Default `0` (check on every commit)
- `--jobs N`: number of repos to check in parallel. Default `8`
- `--bleeding-edge`: update to the latest commit on `HEAD` instead of the
  latest tag
- `--repo URL`: only update this repo. Can be repeated
- `--min-age-days N`: keep a hook on its current rev until the GitHub release
  for its new tag is at least `N` days old. See
  [Minimum release age](#minimum-release-age)
- `--fail-on-update`: fail the commit when a rev is bumped, and leave the
  bump unstaged so you can review it and commit it on its own

Pin to SHAs and check at most once a day:

```yaml
  - repo: https://github.com/mosher-labs/pre-commit-autoupdate
    rev: v1.0.0
    hooks:
      - id: autoupdate
        args: [--freeze, --interval-hours, "24"]
```

Take only releases at least a week old, and review each bump:

```yaml
      - id: autoupdate
        args: [--freeze, --min-age-days, "7", --fail-on-update]
```

### Minimum release age

A new release can be compromised. `--min-age-days` gives the ecosystem time to
catch and pull a bad one before you adopt it. After `pre-commit autoupdate`
runs, the hook looks up the GitHub release for each bumped repo's new tag and
restores the old `rev` line if the release is too new.

The age comes from the release's `published_at`, which GitHub sets. Git tag
and commit dates are set by whoever made them, so the hook doesn't use them.
A bump is held when:

- the tag has no GitHub release, or the repo isn't on GitHub
- the API request fails, e.g. when rate limited. The next commit retries,
  even with `--interval-hours`
- with `--freeze`, a tag now points to a different commit. A release's date
  says nothing about which commit its tag points to, so a moved tag is always
  held

Bump those by hand. `--min-age-days` can't be combined with `--bleeding-edge`,
whose revs have no tag.

github.com repos use `https://api.github.com`. Set `PCA_GITHUB_API` to look up
all other repos elsewhere, such as GitHub Enterprise
(`https://github.example.com/api/v3`). The hook sends `GITHUB_TOKEN` or
`GH_TOKEN` to an `https` API when set, which raises the rate limit. pre-commit
hides a passing hook's output, so run `pre-commit run autoupdate --verbose` to
see which bumps were held.

### Performance

`pre-commit autoupdate` fetches every repo in your config over the network,
so its cost grows with the number of repos. The hook fetches up to 8 repos in
parallel. For the fastest commits, set `--interval-hours` so most commits skip
the check entirely. The last run time is stored in
`.git/pre-commit-autoupdate.stamp`. Delete it to force a check.

### Requirements

- [pre-commit](https://pre-commit.com/) must be installed and available in PATH
- Git repository with a `.pre-commit-config.yaml` file

### Recommended Placement

Place this hook **last** in your repos list. This ensures all other hooks run
first with the current versions, then updates are staged for the commit.

## Contributing

Upon first clone, install the pre-commit hooks:

```bash
pre-commit install
```

To run pre-commit hooks locally without a git commit:

```bash
pre-commit run -a --all-files
```

Run the tests (needs git and pre-commit). CI runs them on Linux and on macOS's
`/bin/bash`:

```bash
tests/run.sh
BASH_BIN=/bin/bash tests/run.sh   # test another bash
```
