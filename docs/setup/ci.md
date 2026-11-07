# Minimal continuous integration

[Issue #26](https://github.com/JFrancoG/SmartShoppingList/issues/26) tracks the initial GitHub Actions validation and delivery. The workflow is [CI](../../.github/workflows/ci.yml).

## Checks and triggers

Pull requests targeting `main` and pushes to `main` run three independent jobs. The workflow also supports manual runs. Superseded runs for the same PR/ref are cancelled.

- **Contract and design system:** Python validates the API contract/examples and the documented color pairs, generated reports and color assets. Validation is read-only.
- **Server tests (Linux arm64):** the pinned Swift 6.4.0 image builds the server and all existing tests with `Package.resolved`, then executes Swift Testing against an isolated PostgreSQL service. The database name ends in `_testing`; the `db-test` host is already allowed by the test harness. Each job owns its temporary database, without published host ports or production credentials.
- **Server runtime image (Linux amd64)** builds the final Release image and starts it against disposable PostgreSQL with test Apple credentials. The [image check](../../scripts/check_server_image.sh) verifies migrations, the health response, authentication on protected routes and removal of the legacy todos routes.

The database image matches `server/docker-compose.yml`. Images are pinned by digest and actions by commit SHA. The repository token only has `contents: read`, and checkout does not persist it. There is no deploy step, self-hosted runner, signing material or connection to Railway.

The repository checks have a 10-minute limit and each server job has 30 minutes. The jobs retain `server-ci-logs` and `server-image-ci-logs` for seven days when available, including failed runs. Explicit Bash uses GitHub's `-e -o pipefail` behavior so `tee` cannot hide a build or test failure. First-party warnings remain errors through `Package.swift`. [EXC-001](../dependency-exceptions.md) documents the existing exception.

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

For server logic, inspect the arm64 test result. For Dockerfile, packaging or startup changes, inspect the amd64 image result. Reuse a successful job for the exact revision under review. Reproduce the affected check locally when results are missing, a failure needs diagnosis or the working tree changes its inputs.

For iOS logic and coordination, use the [Fast test plan](../../ios/SmartShoppingList/TestPlans/Fast.xctestplan). For local persistence and Keychain, use [Integration](../../ios/SmartShoppingList/TestPlans/Integration.xctestplan). A shared API change also needs the contract validator and the affected client and server tests. Device checks, real Apple services and deployment have separate evidence.
