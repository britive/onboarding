# Checkout: runs on the Windows target itself (for example via SSM Run Command).
# Creates a temporary local administrator with a random password and returns a
# signed Guacamole token that opens a recorded RDP session as that user.
# Pair with checkin-rdp.ps1.
#
# Environment: user_email, ResourceName, hostname, port, json_secret_key
#              (32 hex chars), url, expiration (seconds, default 3600)

Add-Type -AssemblyName System.Web

$userEmail    = $env:user_email
$resourceName = $env:ResourceName

$username = $userEmail.Split("@")[0]
$username = $username.Substring(0, [Math]::Min($username.Length, 16))
$username = "$username-rec"

$fullName    = $userEmail
$description = "Local admin account created by Britive"

$logDir  = Join-Path $env:ProgramData "Britive\logs"
$logFile = Join-Path $logDir "$resourceName.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# CSPRNG password that satisfies Windows complexity: upper, lower, digit, special.
function GenerateRandomPassword {
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $digits  = '0123456789'
    $special = '@#$%^&+=_'
    $all     = $upper + $lower + $digits + $special

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = [byte[]]::new(4)

    function Pick([string]$set) {
        $rng.GetBytes($buf)
        $set[[BitConverter]::ToUInt32($buf, 0) % $set.Length]
    }

    $chars = @((Pick $upper), (Pick $lower), (Pick $digits), (Pick $special))
    for ($i = 0; $i -lt 12; $i++) { $chars += Pick $all }

    # Fisher-Yates shuffle so the guaranteed classes are not always first
    for ($i = $chars.Length - 1; $i -gt 0; $i--) {
        $rng.GetBytes($buf)
        $j = [BitConverter]::ToUInt32($buf, 0) % ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }

    $rng.Dispose()
    return -join $chars
}

function SignData {
    param([string]$data, [byte[]]$key)
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($key)
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
    $hashBytes = $hmac.ComputeHash($dataBytes)
    $hmac.Dispose()
    return $hashBytes + $dataBytes
}

function EncryptData {
    param([byte[]]$data, [byte[]]$key)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key[0..15]
    $aes.IV = [byte[]]::new(16)
    $encryptor = $aes.CreateEncryptor()
    $encryptedBytes = $encryptor.TransformFinalBlock($data, 0, $data.Length)
    $encryptor.Dispose()
    $aes.Dispose()
    return $encryptedBytes
}

try {
    $SECRET_KEY = $env:json_secret_key
    if (-not $SECRET_KEY -or $SECRET_KEY -notmatch '^[0-9A-Fa-f]{32}$') {
        throw "json_secret_key must be 32 hex characters (openssl rand -hex 16)"
    }

    $userPassword   = GenerateRandomPassword
    $securePassword = ConvertTo-SecureString $userPassword -AsPlainText -Force

    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $username -Password $securePassword | Out-Null
    } else {
        New-LocalUser -Name $username -Password $securePassword -FullName $fullName -Description $description | Out-Null
    }
    if (-not (Get-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group "Administrators" -Member $username | Out-Null
    }

    Add-Content -Path $logFile -Value "$timestamp SUCCESS: Created local admin user '$username' with resource '$resourceName'."

    $connection = @{
        protocol   = "rdp"
        parameters = @{
            hostname         = "$env:hostname"
            port             = "$env:port"
            username         = "$username"
            password         = "$userPassword"
            security         = "nla"
            "ignore-cert"    = "true"
            "recording-path" = "/home/guacd/recordings"
            "recording-name" = "`${GUAC_DATE}-`${GUAC_TIME}-${userEmail}-${username}-${resourceName}"
        }
    }

    $expiration = $env:expiration
    if (-not $expiration) { $expiration = 3600 }
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expires = ([int64]$epoch + [int64]$expiration) * 1000

    # Guacamole username is the Britive email, like every other checkout script
    $jsonObject = @{
        username    = $userEmail
        expires     = "$expires"
        connections = @{ $resourceName = $connection }
    }

    $JSON = $jsonObject | ConvertTo-Json -Depth 10 -Compress

    $keyBytes = [byte[]]::new($SECRET_KEY.Length / 2)
    for ($i = 0; $i -lt $SECRET_KEY.Length; $i += 2) {
        $keyBytes[$i / 2] = [Convert]::ToByte($SECRET_KEY.Substring($i, 2), 16)
    }

    $signedData    = SignData -data $JSON -key $keyBytes
    $encryptedData = EncryptData -data $signedData -key $keyBytes
    $base64Token   = [Convert]::ToBase64String($encryptedData)
    $TOKEN         = [System.Web.HttpUtility]::UrlEncode($base64Token)

    $result = @{
        token = $TOKEN
        url   = $env:url
    } | ConvertTo-Json -Compress

    Write-Output $result
}
catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp ERROR: $_"
    Write-Host "ERROR: $_"
    exit 1
}
