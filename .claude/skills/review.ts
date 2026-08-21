/**
 * Skill: /review
 * Description: Fetches a PR from GitHub, performs code review, and outputs results. NEVER posts comments to GitHub without asking the user first.
 * Usage: /review <URL or #PR-number>
 */

async function review(prInput: string) {
  // Clean input - supports both URL and #number
  const id = prInput.replace(/.*\/pull\//, '').replace('#', '').trim();

  return `
You received a GitHub Pull Request link. Perform a complete code review following these steps:

1. **Fetch PR metadata** using: gh pr view ${id} --json title,body,author,headRefName,baseRefName,url,comments,reviews

2. **Fetch PR diff** using: gh pr diff ${id}

3. **Fetch complete code state after PR changes** (checkout PR branch locally):
   - Use: gh pr checkout ${id}
   - Read all changed files in their final form (not just the diff)
   - Check context around changes, dependencies, connections
   - After review completion, return to original branch: git checkout -

4. **Perform analysis:**
   - Logic check: Is the implementation correct? Did functionality change unintentionally?
   - Code quality: Readability, idioms, error handling, edge cases
   - Security: OWASP top 10, injection, XSS, auth/authz issues
   - Tests: Do they cover the changes? Are they meaningful?
   - Compare with PR description and discussion

5. **Output:**
   - Summary of changes
   - List of findings (bug, security, style, nit) with file:line references
   - Verdict: APPROVE / REQUEST CHANGES / COMMENT

**IMPORTANT:**
- ❌ NEVER post comments to GitHub without asking the user first (gh pr comment, gh pr review --approve)
- ✅ Only read from GitHub (gh pr view, gh pr diff, gh pr checkout)
- ✅ Output review results directly to console

Begin review of PR #${id}.
  `;
}
