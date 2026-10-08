# Oracle Cloud with Python

`setup_oci.py` creates the service user (with its API signing key), the
group and the tenancy policy the Britive **OCI** application needs, using
the four policy statements Britive documents for OCI 2.0.

Product steps and prerequisites:
[OCI 2.0 prerequisites](https://docs.britive.com/docs/oracle-cloud2-prereqs),
[policy](https://docs.britive.com/docs/creating-a-policy-in-oracle-cloud-oci2).

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
oci setup config            # tenancy administrator credentials in ~/.oci/config

# API signing key pair for the Britive service user
openssl genrsa -out britive-oci.pem 2048
openssl rsa -pubout -in britive-oci.pem -out britive-oci-public.pem
```

## Run

```bash
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
