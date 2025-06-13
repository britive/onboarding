# Session recording

These examples cover session recording features for SSH and RDP sessions curated by Britive Access Broker.


## Background

This example uses Britive Access Broker and Apache Guacamole to achieve proxied user session into servers and allows for video recording of the user session. These sessions are curated by Britive, are short-lived, and do not require end users to install any special tools or to copy credentials -- the credential rotation is handled entirely by Britive Access Broker.

Traditional remote access tools often run as a local client application, however, the Guacamole client requires nothing more than a modern web browser when accessing one of the served protocols, such as RDP/SSH/VNC.

Apache Guacamole’s `guacd` service, is the backend component responsible for proxying remote sessions between the Guacamole web interface and target systems. The `guacd` proxy handles the actual protocol communication and exposes the connection to the Guacamole web application.

By separating the frontend (web application) from the backend (`guacd`), Guacamole enables secure, clientless remote access through a browser without any additional plugins.

## [example_user.json](user.json)

Contains the JSON object to encode for use with the [Encrypted JSON Auth](https://guacamole.apache.org/doc/gug/json-auth.html)

### Example

```py
{
  "username": "first.last@britive.com",
  "expires": "1750000000000", # expiration in epoch time, including milliseconds
  "connections": {
    "connection-name": { # name to give the connection
      "protocol": "ssh", # connection protocol, e.g. ssh, rdp, vnc, etc.
      "parameters": {
        "hostname": "1.2.3.4", # hostname or IP
        "port": "22", # port
        "username": "ubuntu", # username
        "private-key": "...", # ssh private key, with substituted newlines, e.g. s/\n/\\n/g
        "recording-path": "/home/guacd/recordings", # location for recordings
        "recording-name": "${GUAC_DATE}-${GUAC_TIME}-${GUAC_USERNAME}-connection-name" # name of the recording
      }
    }
  }
}
```

> Additional connection parameter information: [configuring-connections](https://guacamole.apache.org/doc/gug/configuring-guacamole.html#configuring-connections)

## [encrypt-token.sh](encrypt-token.sh)

Sign and encrypt the `user.json` file, or any other file, with a JSON secret key.

### Usage

```sh
./encrypt-token.sh <json-secret-key> <file>
```

### Example

#### Generate a JSON secret key

```sh
$ echo -n "britiveallthethings" | md5 # `md5` on macos, `md5sum` on linux
fb57d11d533339aea1e37c2a5a1cb92c
```

#### Encrypt a token with the generated JSON secret key

```sh
./encrypt-token.sh fb57d11d533339aea1e37c2a5a1cb92c user.json
{"token": "dziPjv9S6NgNgsA7V5TCsdUlxRb8OZO3h3Rbi52cfHS9An6hXgMfvpOMq3RLTBUFqC87j8RkN1jJ1zkyQa%2FgmiO07x2P%2FewLiKG86a60v%2BlUCv%2Blh9wd2ENMLjTnhmLhTWkpNgKHfQHQt%2F34K19------oSwJ%2FPLEiuSMvYO6Z72H5%2----------JiDI%2BZ6ap2ZKyB"}
```
