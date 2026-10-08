# Tenant bootstrap from YAML

`setup.py` creates the objects a new tenant or POC needs from one YAML file:
identity providers, users, tags, applications with their environments and
profiles, notification mediums, broker pools, and resource types with
permissions, resources and resource profiles.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env                       # BRITIVE_TENANT, BRITIVE_API_TOKEN
cp data_input-template.yaml data_input.yaml   # gitignored; edit
```

The API token needs tenant-administrator permissions for whatever you
select. Python 3.10+.

## Run

```bash
python3 setup.py --dry-run -i -u -t -a -p -n -b -r    # print the plan, change nothing
python3 setup.py -t -u                                  # tags, then users
python3 setup.py -a -p                                  # applications, then their environments and profiles
python3 setup.py --help
```

| Flag | Creates |
| ---- | ------- |
| `-i`, `--idps` | Identity providers (`idps:`) |
| `-u`, `--users` | Users (`users:`) with a random initial password that is never printed |
| `-t`, `--tags` | Tags on the local Britive identity provider (`tags:`) |
| `-a`, `--applications` | Applications from the catalog by type name (`apps:`) |
| `-p`, `--profiles` | Environments and profiles under each application (`apps[].envs`, `apps[].profiles`); run with `-a` in the same invocation |
| `-n`, `--notification` | Notification mediums (`notification:`; Slack needs `url` and `token`) |
| `-b`, `--broker-pools` | Broker pools (`brokerPools:`) |
| `-r`, `--resource-types` | Resource types, permissions, resources, resource profiles (`resourcesTypes:`) |
| `--data-file` | Another YAML file |
| `--dry-run` | Print every action; make no write call |

`Expiration` values are milliseconds. Permission `checkout`/`checkin` are
file paths to scripts, or inline commands; permissions with an empty `name`
are skipped. See [`data_input-template.yaml`](data_input-template.yaml) for
every section.

## Notes

- Errors stop the run with a non-zero exit and the API message; objects
  created before the error stay. Re-runs are not idempotent for every object
  type (users and tags with the same name fail), so run `--dry-run` first.
- The previous `setup_legacy.py` (JSON input, wrote IDs back into the file)
  was removed; this script covers everything it did.
