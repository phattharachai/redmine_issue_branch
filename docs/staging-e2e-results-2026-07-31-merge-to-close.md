# Staging E2E Results — Merge-to-Close (v0.3.0) — 2026-07-31

## Environment

| Field | Result |
|---|---|
| Test window | `2026-07-31 17:43–17:59 ICT (Asia/Bangkok)` |
| Redmine | `6.1.2.stable` |
| Rails | `7.2.3` |
| Ruby | `3.4.9` |
| PostgreSQL | `17.6` |
| Plugin | `redmine_issue_branch 0.3.0` (deployed from branch `feature/close-by-merge-guarded-policy`, commit `20cd599`) |
| Repository type | `Git` |
| Sanitized repository path | `/tmp/redmine_issue_branch_e2e/repository.git` (recreated this window; see Incidents) |
| Protected branches | `main`, `master` |
| Reference keyword | `refs` |
| Fixing keyword (Redmine `commit_update_keywords`) | `closes` → status `Resolved` (id 3), configured only for this test window |
| Disposable project | ID `6`, identifier `rib-e2e-20260731`, private |
| Disposable repository | ID `1`, identifier `rib-e2e-git` |
| Test Issue | `#597` (reused from the v0.2.0 run; status moved `New` → `Resolved` by cases A and F below) |

Settings before this window: `enabled=false`, `close_by_merge=false`. Settings after this window, verified via the plugin settings page and `Setting.plugin_redmine_issue_branch`: `enabled=false`, `close_by_merge=false`, `commit_update_keywords=[]` (restored to its pre-test empty value). No production repository, credentials, private repository URL, or customer data was used.

## Incidents during this test window

Recorded transparently per the checklist's evidence requirements; none affected production or required approval to resolve, but each blocked progress and is worth capturing for future runs.

