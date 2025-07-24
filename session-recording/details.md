# Other Details on the service

Apache Guacamole’s `guacd` service **does not need software installed on the Windows server** to initiate an RDP session. But it **does need network-level access** and **valid credentials**. Let’s break this down:

---

## 🧠 TL;DR

Apache Guacamole (`guacd`) doesn’t install anything on your Windows server.
It initiates RDP over the network using:

* 📡 Open TCP port 3389 (or reachable via NAT/VPN/VPC/etc.)
* 🔑 A valid login (via credentials you provide)
* 🧠 And it renders the session via WebSocket to your browser.

📖 [Guacamole JSON Authentication](https://guacamole.apache.org/doc/gug/json-auth.html)

---

## ✅ What Guacamole *Needs* (to RDP into a Windows server)

1. **RDP Port Reachability (TCP 3389)**

   * The Windows server must have RDP enabled.
   * `guacd` (the RDP client) must be able to reach it over the network (i.e., no firewall or routing blocks).
   * This is usually accomplished by putting `guacd` in the same VPC/subnet or opening firewall rules.

2. **A Valid User Credential (Username & Password or Smart Card)**

   * Guacamole does not need a local agent or software on the Windows machine.
   * It simply uses RDP to log in — just like Microsoft’s Remote Desktop Client would.

## ❌ What Guacamole *Does Not* Need

* ❌ No Guacamole agent installed on the Windows server.
* ❌ No prior login or local software configuration.
* ❌ No browser plugin or remote tunnel from the Windows host.

## 🔍 So… “How does it work without access?”

The trick is that Guacamole **is just acting as a headless RDP client**. As long as it can:

* **Reach the server's IP and port 3389**, and
* **Use valid credentials**,
  then it can initiate an RDP session like any other remote desktop client.

**You don’t need admin rights on the Windows server — just RDP login rights.**

## 🔒 Security Implication

* Guacamole gives you a centralized place to manage and control RDP access.
* But **you still need to secure the backend RDP servers** (firewall, NLA, strong auth).
* You can use Just-in-Time access, vault tools, or Britive-style ephemeral accounts to make it safer.

## ✅ What is Guacamole JSON Authentication?

The **Guacamole JSON Authentication extension** allows a reverse proxy or authentication broker (like NGINX, Apache, or a custom app) to supply **connection parameters and credentials via a signed JSON file**.

This file **bypasses the need for user logins in Guacamole’s own UI**. The file defines who can connect and to what — no database, LDAP, or SSO integration needed in the web app.

## 📦 How It Works: High-Level Flow

1. A client browser hits Guacamole’s `/` page.
2. The reverse proxy injects a `GUAC_DATA_SOURCE` cookie containing a **JWT-signed JSON file**.
3. Guacamole (the web app, not `guacd`) uses that cookie to:

   * Authenticate the user.
   * Define available connections.
   * Pass connection details to `guacd`.
4. Guacamole web app connects to `guacd`, which **initiates the actual RDP/SSH/VNC session**.

## 🔐 Security: Signing and Trust

* The JSON must be **signed** using a secret key that Guacamole knows (configured in `guacamole.properties`).
* Guacamole verifies the signature before accepting the connection definitions.
* If the JWT is tampered with, authentication fails.

## 🧾 JSON Auth Example

```json
{
  "username": "alice",
  "expires": 1724344338000,
  "connections": {
    "example-rdp": {
      "protocol": "rdp",
      "parameters": {
        "hostname": "10.0.0.5",
        "port": "3389",
        "username": "alice",
        "password": "MySecurePass"
      }
    }
  }
}
```

This defines:

* One user (`alice`)
* One RDP connection (`example-rdp`)
* `guacd` will receive all of these connection details when the user connects via the browser.

## 🧩 Role of `guacd` in This Setup

Just like in all other setups:

* `guacd` is **not aware** of the JSON or the JWT token.
* It **only receives** connection instructions (host, port, credentials) from the Guacamole web app.
* The **JSON authentication step happens fully inside the web app layer** before the connection is passed to `guacd`.

## 🛠️ Deployment Steps

1. Enable the JSON auth extension in your Guacamole deployment:

   * Download from: [https://guacamole.apache.org/releases/](https://guacamole.apache.org/releases/)
   * Place in `/etc/guacamole/extensions/`

2. Configure `guacamole.properties`:

   ```properties
   json-secret-key: supersecretkey
   ```

3. Generate JWT-signed JSON and set it as a cookie for your users:

   ```http
   Set-Cookie: GUAC_DATA_SOURCE=...signed_token...;
   ```

4. Users hit `/guacamole/`, and the session is built from the signed token.

---

## 🧠 Summary

| Component             | Role                                                |
| --------------------- | --------------------------------------------------- |
| `guacamole-auth-json` | Authenticates users via signed JSON (JWT)           |
| Browser               | Gets the token (via cookie or URL)                  |
| Guacamole Web App     | Parses JSON, builds connection, forwards to `guacd` |
| `guacd`               | Connects to the actual RDP/VNC/SSH server           |

This is great for **ephemeral connections**, **SSO proxies**, or platforms like **Britive**, **HashiCorp Boundary**, or your own portal that builds temporary sessions dynamically.

---
