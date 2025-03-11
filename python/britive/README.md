
# README

## Overview

This script automates various tasks using the Britive API, such as processing identity providers, user identities, service identities, applications, tags, and more. It interacts with the Britive platform to create and manage resources using a `.json` file (`britive/data_input.json`) as input.

## Prerequisites

### 1. Python Version

Ensure that you have Python 3.x installed on your machine.

### 2. Required Libraries

Install the following Python packages before running the script:

```bash
pip install britive simplejson colorama jmespath python-dotenv
```

### 3. Environment Configuration

Create a `.env` file in the root directory with the following environment variables:

```
BRITIVE_TENANT=<Your Britive Tenant>
BRITIVE_API_TOKEN=<Your Britive API Token>
```

This information is required for the script to connect to the Britive API.

### 4. Input Data

The script reads from a JSON file located at `britive/data_input.json`, which contains the necessary information to create users, applications, tags, and more. Ensure that this file is properly formatted.

Example structure of `data_input.json`:

```json
{
    "users": [
        {
            "email": "user@example.com",
            "firstname": "John",
            "lastname": "Doe",
            "username": "johndoe",
            "idp": "Britive"
        }
    ],
    "tags": [
        {
            "name": "Tag1",
            "description": "Sample tag"
        }
    ]
    ...
}
```

## Usage

You can run the script with specific options based on the task you want to perform:

```bash
python script.py [options]
```

### Available Options

- `-i`, `--idps`: Process Identity Providers
- `-u`, `--users`: Process User Identities
- `-s`, `--services`: Process Service Identities
- `-t`, `--tags`: Process Tags
- `-a`, `--applications`: Process Applications
- `-p`, `--profiles`: Process Profiles for each application
- `-n`, `--notification`: Process Notification Mediums
- `-r`, `--resourceTypes`: Process creation of Resource Types
- `-b`, `--brokerPool`: Process broker pool. Creates one primary broker pool
- `-o`, `--resourceProfiles`: Process creation of Resource Profiles

### Example

To process users and tags, run:

```bash
python script.py --users --tags
```

### Output

The script outputs logs to the console, showing the progress for each resource being processed (e.g., users, applications, tags).

## Script Flow

1. **Environment Setup**: The script loads environment variables from the `.env` file.
2. **Input Parsing**: Reads `britive/data_input.json` for user, application, tag, and other resource data.
3. **Britive API Interaction**: The script uses the Britive API to create and manage the specified resources.
4. **Command-line Argument Handling**: You can choose which resources to process (identity providers, users, tags, etc.) using command-line arguments.
5. **Data Persistence**: Updates made to users, tags, or applications are written back to `data_input.json`.

## Error Handling

If there is an issue with the Britive API or the input data, the script will print warning or error messages using the `colorama` library, providing visual cues with different colors (red for errors, yellow for warnings, blue for info, green for success).

## License

This project is licensed under the MIT License.
