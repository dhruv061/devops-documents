# Python Service Setup Guide

Complete guide to set up the AI python service on a new Ubuntu server.

---

## Prerequisites

- Ubuntu Server (20.04/22.04/24.04)
- User: `azureuser` (or your preferred user)
- Application files cloned to `/home/azureuser/public_html/ai-resume-parser`

---

## Step 1: Install Python 3.11

```bash
# Add deadsnakes PPA for Python versions
sudo add-apt-repository ppa:deadsnakes/ppa -y

# Update package list
sudo apt update

# Install Python 3.11 with venv support
sudo apt install -y python3.11 python3.11-venv python3.11-dev

# Verify installation
python3.11 --version
```

---

## Step 2: Create Virtual Environment

```bash
cd /home/azureuser/public_html/ai-resume-parser

# Create virtual environment
python3.11 -m venv renv-py311

# Activate virtual environment
source renv-py311/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt

# Install gunicorn for production
pip install gunicorn

# Deactivate
deactivate
```

---

## Step 3: Configure Environment Variables

Ensure your `.env` file is configured:

```bash
nano /home/azureuser/public_html/ai-resume-parser/.env
```

Add your required environment variables (API keys, database URLs, etc.)

---

## Step 4: Test the Application

```bash
cd /home/azureuser/public_html/ai-resume-parser
source renv-py311/bin/activate

# Test with gunicorn
gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
```

Press `Ctrl+C` to stop after confirming it works.

---

## Step 5: Create Systemd Service

### Create the service file:

```bash
sudo nano /etc/systemd/system/resume-parser.service
```

### Paste this content:

```ini
[Unit]
Description=python Service
After=network.target

[Service]
User=azureuser
WorkingDirectory=/home/azureuser/public_html/ai-resume-parser
ExecStart=/home/azureuser/public_html/ai-resume-parser/renv-py311/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
StandardOutput=file:/var/log/artha_resume_parser_service.log
StandardError=file:/var/log/artha_resume_parser_service_error.log
SyslogIdentifier=Resume-Parser
Restart=on-failure
RestartSec=5
Environment="PATH=/home/azureuser/public_html/ai-resume-parser/renv-py311/bin"

[Install]
WantedBy=multi-user.target
```

Save with `Ctrl+O`, `Enter`, `Ctrl+X`

---

## Step 6: Create Log Files

```bash
sudo touch /var/log/artha_resume_parser_service.log
sudo touch /var/log/artha_resume_parser_service_error.log
sudo chown azureuser:azureuser /var/log/artha_resume_parser_service.log
sudo chown azureuser:azureuser /var/log/artha_resume_parser_service_error.log
```

---

## Step 7: Enable and Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable resume-parser.service

# Start the service
sudo systemctl start resume-parser.service

# Check status
sudo systemctl status resume-parser.service
```

Expected output should show **active (running)** in green.

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `sudo systemctl status resume-parser` | Check service status |
| `sudo systemctl restart resume-parser` | Restart the service |
| `sudo systemctl stop resume-parser` | Stop the service |
| `sudo systemctl start resume-parser` | Start the service |
| `sudo journalctl -u resume-parser -f` | View live systemd logs |
| `tail -f /var/log/artha_resume_parser_service.log` | View application logs |
| `tail -f /var/log/artha_resume_parser_service_error.log` | View error logs |

---

## Troubleshooting

### Service exits immediately
- Check logs: `cat /var/log/artha_resume_parser_service_error.log`
- Ensure gunicorn is installed in the virtual environment
- Verify the ExecStart path is correct

### Permission denied errors
- Ensure files are owned by azureuser: `chown -R azureuser:azureuser /home/azureuser/public_html/ai-resume-parser`
- Ensure log files have correct permissions

### Port already in use
- Check what's using port 5000: `sudo lsof -i :5000`
- Kill the process or change the port in the service file

### Missing dependencies
- Activate venv and reinstall: `pip install -r requirements.txt`

---

## Configuration Reference

| Setting | Value |
|---------|-------|
| Service Name | `resume-parser.service` |
| Working Directory | `/home/azureuser/public_html/ai-resume-parser` |
| Python Version | 3.11 |
| Virtual Environment | `renv-py311` |
| WSGI Server | Gunicorn |
| Port | 5000 |
| Workers | 2 |
| Log File | `/var/log/artha_resume_parser_service.log` |
| Error Log | `/var/log/artha_resume_parser_service_error.log` |

---

## Updating the Application

```bash
# Navigate to app directory
cd /home/azureuser/public_html/ai-resume-parser

# Pull latest code
git pull

# Activate virtual environment
source renv-py311/bin/activate

# Install any new dependencies
pip install -r requirements.txt

# Deactivate
deactivate

# Restart service
sudo systemctl restart resume-parser.service
```

---

*Last Updated: January 15, 2026*
