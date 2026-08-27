---
description: Goes through open PRs in the current project's repo, filters out approved/draft/blocked ones, and reviews them interactively (review posted to GitHub only after confirmation, in English).
---

You are in the directory of some project connected to GitHub. Perform an assisted
review of open pull requests according to the following steps. Write the actual
review comments on GitHub concisely and in English.

## 1. Determine the context

- Determine the logged-in user: `gh api user -q .login` (referred to below as <ME>).
- Verify you are in a git repo connected to GitHub: `gh repo view --json nameWithOwner -q .nameWithOwner`.
  If it fails, tell me that the current directory is not a GitHub repository and stop.

## 2. Fetch and filter open PRs

Download open PRs with everything needed for filtering:

```
gh pr list --state open --limit 100 \
  --json number,title,author,isDraft,labels,latestReviews,url,updatedAt
```

From the result, OMIT (skip) PRs that meet any of the following:

- **My own PR** — `author.login == <ME>`.
- **Draft** — `isDraft == true`.
- **Already approved by me** — there is an entry in `latestReviews` with
  `author.login == <ME>` and `state == "APPROVED"`.
- **Blocking label** — any label whose name (case-insensitive, after
  normalizing spaces/dashes) matches: `hold`, `do-not-merge`, `do not merge`,
  `dnm`, `wip`, `work in progress`, `blocked`, `needs-rebase`. Also account for
  variants like `do-not-merge/hold`.

Sort the remaining PRs in ascending order by number (from the oldest / smallest ID).

## 3. List the queue

Print a clear table of PRs to review: number, author, title, url. State how many
were filtered out and why (briefly). If nothing is left to review, say so and stop.

## 4. Determine the repo's review rules

Before starting the first review, find out what the review should follow. Search
the repo (root and `.github/`) in this order and use the first one found:

1. `AGENTS.md`, `CLAUDE.md` (and their imports)
2. `CONTRIBUTING.md`, `.github/CONTRIBUTING.md`
3. `.github/PULL_REQUEST_TEMPLATE.md`, `docs/` review/coding guidelines

If the repo has no such instructions, **use the fallback checklist from the
`zkontroluj` skill**: check logic/regressions, code quality (readability, idioms,
error handling, edge cases), security (OWASP, injection, authz), tests, and
consistency with the PR description. Focus only on more serious problems, not
minor nitpicks.

## 5. Review one by one (interactively)

Proceed from the oldest. For each PR:

1. Fetch metadata and discussion:
   `gh pr view <N> --json title,body,author,headRefName,baseRefName,url,comments,reviews`
2. Fetch the diff: `gh pr diff <N>`
3. Check out the branch to read the code in its final form (not just the diff):
   `gh pr checkout <N>` — read the changed files in context, verify the connections.
   Where it makes sense, verify claims via build/tests (per the repo's instructions).
   After finishing the review, switch back: `git checkout -`.
4. Perform the analysis according to the rules from step 4.
5. Print the result to me in the console: a summary of the changes, a list
   of findings with file:line references, and a verdict (APPROVE / REQUEST CHANGES / COMMENT).
6. **Ask me whether and how to post the review to GitHub** — and WAIT for the answer:
   - Post to GitHub ONLY after my explicit confirmation.
   - Write the review concisely and in English.
   - Approve without a comment: `gh pr review <N> --approve`
   - Approve with a comment: `gh pr review <N> --approve --body "..."`
   - Comment/changes: `gh pr review <N> --comment --body "..."` /
     `--request-changes --body "..."`
   - If I say no, don't send anything and move on.
7. Move on to the next PR in the queue.

## IMPORTANT

- ✅ Do READ operations from GitHub (`gh pr list/view/diff/checkout`) right away, without asking.
- ⚠️ Do NOT post any review/comment to GitHub without my explicit confirmation.
- ⚠️ Always write review comments in English and concisely.
- Always ask before posting and wait for the answer — one PR at a time.

Start with step 1.
