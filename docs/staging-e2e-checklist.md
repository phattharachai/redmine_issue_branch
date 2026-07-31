# Staging E2E Checklist

Use this checklist to validate `redmine_issue_branch` 0.2.0 against a real
Redmine 6.1 staging instance and a disposable Git repository. The automated
test harness covers branch lookup and message enrichment with a temporary bare
repository. This checklist covers Redmine import persistence, issue
association, configuration, and operational evidence.

## Safety and assumptions

- Use a staging-only Redmine project, Issue, and repository.
- Never use production credentials or a production repository.
- Keep `close_by_merge` disabled. This feature is unavailable in 0.2.0.
- Keep the plugin disabled until configuration and repository scope have been
  reviewed.
- Create a new commit for every test case. Redmine may skip a revision already
  persisted by `save_revision`.
- Do not merge the positive-case commit into `main`, `master`, or another
  protected branch before importing it.
- Do not delete Issues, Changesets, branches, or repositories as part of the
  test. Cleanup is a separate, reviewed operation.
- Record only sanitized repository paths and audit logs. Do not record
  credentials, repository URLs, full commit messages containing sensitive
  data, environment variables, stack traces, or exception messages.

## Test record

| Field | Value |
|---|---|
| Test date/time and timezone | `<YYYY-MM-DD HH:MM:SS TZ>` |
| Redmine version | `<CHANGE_ME>` |
| Rails version | `<CHANGE_ME>` |
| Ruby version | `<CHANGE_ME>` |
| PostgreSQL version | `<CHANGE_ME>` |
| Plugin version | `0.2.0` |
| Plugin commit SHA | `<40_HEX_CHANGE_ME>` |
| Repository type | `Git` |
| Sanitized repository path | `<STAGING_PATH_CHANGE_ME>` |
| Protected branch configuration | `<CHANGE_ME>` |
| Test Issue ID | `1842` or `<CHANGE_ME>` |
| Tester | `<CHANGE_ME>` |

Confirm safe defaults before enabling processing:

```text
enabled=false
close_by_merge=false
```

Record the reviewed configuration, then enable branch reference processing
only for the staging test window. Do not enable automatic issue transitions.

## Evidence template

Copy this table once for every test case.

| Field | Value |
|---|---|
| Test case | `<CHANGE_ME>` |
| Full 40-character commit SHA | `<40_HEX_CHANGE_ME>` |
| Branches containing commit | `<SANITIZED_BRANCHES_CHANGE_ME>` |
| Import start time | `<YYYY-MM-DD HH:MM:SS TZ>` |
| Import end time | `<YYYY-MM-DD HH:MM:SS TZ>` |
| Import duration | `<CHANGE_ME>` |
| Stored Changeset message | `<SANITIZED_CHANGE_ME>` |
| Associated Issue result | `<CHANGE_ME>` |
| Original Git commit message verification | `<UNCHANGED/CHANGED>` |
| Sanitized audit log | `<CHANGE_ME>` |
| Expected result | `<CHANGE_ME>` |
| Actual result | `<CHANGE_ME>` |
| Pass/Fail | `<PASS/FAIL>` |
| Tester notes | `<CHANGE_ME>` |

Use read-only commands to collect Git evidence:

```bash
git -C <STAGING_WORKTREE_CHANGE_ME> rev-parse HEAD
git -C <STAGING_WORKTREE_CHANGE_ME> branch --all --contains <40_HEX_CHANGE_ME>
git -C <STAGING_WORKTREE_CHANGE_ME> show \
  --no-patch --format='%H%n%s' <40_HEX_CHANGE_ME>
```

The SHA must match `\A[0-9a-fA-F]{40}\z`. Sanitize the worktree path before
adding evidence to the test record.

## Test matrix

Run each row with a fresh commit and record a separate evidence table.

