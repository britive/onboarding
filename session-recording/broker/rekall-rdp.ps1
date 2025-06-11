# Set default values or use environment variables
$USER_EMAIL = $env:BRITIVE_USER_EMAIL
if (-not $USER_EMAIL) { $USER_EMAIL = "test@example.com" }

# Extract username from email (before @) and remove invalid characters
$USERNAME = $USER_EMAIL.Split("@")[0] -replace '[^a-zA-Z0-9\.]', ''

$DOMAIN = if ($env:domain) { $env:domain } else { "ad.britivetest.com" }

function Finish {
    param($code)
    # Write-Host "Exiting with code $code"
    exit $code
}

# Build expiration timestamp in milliseconds since epoch
$expiration = $env:expiration
if (-not $expiration) { $expiration = 3600 }
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$expires = ([int64]$epoch + [int64]$expiration) * 1000

# Set other required variables from environment
$connection_name = $env:connection_name
$hostname = $env:hostname
$port = $env:port
$security = if ($env:security) { $env:security } else { "nla" }
$ignore_cert = if ($env:ignore_cert) { $env:ignore_cert } else { "true" }
$recording_path = if ($env:recording_path) { $env:recording_path } else { "/home/guacd/recordings" }
$GUAC_DATE = Get-Date -Format yyyy-MM-dd
$GUAC_TIME = Get-Date -Format HH-mm-ss
$json_secret_key = $env:json_secret_key
$url = $env:url

$recording_name = "$GUAC_DATE-$GUAC_TIME-$USER_EMAIL-$USERNAME-$connection_name"

# Create JSON object
$jsonObj = @{
    username = $USER_EMAIL
    expires = "$expires"
    connections = @{
        $connection_name = @{
            protocol = "rdp"
            parameters = @{
                hostname = $hostname
                port = $port
                security = $security
                "ignore-cert" = $ignore_cert
                username = $USERNAME
                domain = $DOMAIN
                "recording-path" = $recording_path
                "recording-name" = $recording_name
            }
        }
    }
}

# Convert to JSON
$JSON = ($jsonObj | ConvertTo-Json -Depth 10 -Compress)


# Sign function: return HMAC-SHA256 signature + JSON
function Sign {
    param($json, $key)
 
    $keyBytes = for ($i = 0; $i -lt $key.Length; $i += 2) {
        [Convert]::ToByte($key.Substring($i, 2), 16)
    }

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $sigBytes = $hmac.ComputeHash($jsonBytes)

    # Combine signature and JSON
    $combined = New-Object System.IO.MemoryStream
    $combined.Write($sigBytes, 0, $sigBytes.Length)
    $combined.Write($jsonBytes, 0, $jsonBytes.Length)
    $combinedArray = $combined.ToArray()

    # Return combined byte array as base64 string (to Encrypt)
    $b64 = [Convert]::ToBase64String($combinedArray)
    return $b64
}


# Encrypt function: AES-128-CBC with IV=0 and no salt
function Encrypt {
    param($data, $keyHex)
    $iv = [byte[]](0..15 | ForEach-Object { 0 })
    $keyBytes = for ($i = 0; $i -lt $keyHex.Length; $i += 2) {
        [Convert]::ToByte($keyHex.Substring($i, 2), 16)
    }

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.KeySize = 128
    $aes.Key = $keyBytes
    $aes.IV = $iv

    $encryptor = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($data)
    $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    $encryptedBase64 = [Convert]::ToBase64String($cipherBytes)
    return $encryptedBase64
}

# Sign then encrypt
$signedPayload = Sign -json $JSON -key $json_secret_key
$encrypted = Encrypt -data $signedPayload -keyHex $json_secret_key

# URI encode
$token = [System.Web.HttpUtility]::UrlEncode($encrypted)

# Output final JSON
$output = @{
    token = $token
    url = $url
} | ConvertTo-Json -Compress

Write-Host $output

Finish 0