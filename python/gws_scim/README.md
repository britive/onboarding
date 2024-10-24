
# README for Britive SCIM Simulation Script

## Overview

This script is designed to simulate SCIM (System for Cross-domain Identity Management) actions using data from Britive scans. It compares local application data with the Britive tenant data to synchronize users, groups (tags), and their entitlements. It can create, enable, disable users, and assign or remove entitlements based on the differences detected between these datasets.

## Features

- **Scan Application Data**: Gathers user and group data from a specified application.
- **Collect Tenant Data**: Retrieves user and group data from the Britive tenant.
- **Diff Calculation**: Compares local application users and groups with tenant data to identify discrepancies.
- **Automate Changes**: Automatically creates users, groups (tags), and assigns/removes entitlements.
- **Error Handling**: Prevents action if the number of users to disable exceeds a defined threshold.
- **Interactive Confirmation**: Optionally prompts for confirmation before proceeding with changes.

## Requirements

- Python 3.x
- `britive` Python SDK
- `python-dotenv` to load environment variables

## Installation

1. Install the required packages:
   ```bash
   pip install britive python-dotenv
   ```

2. Set up your environment variables in a `.env` file:

   ```
   APP_GROUP=<Your Application Group Name>
   GROUP_PREFIX=<Prefix for Britive Group>
   APP_ID=<Application ID>
   IDP_ID=<Identity Provider ID>
   ```

3. Optionally set `LOG_LEVEL` in your environment to control logging verbosity (`INFO` by default).

## Usage

Run the script via the command line:

```bash
python script.py
```

### Command Line Arguments

- `-n` or `--num-allowable-users-to-disable-before-error`: The threshold for the number of users that can be disabled before the script halts (default is 10).
  
- `--confirm/--no-confirm`: Toggles whether to require user confirmation before performing any actions.

- `-f` or `--log-file`: Specifies the path to a log file to record log entries. If omitted, logging is only to the console.

### AWS Lambda

This script includes an optional `handler` function to run it in an AWS Lambda environment. The `process()` function is wrapped in the `handler` for compatibility with Lambda triggers.

### Example Command

```bash
python script.py --num-allowable-users-to-disable-before-error 5 --no-confirm
```

## Logging

Logging is configured to print messages both to the console and (if specified) to a file. It logs important events, such as the number of users to create, disable, and enable, as well as any entitlements and tags to modify.

## Functions

- **`ScanScim` Class**:
  - **`scan_application()`**: Initiates a scan for the application.
  - **`collect_scan_data()`**: Gathers user and group data from the application.
  - **`collect_tenant_data()`**: Gathers user and group data from the Britive tenant.
  - **`diff()`**: Calculates differences between local application data and tenant data.
  - **`create_users()`, `enable_users()`, `disable_users()`**: Handles user lifecycle management.
  - **`create_tags()`, `create_entitlements()`, `remove_entitlements()`**: Manages group (tag) creation and user assignment.

## Error Handling

- The script will stop execution if the number of users to be disabled exceeds the defined threshold.
- It raises exceptions for missing application users, unexpected errors during scans, and other potential failures.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
