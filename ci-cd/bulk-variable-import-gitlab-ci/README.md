# GitLab CI/CD Variable Importer

A simple bash script to bulk import environment variables into a GitLab project from a `.env` file.

## 🚀 Quick Start

### 1. Generate GitLab Personal Access Token (PAT)
To use this script, you need an API token with appropriate permissions:
1. Log in to your GitLab instance (e.g., `https://git.knovator.in`).
2. Go to **User Settings** (top-right avatar) -> **Access Tokens**.
3. Click **Add new token**.
4. Give it a name (e.g., `Variable Importer`).
5. **Select scopes**: Check **`api`** only.
6. Click **Create personal access token**.
7. **Copy the token immediately** (you won't see it again).

### 2. Configure the Script
Open `ci-variable-import.sh` and update the following variables in the `CONFIG` section:

```bash
# ========= CONFIG =========
GITLAB_URL="https://git.knovator.in"      # Your GitLab URL
PROJECT_ID="726"                          # Your Project ID (found on Project Overview page)
PRIVATE_TOKEN="your_token_here"           # The PAT you generated in Step 1

# Optional: Default settings for variables
PROTECTED=false                           # Set to true if only for protected branches
MASKED=false                              # Set to true to hide value in job logs
RAW=false                                 # Set to true to disable variable expansion
```

### 3. Prepare your Variables
Create or edit a file named `variables.env` in the same directory. Add your variables in `KEY=VALUE` format:

```env
API_KEY=123456789
DEBUG=true
DB_NAME=production_db
```

### 4. Run the Script
Make sure the script is executable and run it:

```bash
chmod +x ci-variable-import.sh
./ci-variable-import.sh
```

## 🛠 Features
- **Robust Parsing**: Handles files without trailing newlines.
- **Windows Friendly**: Automatically removes `\r` (carriage returns) from files created on Windows.
- **Error Handling**: 
    - ✅ **Created**: Successfully added.
    - ⚠️ **Skipped**: Variable already exists in the project.
    - ❌ **Failed**: Shows the error message from GitLab (e.g., invalid token or project ID).

## ⚠️ Security Note
**Do not commit your `PRIVATE_TOKEN` to version control.** It is recommended to use a `.gitignore` file or pass the token as an environment variable if you plan to share this repository.