| Test case | Branch or condition | Expected Redmine result |
|---|---|---|
| Positive | `test/redmine-1842-import` | Stored message adds `refs #1842`; Issue 1842 is associated |
| Missing ID | `test/changeset-import` | Message is unchanged; no Issue is associated by this plugin |
| Zero ID | `test/redmine-0-import` | Message is unchanged; no Issue is associated by this plugin |
| Malformed | `test/redmine-abc-import` | Message is unchanged; no Issue is associated by this plugin |
| Ambiguous token | `test/redmine-1842-redmine-2048` | Fail closed; message is unchanged |
| Protected branch | Commit is in `main` before import | Message is unchanged |
| Duplicate reference | Commit message already contains `refs #1842` | Existing reference remains exactly once |
| Multiple branches | One commit is in Issue 1842 and Issue 2048 branches | Fail closed; message is unchanged |
| Invalid SHA | Revision is not 40 hexadecimal characters | Git lookup is not invoked; import continues |
| Git error | Staging-only SCM lookup failure | Original revision is returned; import continues |
| Original object | Successful positive enrichment | Stored Redmine duplicate is enriched; Git commit is unchanged |
| Tags/PR refs | Commit is reachable only through a tag or pull-request ref | Message is unchanged |

For the Git-error case, use an approved, reversible staging fault such as a
temporary read-only SCM availability test. Do not change production access,
delete the repository, or expose repository connection details. Restore access
immediately after collecting evidence.

## Import verification

1. Record the fresh commit SHA and containing branches before import.
2. Record import start and end timestamps in the same timezone.
3. Trigger the standard Redmine repository fetch/import path used by staging.
4. Verify the stored Changeset message and Issue association in Redmine.
5. Re-run the read-only `git show` command and confirm the original Git commit
   subject and SHA are unchanged.
6. Review only sanitized `[redmine_issue_branch]` audit entries. Expected
   fields are `action`, `repository_id`, shortened `revision`, sanitized
   `branch`, `issue_id`, `reason`, and `error_class`.
7. Mark the case Pass or Fail and record deviations without copying sensitive
   logs into the checklist.

## Rollback and cleanup

Disable plugin processing after the test window:

```text
enabled=false
close_by_merge=false
```

First perform read-only checks and stop for review:

```bash
git -C <STAGING_WORKTREE_CHANGE_ME> status --short --branch
git -C <STAGING_WORKTREE_CHANGE_ME> branch --list 'test/*'
git -C <STAGING_WORKTREE_CHANGE_ME> ls-remote --heads origin 'test/*'
```

Deleting remote or local test branches is destructive and can affect later
evidence collection. Run cleanup only after explicit approval and retention
review:

```bash
# DESTRUCTIVE: replace only reviewed branch names; never use a wildcard.
git -C <STAGING_WORKTREE_CHANGE_ME> push origin --delete <EXACT_BRANCH_CHANGE_ME>
git -C <STAGING_WORKTREE_CHANGE_ME> branch -d <EXACT_BRANCH_CHANGE_ME>
```

Do not delete Redmine Issues or Changesets automatically. If staging data must
be removed, use the organization's approved Redmine data-retention procedure
after a database backup and owner approval.

## Acceptance

- Every matrix row has complete evidence and a Pass/Fail result.
- The positive case associates the expected Issue.
- Negative, protected, ambiguous, tag, and pull-request cases remain
  unchanged.
- Git and plugin errors do not stop repository synchronization.
- The original Git SHA and commit message remain unchanged in every case.
- `enabled=false` and `close_by_merge=false` are restored after testing.
- No secrets, repository URLs, customer data, or unsafe logs are included in
  the evidence.

## Common pitfalls and troubleshooting

| Symptom | Read-only check | Likely action |
|---|---|---|
| No new Changeset appears | Confirm the SHA is new and inspect the repository import timestamp | Create a fresh commit; do not reuse a previously imported revision |
| Positive case is skipped | Run `git branch --all --contains <40_HEX_CHANGE_ME>` | Ensure the commit is not reachable from a configured protected branch before import |
| Message is enriched but no Issue is associated | Review Redmine reference keywords and project/cross-project repository policy | Align `reference_keyword` with Redmine and correct staging policy; do not bypass native authorization |
| Expected branch is absent | Inspect sanitized local and remote-tracking refs | Verify the staging fetch refspec includes the branch without exposing the remote URL |
| Import continues after a Git error | Review the sanitized `action=error` entry and `error_class` | This is expected fail-open behavior; restore staging SCM availability and retry with a fresh commit |
| Existing Changeset does not change | Confirm the SHA already exists in Redmine | Use a fresh commit because `save_revision` may not run twice |
| Local test command cannot load Redmine | Confirm the plugin path is `<redmine-root>/plugins/redmine_issue_branch` | Run the suite from the Redmine application root with its supported Ruby and bundle |
