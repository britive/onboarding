# Britive Terraform Example: Profile and Policy Management

This Terraform project demonstrates how to automate **Britive access control** using the [Britive Terraform provider](https://registry.terraform.io/providers/britive/britive/latest). It includes the creation and management of:

- Local Tags and Tag Members
- Profiles across multiple applications (EKS, AWS)
- Profile Permissions
- Profile Policies with approval workflows and access conditions

## 🧩 Use Case

This example is useful for organizations that want to automate access provisioning for cloud platforms (like AWS and EKS) using Just-In-Time (JIT) access policies. The profiles and policies defined here represent different user groups and their corresponding privileges.

## 📁 Project Structure

```bash
.
├── main.tf                # Main Terraform configuration
├── variables.tf           # Input variables for the provider
├── terraform.tfvars       # Values for input variables (not committed to version control)
├── outputs.tf             # (Optional) Outputs from resources
└── README.md              # This documentation
````

---

## 🔐 Prerequisites

* A [Britive](https://www.britive.com/) account with access to the Admin API.
* Terraform v1.3+ installed
* Britive Terraform provider `>= 2.1.0, < 2.1.5`
* Britive token with appropriate permissions
* Applications like **EKS** and **AWS Standalone** configured in Britive

## ⚙️ Setup

1. **Clone this repo**

   ```bash
   git clone https://your.repo.url
   cd britive-terraform-example
   ```

2. **Define required variables**

   Create a `terraform.tfvars` file with the following content:

   ```hcl
   britive-tenant = "your-tenant-id"
   britive-token  = "your-api-token"
   ```

3. **Initialize Terraform**

   ```bash
   terraform init
   ```

4. **Validate the configuration**

   ```bash
   terraform validate
   ```

5. **Apply the configuration**

   ```bash
   terraform apply
   ```

---

## 🚀 What It Does

### 🔖 Tags and Memberships

* Creates three tags: `k8s users`, `AWS admins`, and `S3 developers`
* Adds members (usernames) to the `k8s users` tag

### 📦 Applications

* Looks up existing applications: `EKS` and `AWS Standalone - Vin`

### 👤 Profiles and Policies

Creates 4 profiles with distinct use cases:

| Profile Name   | Application    | Permissions           | Description             |
| -------------- | -------------- | --------------------- | ----------------------- |
| JIT Admins     | EKS            | `jit-admins` (Group)  | EKS Namespace Admins    |
| AWS Power User | AWS Standalone | `Poweruser-role`      | General AWS Power Users |
| AWS S3 Admins  | AWS Standalone | `S3-Fullaccess-role`  | Admins for S3           |
| AWS EC2 Admins | AWS Standalone | `EC2-Fullaccess-role` | Admins for EC2          |

### ✅ Policies

Each profile is bound to a policy that includes:

* Access conditions (e.g. approval workflows, IP address restrictions)
* Approval notifications via Magic Link Email and Slack
* User or tag-based access control

---

## 📌 Notes

* The `identity_provider_id` is dynamically fetched based on the `Britive` Identity Provider.
* Ensure that all tag names, permission names, and approver values (users or tags) exist in your Britive environment.
* Sensitive data like API tokens should be stored securely (e.g. via environment variables, secrets managers, or CI/CD pipelines).

---

## 🔗 References

* [Britive Terraform Provider Docs](https://registry.terraform.io/providers/britive/britive/latest/docs)
* [Britive Admin API](https://docs.britive.com/apidocs/introduction-service-apis)
* [Britive Official Site](https://www.britive.com/)

---
