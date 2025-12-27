# pre-commit-autoupdate

![GitHub branch status](https://img.shields.io/github/checks-status/mosher-labs/pre-commit-autoupdate/main)
![GitHub Issues](https://img.shields.io/github/issues/mosher-labs/pre-commit-autoupdate)
![GitHub last commit](https://img.shields.io/github/last-commit/mosher-labs/pre-commit-autoupdate)
![GitHub repo size](https://img.shields.io/github/repo-size/mosher-labs/pre-commit-autoupdate)
![GitHub License](https://img.shields.io/github/license/mosher-labs/pre-commit-autoupdate)
![GitHub Sponsors](https://img.shields.io/github/sponsors/mosher-labs)

## Introduction

A pre-commit hook that automatically keeps your pre-commit hooks up to date.
On every commit, this hook runs `pre-commit autoupdate` and stages any changes
to `.pre-commit-config.yaml` so they're included in your commit.

### Key Features

- Automatically updates all pre-commit hooks to their latest versions
- Stages updated `.pre-commit-config.yaml` for inclusion in the current commit
- Works silently when no updates are available
- Zero configuration required

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
