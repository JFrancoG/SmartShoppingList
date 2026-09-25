# Minimal continuous integration

[Issue #26](https://github.com/JFrancoG/SmartShoppingList/issues/26) tracks the initial GitHub Actions validation and delivery. The workflow is [CI](../../.github/workflows/ci.yml).

## Checks and triggers

Pull requests targeting `main` and pushes to `main` run two independent jobs. A manual run is also available once the workflow reaches the default branch. Superseded runs for the same PR/ref are cancelled.

- **Contract and design system:** Python validates the API contract/examples and the documented color pairs, generated reports and color assets. Validation is read-only.
- **Server tests (Linux arm64):** the pinned Swift 6.4.0 image builds the server and all existing tests with `Package.resolved`, then executes Swift Testing against an isolated PostgreSQL service. The database name ends in `_testing`; the `db-test` host is already allowed by the test harness. Each job owns its temporary database, without published host ports or production credentials.

The database image matches `server/docker-compose.yml`. Images are pinned by digest and actions by commit SHA. The repository token only has `contents: read`, and checkout does not persist it. There is no deploy step, self-hosted runner, signing material or connection to Railway.

The jobs have 10/30-minute limits. Server build/test output is retained in the run log and uploaded as `server-ci-logs` for seven days when available, including failed runs. Explicit Bash uses GitHub's `-e -o pipefail` behavior so `tee` cannot hide a build or test failure. First-party warnings remain errors through `Package.swift`; [EXC-001](../dependency-exceptions.md) stays visible with its existing narrow scope.

## Local reproduction

From the repository root, with Python 3.10 or later:

```bash
python3 -m venv /tmp/smartshoppinglist-ci-venv
/tmp/smartshoppinglist-ci-venv/bin/python -m pip install -r scripts/requirements-contract.txt
/tmp/smartshoppinglist-ci-venv/bin/python scripts/validate_contract.py
/tmp/smartshoppinglist-ci-venv/bin/python scripts/validate_design_system.py
```

For server tests, use the isolated PostgreSQL instructions in [the server README](../../server/README.md#postgresql-y-pruebas). Native macOS tests are useful local evidence but do not establish a successful Linux CI run; inspect the linked workflow execution for that result.

## Scope and limits

This workflow does not build iOS, perform physical accessibility/Speech/Apple sign-in checks, test production, or deploy. It does not build the Release Docker runtime or claim amd64 coverage. Branch protection is unchanged: failed checks are visible, but the workflow alone does not make them mandatory for merging. iOS CI, caching and automatic deployment are outside this MVP setup.
