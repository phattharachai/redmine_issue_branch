# Staging E2E Results — 2026-07-31

## Environment

| Field | Result |
|---|---|
| Test window | `2026-07-31 15:23–15:27 ICT (Asia/Bangkok)` |
| Redmine | `6.1.2.stable` |
| Rails | `7.2.3` |
| Ruby | `3.4.9` |
| PostgreSQL | `17.6` |
| Plugin | `redmine_issue_branch 0.2.0` |
| Plugin source | Installed package has no Git metadata; runtime file SHA-256 values match branch commit `b76c1852ad019d40c1ab40d7a48766fc58db3dfc` |
| Repository type | `Git` |
| Sanitized repository path | `/tmp/redmine_issue_branch_e2e/repository.git` |
| Protected branches | `main`, `master` |
| Reference keyword | `refs` |
| Disposable project | ID `6`, identifier `rib-e2e-20260731`, private |
| Disposable repository | ID `1`, identifier `rib-e2e-git` |
| Test Issue | `#597` |

The staging installation initially had processing enabled. After the test
window, settings were restored and verified as:

```text
enabled=false
close_by_merge=false
```

No production repository, credentials, private repository URL, or customer
data was used.

## Results

| Case | Full commit SHA | Containing branches | Stored Changeset result | Issue result | Pass |
|---|---|---|---|---|---|
| Positive | `02d66c42820f24bfbf589c5882569fc6d3f947a0` | `test/redmine-597-import` | `E2E positive import` plus `refs #597` | Associated with `#597` | PASS |
| Missing ID | `5f077867e9d7a928921a912daecfc376990473a5` | `test/changeset-import` | Unchanged | No association | PASS |
| Zero ID | `6995870bc2d31cce6bdbc1536de13e0fa01715e0` | `test/redmine-0-import` | Unchanged | No association | PASS |
| Malformed ID | `d7d08c8f3c3f81408c980a59ff3b2b2772560b6c` | `test/redmine-abc-import` | Unchanged | No association | PASS |
| Ambiguous token | `6a89600043482872154fa180dd8e1a5d179a99a1` | `test/redmine-597-redmine-1597` | Unchanged | No association | PASS |
| Protected branch | `07619abbc1803b325adda40644ff519b7fa16e9f` | `main`, `test/redmine-597-protected` | Unchanged | No association | PASS |
| Duplicate reference | `efa04df4ed1c930225e70badf673d6e6f666d1b1` | `test/redmine-597-duplicate` | Existing `refs #597` occurs once | Associated with `#597` | PASS |
| Multiple branches | `0d0647897d350aa8ec350f9b4f3150dbce0c1d46` | `test/redmine-597-multiple`, `test/redmine-1597-multiple` | Unchanged | No association | PASS |
| Invalid SHA | `HEAD` (intentionally invalid) | Not applicable | Git invocation count was zero | Not applicable | PASS |
| Git error | Synthetic staging-runtime adapter failure | Not applicable | Original revision object returned | Import service remained available | PASS |
| Original object | Reused positive-case full SHA in service verification | `test/redmine-597-import` | Enriched duplicate returned | Original object and Git message unchanged | PASS |
| Tags/PR refs | `18ff6b4bc0595fd84cbe757c732b57c42862f333` | No branch; tag and `refs/pull/597/head` only | No Changeset imported and no branch match | No association | PASS |

All Git-backed cases used a fresh commit. The positive commit was not reachable
from a protected branch before import. Read-only `git show` verification
confirmed every original Git commit message was unchanged.

## Import timing

| Scope | Start (UTC) | End (UTC) | Duration |
|---|---|---|---|
| Positive and initial base import | `2026-07-31T08:23:39.384779Z` | `2026-07-31T08:23:39.746999Z` | `362.22 ms` |
| Missing-ID import | `2026-07-31T08:25:45.699463Z` | `2026-07-31T08:25:45.826029Z` | `126.57 ms` |
| Pending zero/malformed/ambiguous/duplicate/multiple/protected batch | `2026-07-31T08:26:24.175370Z` | `2026-07-31T08:26:24.429279Z` | `253.91 ms` |
| Tag/PR-only lookup | `2026-07-31T08:25:46.779876Z` | `2026-07-31T08:25:46.787813Z` | `7.94 ms` |

The pending cases were imported in one fresh Rails process after the temporary
orchestrator reused a memoized Git adapter and therefore did not discover refs
created later in that same process. No Changeset existed for those commits
before the fresh-process import. This was a staging orchestration issue, not a
plugin failure.

## Sanitized audit evidence

```text
[redmine_issue_branch] action=enriched repository_id=1 revision=02d66c42820f issue_id=597 branch=test/redmine-597-import
[redmine_issue_branch] action=skipped repository_id=1 revision=0d0647897d35 reason=ambiguous_issue_ids
[redmine_issue_branch] action=skipped repository_id=1 revision=07619abbc180 reason=protected_branch branch=main
[redmine_issue_branch] action=error repository_id=1 revision=aaaaaaaaaaaa error_class=GitCommandFailed
```

The audit entries contain no repository URL, credentials, exception message,
stack trace, full commit message, or environment values.

## Limitations

- The invalid-SHA case was exercised directly against the installed adapter
  patch because Redmine does not naturally produce a non-SHA Git revision
  during import.
- The Git-error case used the installed enrichment service with a synthetic
  adapter failure. The live repository path was not disrupted because that
  would affect staging availability.
- Tag and pull-request-only refs are not branch heads, so Redmine did not
  create a Changeset for that commit. The installed adapter returned no
  containing branches, and the automated bare-Git harness provides additional
  coverage for this behavior.
- The installed plugin package does not include `.git`; provenance was checked
  by comparing SHA-256 values of all runtime Ruby files with the reviewed
  branch.

## Retained staging data and cleanup

The private Project, Issue, Repository record, Changesets, branches, tags, and
temporary Git repository were intentionally retained for review. Nothing was
deleted automatically.

Read-only checks before any cleanup:

```bash
docker exec dockstack_redmine \
  git --git-dir=/tmp/redmine_issue_branch_e2e/repository.git \
  branch --all

docker exec dockstack_redmine \
  bundle exec rails runner \
  'puts Project.exists?(identifier: "rib-e2e-20260731")'
```

Removing the retained Redmine records or Git path is destructive and requires
a separate approval after evidence retention review.
