# Complete Guide: Grafana Alerting to ClickUp Chat

This is a 100% self-contained guide to connect your Grafana alerts to a ClickUp Chat channel. It covers the **ClickUp side**, the **Grafana SMTP server**, and the **Alerting configuration**.

---

## 🛠️ Phase 1: ClickUp Setup (Inbound Email)

ClickUp allows you to send emails directly into a chat channel.

1.  Open ClickUp and go to your **Chat Channel**.
2.  Click the **ellipsis (...)** menu next to the channel name.
3.  Select **Settings** -> **Email to Channel**.
4.  **Copy** the unique email address (e.g., `chat+12345@clickup.com`).
    *   *Note: This works on all plans, including Free.*

---

## 🛠️ Phase 2: Grafana SMTP Configuration

Grafana needs an SMTP server to send the "Email to Channel" notification. You must edit the `grafana.ini` file on your Ubuntu server.

1.  Open your terminal and edit the configuration:
    ```bash
    sudo nano /etc/grafana/grafana.ini
    ```
2.  Find the `[smtp]` section and update it (example using Gmail):
    ```ini
    [smtp]
    enabled = true
    host = smtp.gmail.com:587
    user = your-email@gmail.com
    # Use an App Password if using Gmail/Outlook
    password = your-app-password 
    from_address = admin@yourdomain.com
    from_name = Grafana Monitoring
    startTLS_policy = MandatoryStartTLS
    ```
3.  **Save** (Ctrl+O, Enter) and **Exit** (Ctrl+X).
4.  **Verify & Restart (The "Safe" Way)**:
    Since Grafana doesn't have a direct `nginx -t` command, follow these steps to ensure a smooth restart:
    
    *   **Syntax Check**: Open a second terminal and run:
        ```bash
        grep -A 10 "\[smtp\]" /etc/grafana/grafana.ini
        ```
        Ensure your settings are correctly indented under `[smtp]` and no duplicate `[smtp]` sections exist.
        
    *   **Monitor Logs**: Run this command to watch logs in real-time:
        ```bash
        sudo journalctl -u grafana-server -f
        ```
        
    *   **Restart Service**: In your main terminal, run the restart:
        ```bash
        sudo systemctl restart grafana-server
        ```
        *Watch the second terminal (logs). If you see "Server is stopping" followed by "HTTP Server Listen", it was successful.*

---

## 🛠️ Phase 3: Grafana Alerting Config

Now connect Grafana to the ClickUp email address.

1.  In Grafana UI, go to **Alerting** -> **Contact points**.
2.  Click **"+ Add contact point"**.
3.  **Name**: `ClickUp Chat`
4.  **Integration**: `Email`
5.  **Addresses**: Paste the `chat+...@clickup.com` address from Phase 1.
6.  Click **Save contact point**.

### (Optional) Customizing the Message
To make messages look like real alerts in chat, go to **Notification Templates** and add:
**Name**: `clickup_format`
**Content**:
```go
{{ define "subject" }}🚨 {{ .Status | toUpper }}: {{ (index .Alerts 0).Labels.alertname }}{{ end }}
{{ define "message" }}
Alert Details:
{{ range .Alerts }}
- **Status**: {{ .Status | toUpper }}
- **Component**: {{ .Labels.instance }}
- **Summary**: {{ .Annotations.summary }}
[Open Alert]({{ .GeneratorURL }})
{{ end }}
{{ end }}
```
Then, in your **Contact Point** (Optional Email settings), set:
- **Subject**: `{{ template "subject" . }}`
- **Body**: `{{ template "message" . }}`

---

## 🛠️ Phase 4: Link Alert Rules

1.  Go to **Alerting** -> **Notification policies**.
2.  Edit your **Default policy** (or create a specific one).
3.  Set the **Contact point** to `ClickUp Chat`.
4.  Click **Save policy**.

---

## ✅ Phase 5: Test & Verify

1.  Go to **Contact points** -> Edit `ClickUp Chat`.
2.  Click **"Test"** -> **"Send test notification"**.
3.  Wait 30-60 seconds.
4.  Verify the message appears in your **ClickUp Chat channel**.

> [!NOTE]
> If it fails, check Grafana logs for SMTP errors: `sudo journalctl -u grafana-server`.
