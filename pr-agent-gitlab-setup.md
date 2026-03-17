# PR-Agent Setup for Self-Hosted GitLab (Azure OpenAI)

This guide provides a single-file setup for running PR-Agent as a Docker service to review Merge Requests in your self-hosted GitLab.

- [x] Verify PR-Agent interaction in Merge Requests <!-- id: 6 -->
- [x] Clarify cross-model support (LiteLLM) <!-- id: 7 -->
- [x] Craft and implement advanced PR_REVIEWER__INSTRUCTIONS <!-- id: 10 -->

---

## 1. Prerequisites

1.  **GitLab Personal Access Token**:
    - Create a PAT in GitLab (**User Settings > Access Tokens**).
    - Scopes: `api`, `read_repository`.
    - Role: `Maintainer` (required to post comments on MRs).
2.  **Shared Secret**:
    - Choose any random strong string (e.g., `XGCDzl1Hr...`).
    - This must match exactly in both your `docker-compose.yml` and your GitLab Webhook settings.
3.  **Azure OpenAI Credentials**:
    - `AZURE_OPENAI_ENDPOINT` (e.g., `https://your-resource.openai.azure.com`)
    - `AZURE_OPENAI_API_KEY`
    - `AZURE_OPENAI_DEPLOYMENT_ID` (e.g., `gpt-4o`)
    - `AZURE_OPENAI_API_VERSION` (e.g., `2024-02-15-preview`)

---

## 2. Docker Setup

Create a directory (e.g., `devops/pr-agent/`) and add the following files.

### .env

Create a file named `.env` in the same directory:

```bash
# GitLab Configuration
GITLAB__URL=https://git.knovator.in
GITLAB__PERSONAL_ACCESS_TOKEN=glpat-your-token
GITLAB__SHARED_SECRET=your-shared-secret

# Azure OpenAI Configuration
OPENAI__API_TYPE=azure
OPENAI__API_BASE=https://artha-openai-dev.openai.azure.com/
OPENAI__KEY=your-azure-api-key
OPENAI__API_VERSION=2024-12-01-preview
OPENAI__DEPLOYMENT_ID=gpt-4o

# Model Selection
CONFIG__MODEL=azure/gpt-4o
CONFIG__FALLBACK_MODELS=["azure/gpt-4o"]
CONFIG__CUSTOM_MODEL_MAX_TOKENS=128000
CONFIG__MAX_MODEL_TOKENS=32000

# Automation (Run commands automatically on MR created/updated)
# Note: Webhook server often uses GITLAB_APP__ prefix for automation
GITLAB_APP__PR_COMMANDS=["/describe", "/review", "/improve"]
GITLAB_APP__HANDLE_PUSH_TRIGGER=true
GITLAB_APP__PUSH_COMMANDS=["/review", "/improve"]

# Fallback (can keep both)
GITLAB__PR_COMMANDS=["/describe", "/review", "/improve"]
GITLAB__HANDLE_PUSH_TRIGGER=true
GITLAB__PUSH_COMMANDS=["/review", "/improve"]

# Behavior
PR_REVIEWER__INSTRUCTIONS="Act as a Senior Full-stack Engineer, DevOps Architect, and Security Specialist. Review for: 1) Security: Check for OWASP risks, hardcoded secrets/Pipes, and SQL/XSS vulnerabilities. 2) Logic: Identify edge cases, race conditions, and logical flaws. 3) DevOps: Check for CI/CD inefficiencies, container best practices, and resource leaks. 4) Code Quality: Ensure DRY, SOLID, and clean code. 5) Maintenance: Detect deprecated packages and future scaling bottlenecks. Be critical but constructive. Focus on impact."
PR_DESCRIPTION__ENABLE_LARGE_PR_HANDLING=true
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  pr-agent:
    image: codiumai/pr-agent:latest
    container_name: pr-agent
    ports:
      - "5000:3000"
    entrypoint: ["python", "pr_agent/servers/gitlab_webhook.py"]
    env_file: .env
    restart: always
```

---

## 3. GitLab Webhook Configuration

For each of the 3 repositories, set up a Webhook:

1.  Go to **Settings > Webhooks**.
2.  **URL**: `http://your-server-ip:5000/webhook` (notice port 5000)
3.  **Secret token**: Use the same as `CONFIG.SECRET_TOKEN` (e.g., `my-secret-webhook-token`).
4.  **Trigger**:
    - [x] Push events (required for automatic re-reviews on new code)
    - [x] Merge request events
    - [x] Comments
5.  **SSL verification**: Enable if using HTTPS, disable if using plain HTTP for testing.

---

## 4. Best Models for Code Review (Azure AI Foundry)

For the best results with PR-Agent, we recommend these models:

