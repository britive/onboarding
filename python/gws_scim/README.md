# Britive SCIM Sync Script

## Overview

This script syncs users, groups (tags), and entitlements between a Britive application and the Britive tenant, using SCIM-like behavior.

It can be run from the command line or as an AWS Lambda.

It compares application data with Britive tenant data and takes appropriate action to:

- Create or enable users
- Disable users (with safeguards)
- Create missing groups (tags)
- Add/remove entitlements to/from users

## Key Features

- **Application Scan**: Extracts user and group data from your Britive application (e.g. Google Workspace).
- **Tenant Sync**: Collects current user/tag/entitlement data from Britive.
- **Smart Diffing**: Identifies changes needed for alignment.
- **Automated Actions**: OPTIONALLY applies changes (user lifecycle, group creation, entitlement mapping).
- **Safeguards**: Prevents excessive user disablement with a configurable threshold.
- **Detailed Logging**: Console and optional file logging for audit trails.
- **CLI + AWS Lambda Support**: Use as a local script or deploy in serverless environments.

## Requirements

- Python 3.9+
- [`britive`](https://pypi.org/project/britive/)
- [`tomli`](https://pypi.org/project/tomli/)

## Installation

```bash
# Set up virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Configuration

Configuration is managed through the `scan_config.toml` file.

### Configuration Reference

| Required | Section | Name | Value | Description |
| -------- | ------- | ---- | ----- | ----------- |
| N | base | `log_level` | `"INFO"` | Logging level, e.g. `INFO`, `DEBUG`, etc. |
| Y | `[britive]` | `app_id` | `"..."` | Britive Application ID to scan |
| N | `[britive]` | `federation_provider` | `"..."` | Federation Provider, if being used |
| N | `[britive]` | `idp_id` | `"..."` | Identity Provider ID if not using the default `Britive` IdP |
| N | `[britive]` | `tenant` | `"..."` | Britive Tenant to perform actions against |
| N | `[britive]` | `token` | `"..."` | Britive API Token for authentication |
| Y | `[group_name]` | n/a | n/a | Name of an application group to scan and include |
| N | `[group_name]` | `prefixes` | `["prefix-one-", "prefix-two"]` | Names of application group prefixes to include in scan |

> There can be as many `[group_name]` sections as desired, each will be included in scan and subsequent actions.

### Optional Environment Variables

```sh
BRITIVE_TENANT="{tenant-name}"
BRITIVE_API_TOKEN="{api-token}"
LOG_LEVEL="{log-level}"
```

#### Environment Variable Reference

| Variable | Description |
| -------- | ----------- |
| `BRITIVE_TENANT` | Subdomain of your Britive URL (e.g. `example` from `example.britive-app.com`) |
| `BRITIVE_API_TOKEN` | API token for authentication |
| `LOG_LEVEL` | Set to `DEBUG`, `INFO`, etc. (default: `INFO`) |

## Usage

```bash
python scan_scim.py
```

### Optional Arguments

| Flag | Description |
|------|-------------|
| `--user-cap`, `-u` | Threshold number of Britive users to allow automated disablement. (default: 10) |
| `--confirm`, `-c` | Require confirmation before making changes |
| `--log-file`, `-f` | Absolute path for where to emit log entries to file - in addition to console logging. |
| `--skip-scan`, `-s` | Useful during debugging to skip repeatedly scanning the organization and environment(s) |

#### Example

```bash
python scan_scim.py -u 5 --confirm -f scan_scim.log
```

## AWS Lambda Support

The script includes a `handler(event, context)` function to enable AWS Lambda deployment.

AWS EventBridge can be used to initiate sync runs on a schedule, or triggered via API Gateway.

## Logging

Logs key metrics and changes to:

- Console - always.
- File - if `--log-file` is specified

Includes counts of users to be created, enabled, disabled, and changes to entitlements(tags).

## Function Overview

| Class/Function | Description |
|----------------|-------------|
| `TenantData` | Retrieves current users, tags, and entitlements from Britive |
| `scan_application()` | Scans source application for users and groups |
| `ScanScim` | Collects scan data for each application group |
| `ScanScim.diff()` | Computes diffs between app and tenant |
| `create_users()` | Creates newly discovered users |
| `enable_users()` | Enables existing disabled users if granted entitlement(s) in scanned groups |
| `disable_users()` | Disables existing users if removed from all scanned groups |
| `create_tags()` | Creates missing Britive tags |
| `create_entitlements()` | Creates scanned entitlements for users |
| `remove_entitlements()` | Removes dropped entitlements for users |
| `process` | Orchestrates full sync cycle |
| `handler` | AWS Lambda entry point |

## Error Handling & Safeguards

- Exits with error if number of users to disable exceeds defined threshold.
- Provides detailed exceptions for scan failures or invalid configurations.
- Confirms actions to be taken - if `--confirm` is explicitly provided.

## License

MIT License – See [LICENSE](../../LICENSE)