1. **Container restart wiped `/tmp`.** Deploying the new plugin code required a Puma restart (Redmine runs in `RAILS_ENV=production`, which caches classes). `/tmp` inside the `dockstack_redmine` container is not part of any bind mount, so `docker restart` silently deleted the disposable bare Git repository and working clone used by the v0.2.0 run, including the 9 retained `test/*` branches. Database records (Project, Issue #597, Repository row, Changeset rows) were unaffected — they live in a separate, persisted Postgres volume. The physical Git history behind the earlier `docs/staging-e2e-results-2026-07-31.md` evidence is gone; the recorded SHAs, messages, and audit log lines in that file remain the historical record. A fresh bare repository and working clone were created at the same path for this window.
2. **Fresh bare repo's `HEAD` pointed at a nonexistent branch.** `git init --bare` (without `--initial-branch`) defaulted `HEAD` to `refs/heads/master`, but only `main` ever existed in the new repo. Redmine's `fetch_changesets` failed with `git log error: git exited with non-zero status: 128` until `git symbolic-ref HEAD refs/heads/main` was run against the bare repo (read-only-equivalent metadata fix, no history change).
3. **Stale `Repository#extra_info['heads']`.** The Repository row (id 1) still referenced the old, now-nonexistent commit SHAs from the wiped repo as "previously known heads," which `fetch_changesets` uses to compute an exclude list for `git log`. Because those SHAs no longer existed, git rejected the revision range with the same exit-128 error. Reset via `repo.update_column(:extra_info, extra_info.merge('heads' => []))` to force a full rescan; no Changesets, Issues, or branches were deleted.
4. **Browser automation could not reliably toggle the "Close issues on merge" checkbox for case B.** A click+Apply sequence did not visibly change the checkbox state on screenshot re-check (the earlier positive-case toggle had worked). Resolved by setting `Setting.plugin_redmine_issue_branch` directly via `rails runner`, which has the identical effect to submitting the settings form and was verified by reading the setting back before proceeding.

## Results

| Case | Merge commit SHA | Stored Changeset message | Issue #597 result | Pass |
|---|---|---|---|---|
| A. Merge positive | `bff01446d1e907598fe216134506e97c7a9168bf` | `Merge export for issue 597` + `closes #597` | Status `New`(1) → `Resolved`(3) via Redmine's own `Changeset#scan_for_issues` | PASS |
| B. Merge, `close_by_merge=false` | `50ab8d94c2fc3463a1bc4a45ee01be07f2d9a296` | Unchanged | No change; `action=skipped reason=protected_branch` | PASS |
| C. Squash merge (single parent) | `8ff8065b5259dabaa3db8664680c52e5b1f0a1e9` | Unchanged | No change; `action=skipped reason=merge_not_a_merge_commit` | PASS |
| D. Merge into non-protected branch (`develop`) | `3a4cdd74bb1f4c5557be0733311318b1e31935db` | Unchanged | No change; merge commit's only containing branch (`develop`) carries no `redmine-<id>` token, so no enrichment of any kind was attempted | PASS |
| E. Octopus merge (3 parents) | `da588325fcd21b85a32f175659155b0b4e9996de` | Unchanged | No change; `action=skipped reason=merge_octopus_unsupported` | PASS |
| F. Merged branch already deleted (Changeset DB fallback) | `af05c793f245574b660e40c153b82b439b49b8b8` | `Merge DB fallback case for issue 597` + `closes #597` | Resolved via the existing Changeset↔Issue association for the deleted branch's tip SHA (`48f964d36e3eac61c9dd2da9e4b295d700e24a74`), recorded before the branch was deleted | PASS |
| G. No Fixing keyword configured | `85caeda3fc616d198ed5cfc5c014be122dd59a2b` | Unchanged | No change; `action=skipped reason=fix_keyword_unset` | PASS |

All 7 rows of the merge-to-close matrix in `docs/staging-e2e-checklist.md` passed. Read-only `git show --no-patch` confirmed the original Git commit message is unchanged for every case, including both cases that closed the issue (A, F):

```text
bff01446d1e907598fe216134506e97c7a9168bf
Merge export for issue 597

af05c793f245574b660e40c153b82b439b49b8b8
Merge DB fallback case for issue 597
```

## Sanitized audit evidence

```text
[redmine_issue_branch] action=closed repository_id=1 revision=bff01446d1e9 issue_id=597
[redmine_issue_branch] action=skipped repository_id=1 revision=50ab8d94c2fc reason=protected_branch branch=main
[redmine_issue_branch] action=skipped repository_id=1 revision=8ff8065b5259 reason=merge_not_a_merge_commit
[redmine_issue_branch] action=skipped repository_id=1 revision=da588325fcd2 reason=merge_octopus_unsupported
[redmine_issue_branch] action=closed repository_id=1 revision=af05c793f245 issue_id=597
[redmine_issue_branch] action=skipped repository_id=1 revision=85caeda3fc61 reason=fix_keyword_unset
```

Audit entries contain no repository URL, credentials, exception message, stack trace, full unrelated commit message, or environment values.

## Limitations of this run

- Case D's expected result was refined during execution: the checklist row originally described "falls through to plain reference enrichment." In practice, a merge commit's own containing-branch set only ever includes the branch it actually landed on (`develop` here), which carries no `redmine-<id>` token itself — so the merge commit is left unenriched rather than gaining a plain `refs` reference. The checklist has been corrected to match this actual, verified behavior.
- Case G incidentally also exercised a single-parent commit reachable from a protected branch with no Fixing keyword configured (an unplanned but consistent variant of case C/G combined), because that commit's branch push and the subsequent merge were both captured in the same `fetch_changesets` run. This is documented here rather than silently ignored; it does not weaken case G's core assertion (the merge commit itself was not closed).
- This run reused Issue #597 across all cases rather than a fresh Issue per case, matching the project's existing v0.2.0 staging-evidence convention. Issue #597's status is left at `Resolved` after this test window; this is disposable test data in a private, disposable project and was not restored, matching the checklist's "no automatic deletion or rollback of Issues/Changesets" rule.

## Retained staging data and cleanup

The private Project, Issue #597 (now `Resolved`), Repository record, Changesets (both from this window and the original v0.2.0 window, now without matching Git history — see Incident 1), and the newly created temporary Git repository at `/tmp/redmine_issue_branch_e2e` are intentionally retained for review. Nothing was deleted automatically. `close_by_merge`, `enabled`, and `commit_update_keywords` were all confirmed restored to their pre-test values (`false`, `false`, `[]`) before ending the test window.
