# Azure Britive Integration

This Python script automates the process of registering a Britive application in Azure Active Directory and assigning custom roles at the Tenant Root Group level.

## Prerequisites

- Python 3.6 or higher
- Azure Subscription and Tenant ID
- Azure credentials with necessary permissions

## Installation

1. **Install Required Packages**
2. 
   Install the required Azure SDK packages using pip:

    ```bash
    pip install azure-identity azure-core azure-graphrbac azure-mgmt-authorization python-dotenv
    ```