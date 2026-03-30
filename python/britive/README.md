# README

## Overview

This script automates various tasks using the Britive API, such as processing identity providers, user identities, service identities, applications, tags, and more. It interacts with the Britive platform to create and manage resources using a `.yaml` file (`britive/data_input.yaml`) as input.

## Prerequisites

### 1. Python Version

Ensure that you have Python 3.x installed on your machine.

### 2. Required Libraries

Install the following Python packages before running the script:

```bash
pip install britive pyyaml colorama jmespath python-dotenv
```

### 3. Environment Configuration

Create a `.env` file in the root directory with the following environment variables:

```
BRITIVE_TENANT=<Your Britive Tenant>
BRITIVE_API_TOKEN=<Your Britive API Token>
```

This information is required for the script to connect to the Britive API.

### 4. Input Data

The script reads from a YAML file located at `britive/data_input.yaml`, which contains the necessary information to create users, applications, tags, and more. Ensure that this file is properly formatted.

Example structure of `data_input.yaml`:

```yaml
users:
  - email: user@example.com
    firstname: John
    lastname: Doe
    username: johndoe
    idp: Britive

tags:
  - name: Tag1
    description: Sample tag
```

## Usage

You can run the script with specific options based on the task you want to perform:

```bash
python script.py [options]
```

### Available Options

- `-i`, `--idps`: Process Identity Providers
- `-u`, `--users`: Process User Identities
- `-s`, `--services`: Process Service Identities (reserved)
- `-t`, `--tags`: Process Tags
- `-a`, `--applications`: Process Applications
- `-p`, `--profiles`: Process Profiles for each application
- `-n`, `--notification`: Process Notification Mediums
- `-r`, `--resourceTypes`: Process creation of Resource Types
- `-b`, `--brokerPool`: Process broker pool (creates one primary broker pool)
- `--dry-run`: Simulate operations without making any changes to the Britive tenant

### Examples

Process users and tags:

```bash
python script.py --users --tags
```

Simulate processing identity providers and applications without making changes:

```bash
python script.py --idps --applications --dry-run
```

Process everything in dry-run mode:

```bash
python script.py -i -u -t -a -p -n -r -b --dry-run
```

## Output

The script outputs logs to the console, showing the progress for each resource being processed (e.g., users, applications, tags). In `--dry-run` mode, it will print what would be created without making any API calls.

## Script Flow

1. **Environment Setup**: Loads environment variables from the `.env` file.
2. **Input Parsing**: Reads `britive/data_input.yaml` for user, application, tag, and other resource data.
3. **Britive API Interaction**: Uses the Britive API to create and manage the specified resources.
4. **Command-line Argument Handling**: Choose which resources to process using command-line flags.
5. **Dry-Run Simulation**: Use `--dry-run` to preview the operations without executing them.

## Error Handling

If there is an issue with the Britive API or the input data, the script will print warning or error messages using the `colorama` library, providing visual cues with different colors:

- Red for errors
- Yellow for warnings
- Blue for informational messages
- Green for success indicators
