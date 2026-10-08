# DBeaver

DBeaver can obtain a connection password from a command instead of storing
it: **Password from Shell Command** authentication runs the command on every
connect and uses the first line of its output. Point it at a `pybritive`
checkout and the database credential is minted just in time and never
saved by DBeaver.

Tested with DBeaver 24.x and pybritive 2.4.

## 1. Alias the profile once

```bash
pybritive checkout "<app>/<environment>/<profile>" --profile-type my-resources --alias prod-db
```

## 2. Enable the authentication method

**Window → Preferences → Connections → Enable password retrieval via CLI**
(wording varies by version; it is the setting that unlocks the *Password
from Shell Command* authentication type).

## 3. Configure the connection

Edit the connection → **Main** → **Authentication: Password from Shell
Command** → command:

```text
/path/to/dbeaver-password.sh prod-db
```

Use absolute paths: DBeaver does not inherit your shell's `PATH`, which is
also why [`dbeaver-password.sh`](dbeaver-password.sh) resolves `pybritive`
and `jq` explicitly (override with the `PYBRITIVE` / `JQ` environment
variables if they live elsewhere).

The script prints the `password` key of the checkout's JSON. If your
profile's response template uses another key, pass it as the second
argument: `/path/to/dbeaver-password.sh prod-db db_password`.

## Notes

- The checkout's username is usually fixed per profile; put it in the
  connection's *Username* field.
- Profiles that need approval block until approved; raise DBeaver's connect
  timeout or approve before connecting.
- Older DBeaver versions without this authentication type can run the same
  script from **Shell Commands → Before Connect** and copy the result to the
  clipboard, but that leaves the credential in the clipboard; prefer the
  authentication method.
