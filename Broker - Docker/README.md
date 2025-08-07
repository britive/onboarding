# Session recording

These examples cover session recording features for SSH and RDP sessions curated by Britive Access Broker.

## Background

This example uses Britive Access Broker and Apache Guacamole to achieve proxied user session into servers and allows for video recording of the user session. These sessions are curated by Britive, are short-lived, and do not require end users to install any special tools or to copy credentials -- the credential rotation is handled entirely by Britive Access Broker.

Traditional remote access tools often run as a local client application, however, the Guacamole client requires nothing more than a modern web browser when accessing one of the served protocols, such as RDP/SSH/VNC.

Apache Guacamole’s `guacd` service, is the backend component responsible for proxying remote sessions between the Guacamole web interface and target systems. The `guacd` proxy handles the actual protocol communication and exposes the connection to the Guacamole web application.

By separating the frontend (web application) from the backend (`guacd`), Guacamole enables secure, clientless remote access through a browser without any additional plugins.

## Setup

This example helps with setting up the Britive broker and Guacd service under one Docker package. The following steps would allow for a quick deployment of these service to create ephemeral user session for RDP and SSH and record the same with the help of the guacd service.

1. Copy this directory on the desired server or virtual machine.
2. Download and store the broker .jar install from the Britive admin interface.
3. Update the broker-config.yml with the desired tenant subdomain and the token for the broker bootstrap.
4. Generate a JSON secret key (update the text as needed in the following command):  

    On Linux:

      ```sh
      echo -n "britiveallthethings" | md5 # `md5` on macos, `md5sum` on linux
      ```

    On Windows:

    ```powershell
    $input = "britiveallthethings"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    $md5 = [System.BitConverter]::ToString($hash) -replace "-", ""
    $md5.ToLower()
    ```

    Update the docker-compose.yml file with the generated key.

      ```yaml
      guacamole:
        environment:
          JSON_SECRET_KEY: "<json secret key goes here>"

      ```

5. While in the directory run Docker build process:

    ```sh
    docker build -t broker-docker .
    ```

6. Once complete, run the broker compose to stand up the services:

    ```sh
    docker compose up
    ```

This would complete the broker and guacamole install. The broker service would start automatically and you should see an instance of the broker running on britive admin portal.

> Info
>
> The synchronization option allow you to synchronize the recording to your AWS S3 bucket.
