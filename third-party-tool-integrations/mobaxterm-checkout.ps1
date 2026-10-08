# MobaXterm: check out an SSH private key with pybritive, write it to a file
# only the current user can read, launch the bookmark, then check in and
# delete the key when MobaXterm exits.
#
# Usage:  mobaxterm-checkout.ps1 -Profile <pybritive profile or alias> [-Bookmark <name>] [-Key privateKey]
#
# The profile's response template decides the JSON key holding the PEM;
# "privateKey" is the common choice. Tell the MobaXterm session to use the
# key file path printed below (Advanced SSH settings > Use private key).

param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$Bookmark = $Profile,
    [string]$Key = "privateKey",
    [string]$MobaXterm = "C:\Program Files (x86)\Mobatek\MobaXterm\MobaXterm.exe"
)

$ErrorActionPreference = "Stop"

$keyDir = Join-Path $env:USERPROFILE ".britive\keys"
New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
$keyFile = Join-Path $keyDir "$Profile.pem"

$checkout = pybritive checkout $Profile --silent --mode json --profile-type my-resources | ConvertFrom-Json
if (-not $checkout.$Key) { throw "key '$Key' not in the checkout output; check the profile's response template" }

# Write with no inheritance and read access for the current user only.
Set-Content -Path $keyFile -Value $checkout.$Key -Encoding ASCII -NoNewline
icacls $keyFile /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null
Write-Host "key written to $keyFile"

try {
    Start-Process -FilePath $MobaXterm -ArgumentList "-bookmark `"$Bookmark`"" -Wait
}
finally {
    pybritive checkin $Profile --profile-type my-resources
    Remove-Item -Path $keyFile -Force -ErrorAction SilentlyContinue
    Write-Host "checked in and removed $keyFile"
}
