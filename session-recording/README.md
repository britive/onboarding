# Session recording

These examples cover session recording features for SSH and rDP sessions curated by Britive access broker.

## Background

This example uses Britive access broker and Apache Guacamole to achieve proxied user session into servers and allows for video recording of the user session. The sessions curated by Britive are short-lived and does nto require user to install any special tools or copying credentials. The credential rotation is compeltely handled by Britive access broker.

Apache Guacamole’s proxy service, called guacd, is the core backend component responsible for brokering remote desktop sessions between users and target systems. Unlike traditional remote access tools that run directly in a client application, Guacamole uses guacd to handle protocols like RDP, VNC, and SSH, and then streams the session over the web using HTML5. This proxy receives connection requests from the Guacamole web frontend and manages the actual protocol communication, abstracting it into a format that browsers can render. By separating the frontend (web application) from the backend (guacd), Guacamole enables secure, clientless remote access through a browser without plugins.

## [example_user.json](user.json)

Contains the JSON object to encode for use with the [Encrypted JSON Auth](https://guacamole.apache.org/doc/gug/json-auth.html)

### Example

```json
{
  "username": "first.last@britive.com",
  "expires": "1740000000000", // expiration in epoch time, including milliseconds
  "connections": {
    "connection-name": { // name to give the connection
      "protocol": "ssh", // connection protocol, e.g. ssh, rdp, vnc, etc.
      "parameters": {
        "hostname": "1.2.3.4", // hostname or IP
        "port": "22", // port
        "username": "ubuntu", // username
        "private-key": "...", // ssh private key, with substituted newlines, e.g. s/\n/\\n/g
        "recording-path": "/home/guacd/recordings", // location for recordings
        "recording-name": "${GUAC_DATE}-${GUAC_TIME}-${GUAC_USERNAME}-connection-name" // name of the recording
      }
    }
  }
}
```

> Additional connection parameter information: [configuring-connections](https://guacamole.apache.org/doc/gug/configuring-guacamole.html#configuring-connections)

## [encrypt-token.sh](encrypt-token.sh)

Sign and encrypt the `user.json` file, or any other file, with a JSON secret key.

### usage

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
{"token": "dziPjv9S6NgNgsA7V5TCsdUlxRb8OZO3h3Rbi52cfHS9An6hXgMfvpOMq3RLTBUFqC87j8RkN1jJ1zkyQa%2FgmiO07x2P%2FewLiKG86a60v%2BlUCv%2Blh9wd2ENMLjTnhmLhTWkpNgKHfQHQt%2F34K19vCl1Nyl4TPAJSDG%2Ffg6lngmQ1mN%2Fc1aa6iSWe7nm0p7hbYIlZqiF8I70Z1DhdWSSM6msAtMlMQmJirwPwRlaiN4FpUVM%2FN3isxoz0NdAjtNRZTjhTKXpJaUNX17Gyek9eo%2Bm8%2BGWWwZ7dFYNYusuECyRfS2iFyBGY5QQPk1%2F2LcVmtNJm%2BODGNujayEH89%2BQ8wmys5DY%2BByc92PgswrZQp6EwTAMnObT2nPqCnrh0wIeF3307ApcdIaqazlXUgqcboMPzP7ahK8rHGuzBWaf7%2B%2FwtDdLvTsEx6oSwJ%2FPLEiuSMvYO6Z72H5%2B1MqpVQil3hzmuaivilA263uYFky0tuJpT0zWErQD3nVXJQ%2B%2FGwqeOMcFSG8QvdW45KWZzgVF58aJO33%2FEO%2F8b8SI1a5nWvaFBRHEOfv6ftjhvbgkau4R1dN%2F9xMm9pfqAQOTdSzjJKWbcV2Emo%2BwlTocjP%2By%2F84HqLQtH8A%2BmRh9AjM8UqhW6QFoi50pd%2BF8IMiMeW2JcYX9zAD85semDdCzI2LnPVKtwe1KmfbJiDI%2BZ6ap2ZKyB"}
```
