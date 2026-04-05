---
description: Scan for likely secrets, dangerous config patterns and sensitive leaks
agent: security-auditor
subtask: true
---

Scan for likely secrets, dangerous config patterns and sensitive local leaks.

You are the **security-auditor** role. Report findings, don't auto-fix.

Workflow:

1. Search for high-confidence secret patterns:
   - API keys: `grep -rn "sk-[a-zA-Z0-9]\\{20,\\}" --include="*.ts" --include="*.js" --include="*.json" --include="*.yml" --include="*.md" . 2>/dev/null | grep -v node_modules | grep -v ".env.example" | head -20`
   - Passwords in code: `grep -rn "password.*=.*['\"]" --include="*.ts" --include="*.js" --include="*.yml" . 2>/dev/null | grep -v node_modules | grep -v ".env.example" | grep -v "process.env" | head -20`
   - Private keys: `find . -name "*.pem" -o -name "*.key" -o -name "*.p12" 2>/dev/null | grep -v node_modules`

2. Check .gitignore coverage:
   - `.env` files excluded?
   - `secrets/` excluded?
   - `*.pem`, `*.key` excluded?

3. Check for unsafe patterns:
   - Secrets in docker-compose (not using `${VAR}` substitution)
   - Hardcoded URLs with credentials
   - JWT secrets in source code
   - API tokens in workflow JSON files

4. Check existing security tooling:
   - `.gitleaks.toml` config
   - GitHub Actions security scan workflows

5. Produce:

   ## High Confidence Leaks
   Actual secrets found in repo (CRITICAL).

   ## Suspicious Patterns
   Might be secrets, need human review.

   ## False Positive Candidates
   Patterns that look like secrets but are safe.

   ## .gitignore Coverage
   What's protected, what's missing.

   ## Remediation Steps
   Ordered by severity.

6. Return: severity assessment + immediate actions needed
