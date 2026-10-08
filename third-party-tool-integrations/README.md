# Third-party tool integrations

Small recipes for using `pybritive` checkouts from desktop tools, so the
credential never has to be copied by hand.

| Tool | Recipe | Script |
| ---- | ------ | ------ |
| [DBeaver](dbeaver.md) | *Password from Shell Command* authentication runs a checkout on every connect | [`dbeaver-password.sh`](dbeaver-password.sh) |
| [MobaXterm](mobaxterm.md) | A macro checks out an SSH key, launches the session, checks in | [`mobaxterm-checkout.ps1`](mobaxterm-checkout.ps1) |

Both assume [`pybritive`](https://github.com/britive/python-cli) 2.3+ is
installed and configured (`pybritive configure tenant`, `pybritive login`).
Tested with pybritive 2.4 on 2026-10-08.

What a checkout prints depends on the profile's **response template**; the
scripts read the JSON keys named below and say where to change them.