| Model | Use Case | Strength |
| :--- | :--- | :--- |
| **GPT-4o** (Default) | General Reviews | **Best Balance.** Fast, cheap, and very smart at descriptive reviews. |
| **o1-preview / o1-mini** | Complex Logic | **Deep Reasoning.** Better at catching subtle bugs and architectural issues. |
| **Llama-3.1-405B** | High Precision | **Powerhouse.** Available in Azure, rivals GPT-4o for technical Q&A. |

To change models, update `CONFIG__MODEL` and `CONFIG__FALLBACK_MODELS`.

---

## 5. Usage Commands

PR-Agent will automatically review new Merge Requests. You can also trigger it manually by typing commands in the **MR Comment section**.

| Command | Use Case | Result |
| :--- | :--- | :--- |
| `/describe` | Update the MR title and description. | Generates a structured summary & Mermaid diagram. |
| `/review` | Trigger a new code review. | Posts a comment with suggestions and a checklist. |
| `/improve` | Get specific code improvement suggestions. | Provides actionable diffs and code snippets. |
| `/ask "how is X?"` | Ask a question about the MR code. | AI answers based on the MR context. |
| `/generate_labels` | Categorize the MR automatically. | Adds GitLab labels like `bug`, `feature`, etc. |
| `/help` | List all available commands. | Posts a list of available actions. |

**Where to run**: Comments section of any Merge Request in GitLab.

---

## 6. Advanced: Custom Repository Rules (`.pr_agent.toml`)

While the `.env` file applies rules to **all** repositories, you can define specific reviews, tests, and security checks for individual repositories by creating a `.pr_agent.toml` file at the root of that repository.

### Why use `.pr_agent.toml`?
- Different projects have different testing strategies (e.g., Frontend vs. Backend).
- Rules are version-controlled alongside the code.
- You can enforce strict security and architecture guidelines.

### Template 1: Include rules directly in `.pr_agent.toml`
Create this file in the root directory of your repository (e.g., your `pipeline-improvements-admin` repo) and commit it to `main`:

```toml
[pr_reviewer]
extra_instructions="""
# 🚨 MANDATORY REVIEW GUIDELINES 🚨

Act as our Principal Software Engineer and QA Lead. You must strictly enforce the following rules for every Pull Request. If a rule is violated, you MUST flag it clearly in your review comment.

## 1. 🧪 Testing Strict Rules
- **Test Coverage**: Every new feature or API endpoint MUST include corresponding unit or integration tests. If tests are missing, explicitly state: "❌ Missing tests for new logic."
- **Happy & Sad Paths**: Verify that tests cover both the "Happy Path" (success, HTTP 200) and the "Sad Path" (failures, exceptions, HTTP 400/404/500).
- **Mocking**: Ensure external services are mocked appropriately in unit tests.

## 2. 🛡️ Security & Data Privacy
- **Hardcoded Secrets**: Scan aggressively for API keys, tokens, passwords, or connection strings.
- **Input Validation**: Check that all incoming payload data is validated to prevent SQL Injection and XSS.

## 3. 🏗️ Architecture & Logic Design
- **Separation of Concerns**: Controllers should ONLY handle web requests. All business logic must live in Services/UseCases.
- **Error Handling**: Catch exceptions gracefully. Do not let unhandled errors crash the process.

## 4. 🧹 Code Quality & Clean Code
- **Naming Conventions**: Variables and functions must have descriptive, English names.
- **DRY Principle**: Suggest abstracting copy-pasted code into shared helpers.
- **Dead Code**: Flag commented-out code blocks or unused variables for removal.
"""

[pr_description]
extra_instructions="""
- Ensure the description clearly explains *WHY* the change was made, not just *WHAT* changed.
"""
```

### Template 2: Link to an existing Markdown file
If you already have a Markdown file containing your rules (e.g., `AI_RULES.md` in your repository), you do not need to copy-paste. You can simply tell PR-Agent to read it!

```toml
[pr_reviewer]
extra_instructions="""
Before reviewing this code, you MUST read the custom guidelines defined in the file `AI_RULES.md` located in the root of this repository. Strictly enforce all testing, security, and architecture rules defined within that file. If any changes violate these rules, flag them immediately.
"""

[pr_description]
extra_instructions="""
Ensure the description meets the formatting guidelines defined in our `AI_RULES.md` file.
"""
```

---

## 7. Troubleshooting Automation

If manual commands (like `/review`) work but automation does not:

1.  **Check GitLab Webhook Triggers**:
    - Go to your Project -> **Settings > Webhooks**.
    - Click **Edit** on your webhook.
    - Ensure **"Merge request events"** and **"Push events"** are checked.
2.  **Inspect Recent Events**:
    - Scroll down on the Webhook page to **"Recent events"**.
    - If you see a `Merge Request Hook` or `Push Hook` with status **200**, the server is receiving it but the config is stopping it.
    - If you don't see them, GitLab isn't sending them.
3.  **Check `.env` Variable Names**:
    - Ensure you are using `GITLAB_APP__PR_COMMANDS` (with double underscores).
    - Restart after changes: `docker compose up -d --force-recreate`.
