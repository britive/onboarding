# Oracle Cloud with Python

Two scripts, one per Britive application type:

| Script | Application type | Creates | How Britive authenticates |
| ------ | ---------------- | ------- | ------------------------- |
| `setup_oci.py` | **OCI** (2.0) | Service user with an API signing key, group, tenancy policy | The user's API key, uploaded to Britive |
| `setup_oci_wif.py` | **OCI WIF** (identity domains) | Service user, group, identity propagation trust, optional admin grant and tenancy policy | Workload identity federation: the Britive tenant's own token is exchanged for the service user's; no key is stored |

Product steps: [OCI 2.0 prerequisites](https://docs.britive.com/docs/oracle-cloud2-prereqs) and
[policy](https://docs.britive.com/docs/creating-a-policy-in-oracle-cloud-oci2);
[OCI WIF onboarding guide](https://docs.britive.com/docs/oracle-cloud-infrastructure-oci-wif-onboarding-guide)
and [prerequisites](https://docs.britive.com/docs/prereq-oci-wif).

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## `setup_oci.py` (OCI application)

Authenticates with the OCI CLI configuration, as a tenancy administrator:

```bash
oci setup config            # tenancy administrator credentials in ~/.oci/config

# API signing key pair for the Britive service user
openssl genrsa -out britive-oci.pem 2048
openssl rsa -pubout -in britive-oci.pem -out britive-oci-public.pem

python3 setup_oci.py --email britive@example.com --public-key-file britive-oci-public.pem
```

| Option | Default |
| ------ | ------- |
| `--user-name` | `britive-service` |
| `--group-name` | `BritiveGroup` |
| `--policy-name` | `BritivePolicy` |
| `--config`, `--profile` | `~/.oci/config`, `DEFAULT` |

It prints the tenancy OCID, user OCID and key fingerprint to enter when
creating the application in Britive; the private key is `britive-oci.pem`.
Keep both PEM files out of the repository.

The script does not create identity-domain memberships: in a tenancy with
identity domains, add the user to **IdentityDomainAdministrator** in each
domain Britive should manage (Identity → Domains → *domain* → Groups).

Running it twice fails on the existing user; delete the objects or change
the names.

## `setup_oci_wif.py` (OCI WIF application)

The identity-domain objects are created through the domain's REST (SCIM)
API — the same calls Britive's guide shows as cURL — and are idempotent: an
existing user, group, membership, grant or trust is reported and kept.

### Before running

1. **In Britive:** create the application — **System Administration → Tenant
   Applications → Create Application → OCI WIF** — and copy the **Britive
   Issuer URL** from its Settings tab. Download the WIF certificate:
   **System Administration → Security → SAML Configurations → Download WIF
   Certificate**.
2. **In the OCI identity domain** (Identity & Security → Domains → *Default* →
   Integrated applications → Add application → **Confidential Application**):
   configure the application as a client with the **Client credentials**
   grant, client type **Trusted**, import the Britive WIF certificate under
   *Certificate*, submit, then **Activate** it. Copy the client ID and client
   secret.
3. Note the domain URL (Identity → Domains → *Default* → **Domain URL**).

The confidential application's token is what the script uses to create
everything else, so the application must be allowed to administer the domain
(an Identity Domain Administrator role on it; the console grants it to a
trusted client when you create one as an administrator).

### Run

```bash
cp .env.example .env        # OCI_DOMAIN_URL, OCI_CLIENT_ID, OCI_CLIENT_SECRET, BRITIVE_ISSUER_URL

python3 setup_oci_wif.py --certificate-file ~/Downloads/britive-wif.cer --dry-run
python3 setup_oci_wif.py --certificate-file ~/Downloads/britive-wif.cer --grant-domain-admin --create-policy
```

| Option | Default | Effect |
| ------ | ------- | ------ |
| `--certificate-file` | — | The Britive WIF certificate (PEM or DER); stored in the trust as base64 DER on one line |
| `--user-name`, `--display-name` | `britive-wif`, `Britive WIF` | Service user (`serviceUser: true`) |
| `--group-name` | `BritiveWIFGroup` | Group the policy statements name |
| `--trust-name` | `britive-wif` | Identity propagation trust: type JWT, issuer = Britive Issuer URL, `oauthClients` = the confidential app, `impersonationServiceUsers` rule `sub eq *` → the service user |
| `--grant-domain-admin` | off | Grant the service user **Identity Domain Administrator** (the guide's "Granting a Service User an Admin Role") |
| `--create-policy` | off | Create the tenancy policy below with the OCI SDK and `~/.oci/config` (`--config`, `--profile`); otherwise the statements are printed for the console |
| `--policy-name`, `--domain-name` | `BritiveWIFPolicy`, `Default` | Policy name; identity domain name used in the statements |
| `--dry-run` | off | Only reads; prints what would be created |

The policy, in the root compartment, is the one the guide gives:

```text
Allow group 'Default'/'BritiveWIFGroup' to inspect domains in tenancy
Allow group 'Default'/'BritiveWIFGroup' to inspect compartments in tenancy
Allow group 'Default'/'BritiveWIFGroup' to inspect policies in tenancy
Allow group 'Default'/'BritiveWIFGroup' to inspect users in tenancy
Allow group 'Default'/'BritiveWIFGroup' to inspect groups in tenancy
Allow group 'Default'/'BritiveWIFGroup' to use users in tenancy where target.group.name != 'Administrators'
Allow group 'Default'/'BritiveWIFGroup' to use groups in tenancy where target.group.name != 'Administrators'
```

### Then, in Britive

Back on the application's Settings tab enter the OCID of the tenancy
(Identity & Security → Domains → *Default* → OCID), the tenancy name, the
confidential application's client ID, the region identifier (e.g.
`us-phoenix-1`) and the identity domain URL, then **Save and Test** and
**Scan**. Profiles in an OCI WIF application grant OCI **groups**; the
groups are sent to OCI at checkout and OCI applies the policies defined for
them.

### Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `token request failed (401)` | Wrong client ID/secret, or the application is not activated | Check **General Information** of the confidential application; **Activate** it |
| `POST Users failed (403)` | The confidential application cannot administer the domain | Give it the Identity Domain Administrator role (application → *Application roles*) |
| `POST IdentityPropagationTrusts failed (400)` mentioning the certificate | Certificate not base64 DER on one line | Pass the downloaded file itself to `--certificate-file`; the script converts PEM |
| Trust already exists but with an old certificate or issuer | The script never modifies an existing trust | Delete it in the console (domain → Security → Identity propagation trust) and run again |
| **Save and Test** fails in Britive | Issuer URL in the trust differs from the application's, or the certificate in the confidential application is not the current WIF certificate | Compare the issuer with the Settings tab; re-import the certificate |
