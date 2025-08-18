$userEmail = $env:user_email
$resourceName = $env:ResourceName

$username = $userEmail.Split("@")[0]
$username = $username.Substring(0, [Math]::Min($username.Length, 16))
$username = "$username-rec"

$fullName = $userEmail
$description = "Local admin account created for Britive POV"

$logFile = "logs\${resourceName}.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function GenerateRandomPassword {
    $length = 12
    $validChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&+=_'
    $passwordChars = @()
    $rand = New-Object System.Random

    for ($i = 0; $i -lt $length; $i++) {
        $index = $rand.Next(0, $validChars.Length)
        $passwordChars += $validChars[$index]
    }

    return -join $passwordChars
}

function SignData {
    param([string]$data, [byte[]]$key)
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($key)
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
    $hashBytes = $hmac.ComputeHash($dataBytes)
    $hmac.Dispose()
    $combined = $hashBytes + $dataBytes
    return $combined
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
    $userPassword = GenerateRandomPassword
    $securePassword = ConvertTo-SecureString $userPassword -AsPlainText -Force

    $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue

    if (-not $userExists) {
        # Create user
        New-LocalUser -Name $username -Password $securePassword -FullName $fullName -Description $description | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $username | Out-Null
        Add-Content -Path $logFile -Value "$timestamp SUCCESS: Created local admin user '$username' with resource '$resourceName'." | Out-Null
    }
    else {
        # Reset password if user already exists
        Set-LocalUser -Name $username -Password $securePassword
        Add-Content -Path $logFile -Value "$timestamp INFO: Reset password for existing user '$username'." | Out-Null
    }

    # Guacamole JSON generation
    $connection = @{
        protocol   = "rdp"
        parameters = @{
            hostname         = "$env:hostname"
            port             = "$env:port"
            username         = "$username"
            password         = $userPassword
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

    $jsonObject = @{
        username    = "$username-$expires"
        expires     = $expires
        connections = @{ $resourceName = $connection }
    }

    $JSON = $jsonObject | ConvertTo-Json -Depth 10 -Compress

    $SECRET_KEY = $env:json_secret_key

    $keyBytes = [byte[]]::new($SECRET_KEY.Length / 2)
    for ($i = 0; $i -lt $SECRET_KEY.Length; $i += 2) {
        $keyBytes[$i / 2] = [Convert]::ToByte($SECRET_KEY.Substring($i, 2), 16)
    }

    $signedData = SignData -data $JSON -key $keyBytes
    $encryptedData = EncryptData -data $signedData -key $keyBytes
    $base64Token = [Convert]::ToBase64String($encryptedData)
    $TOKEN = [System.Web.HttpUtility]::UrlEncode($base64Token)

    $result = @{
        json  = $JSON
        token = $TOKEN
        url   = $env:url
    } | ConvertTo-Json -Compress

    Write-Output $result
}
catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp ERROR: $_"
    Write-Host "ERROR: $_"
}
