# MobaXterm

MobaXterm has no pre-connect hook, so the integration is a script that
checks out the SSH key with `pybritive`, launches the bookmark, and checks
in again when MobaXterm closes. [`mobaxterm-checkout.ps1`](mobaxterm-checkout.ps1)
does that; run it from any PowerShell window or bind it to a MobaXterm
macro.

Tested with MobaXterm 24.x and pybritive 2.4 on Windows 11.

## 1. Alias the profile once

```powershell
pybritive checkout "<app>/<environment>/<profile>" --profile-type my-resources --alias demo_box
```

## 2. Point the bookmark at the key file

The script writes the key to `%USERPROFILE%\.britive\keys\<profile>.pem`
with an ACL that only your user can read. In the MobaXterm session
(**Advanced SSH settings → Use private key**) select that path; it exists
only while a checkout is active.

## 3. Run

```powershell
.\mobaxterm-checkout.ps1 -Profile demo_box                    # bookmark named like the profile
.\mobaxterm-checkout.ps1 -Profile demo_box -Bookmark "Prod web"
```

The script reads the `privateKey` key of the checkout's JSON; pass
`-Key <name>` if your response template uses another key. When MobaXterm
exits, the script runs `pybritive checkin` and deletes the file — no key is
left on the workstation. If MobaXterm is already open the launch returns
immediately and the key is removed again; close MobaXterm first or start a
second instance.
