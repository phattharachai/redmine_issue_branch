# Redmine Issue Branch

`redmine_issue_branch` is a Redmine 6.1 plugin for safely resolving Redmine
issue IDs from Git branch references and enriching imported changeset messages.

## Compatibility

- Redmine 6.1.x
- Ruby 3.2, 3.3, or 3.4
- Rails 7.2 (provided by Redmine 6.1)
- PostgreSQL 14 or later
- Git repositories managed by Redmine

Version 0.2.0 integrates with Redmine's Git changeset import lifecycle. Before
Redmine persists a new changeset, the plugin resolves the branches containing
the commit and appends a configured reference such as `refs #1842` to the
message stored by Redmine. The Git commit itself is never modified.

Version 0.3.0 adds an opt-in, guarded merge-to-close policy: a genuine
two-parent merge commit landing on a protected base branch can append one of
Redmine's own configured "Fixing keywords" (**Administration → Settings →
Repositories**) instead of a plain reference, letting Redmine's native
`Changeset#scan_for_issues` close the issue. See "Merge-to-close behavior"
below.

## Supported branch format

Use an explicit `redmine-<issue-id>` token:

```text
feature/redmine-1842-add-candidate-export
bugfix/redmine-1842-fix-export
hotfix/redmine-1842-restore-export
```

The parser normalizes local and remote refs such as:

```text
refs/heads/feature/redmine-1842-add-export
refs/remotes/origin/feature/redmine-1842-add-export
origin/feature/redmine-1842-add-export
```

Tags, pull-request refs, missing IDs, zero IDs, and branches containing multiple
Redmine issue IDs are rejected. This fail-closed behavior reduces accidental
cross-linking.

## Changeset import behavior

The plugin uses two narrow Redmine 6.1 integration points:

- `Redmine::Scm::Adapters::GitAdapter` gains a read-only
  `branches_containing(scmid)` query.
- `Repository::Git#save_revision` enriches a duplicate of the revision before
  Redmine creates the `Changeset`.

For each newly imported Git revision:

1. Query local and remote-tracking branches containing the full 40-character
   commit SHA.
2. Normalize each branch and extract explicit `redmine-<issue-id>` tokens.
3. Skip the revision if it is already contained in `main`, `master`, or another
   configured protected base branch.
4. Skip the revision if different containing branches resolve to different
   Redmine issue IDs.
5. Append the reference keyword and Issue ID to the Redmine changeset message.
6. Let Redmine's native `Changeset#scan_for_issues` enforce project and
   cross-project reference policy.

Parser or SCM lookup errors fail open: the original revision is passed to
Redmine and repository synchronization continues. Structured logs contain only
the repository ID, shortened revision, action, sanitized branch, Issue ID, and
error class.

## Merge-to-close behavior

When `close_by_merge` is enabled, a revision landing on a protected base
branch is not simply skipped; it is checked for a genuine merge:

1. The revision must have exactly two parents (a real merge commit, matching
   how `git merge` and GitHub/GitLab "Merge pull request" both create merge
   commits). A single-parent commit or an octopus merge (3+ parents) is never
   eligible.
2. The incoming (second) parent's Issue is resolved first from Redmine's own
   already-recorded Changeset-to-Issue association for that parent SHA (set
   when the feature-branch commit was originally imported), then, if no
   association is recorded, from any branch whose current tip is exactly
   that parent SHA.
3. If exactly one Issue is resolved, the plugin appends the first configured
   "Fixing keyword" from Redmine's own `commit_update_keywords` setting
   (**Administration → Settings → Repositories**) to the changeset message
   instead of the plain reference keyword. Redmine's unmodified
   `Changeset#scan_for_issues` then performs the actual status transition,
   using whichever status/tracker rule it has configured for that keyword.
4. Any ambiguity (zero or multiple resolved Issues, an octopus merge, or no
   Fixing keyword configured) fails closed: the revision is left unenriched,
   exactly like the existing protected-branch skip.

The plugin never mutates an Issue directly. The only write path is Redmine's
own native commit-fix-keyword mechanism, unchanged.

### Known limitations

- Fast-forward merges are not supported: no new commit is created, so there
  is no `save_revision` event to hook at merge time.
- Squash and rebase merges are not supported: the resulting commit has no
  structural (parent) link back to the original feature branch.
- If the merged branch was deleted **and** the original feature commit was
  never previously imported with a resolvable Issue association, the merge
  cannot be resolved and is left unenriched.

## Install for compatibility testing

```bash
cd /usr/src/redmine/plugins
git clone https://github.com/phattharachai/redmine_issue_branch.git
cd /usr/src/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

This version has no database migrations. Restart Redmine after installation,
then review the plugin under **Administration → Plugins → Configure**.

Keep processing disabled until the integration is validated with a staging
repository and the protected base branch list matches the repository workflow.

## Configure

Under **Administration → Plugins → Redmine Issue Branch → Configure**:

- Enable branch reference processing only after staging validation.
- Set the reference keyword to one of Redmine's configured repository
  reference keywords, normally `refs`.
- List protected base branches one per line, for example:

```text
main
master
develop
```

Commits already reachable from a protected base branch are deliberately not
linked from feature branch names. This prevents a full repository import from
linking shared base history to the current feature issue.

- Enable branch reference processing (above) and staging validation before
  enabling **Close issues on merge**.
- Configure at least one row of Redmine's own "Fixing keywords" (with a
  status) under **Administration → Settings → Repositories** —
  `commit_update_keywords`. The plugin never adds its own separate
  close-keyword setting; it only reuses Redmine's configuration so it can
  never trigger something Redmine's native commit-keyword feature wouldn't
  already recognize.
- See [Merge-to-close behavior](#merge-to-close-behavior) for exactly which
  merges qualify.

## Automated tests

From the Redmine application root:

```bash
RAILS_ENV=test bundle exec rake \
  redmine:plugins:test:units \
  NAME=redmine_issue_branch
```

The unit suite includes an isolated staging-style integration harness. It
creates temporary working and bare Git repositories, exercises real
`branches_containing`/`parents_of`/`branch_heads_at` lookups, and removes the
repositories after each test. It covers positive, negative, ambiguous,
protected-branch, duplicate, multiple-branch, invalid-SHA, Git-error,
original-object, tag, and pull-request reference behavior, plus merge-to-close
scenarios (genuine merge commit, squash-merge left unsupported, octopus
merge, and merge into a non-protected branch). It does not require a
plugin-level Gemfile, a production repository, or repository credentials.

CI validates the plugin against Redmine's `6.1-stable` branch with Ruby 3.2,
3.3, and 3.4 using PostgreSQL 14.

## Manual staging E2E verification

Use [docs/staging-e2e-checklist.md](docs/staging-e2e-checklist.md) for the
Redmine 6.1 staging checks that automated bare-Git tests cannot prove:
Changeset persistence, native Issue association, staging configuration, import
timing, and sanitized operational logs.

Every staging test case must use a new commit because Redmine may not run
`save_revision` again for an existing Changeset. For the positive case, do not
merge or otherwise make the commit reachable from a configured protected
branch before the import. Use only a disposable staging repository. Keep
`close_by_merge` disabled unless the test window is specifically validating
merge-to-close behavior, and restore it to disabled afterward.

The checklist separates read-only evidence collection from cleanup. It does
not automatically delete Issues, Changesets, branches, or repositories.

## Security defaults

- Plugin processing is disabled by default.
- Automatic issue closing (`close_by_merge`) is disabled by default. When
  enabled, it only ever appends Redmine's own configured fix keyword to a
  genuine two-parent merge commit landing on a protected base branch; the
  plugin never mutates an Issue directly and never invents a default close
  keyword.
- Only the explicit `redmine-<positive integer>` token is accepted.
- Ambiguous references fail closed.
- Full 40-character hexadecimal commit IDs are required before invoking Git.
- Shared history reachable from protected base branches is not enriched.
- The plugin stores no repository credentials or access tokens.
- Parser failures must not interrupt Redmine repository imports.

## Roadmap

- v0.1.0: Redmine 6.1 compatibility PoC and reference engine
- v0.2.0: changeset import integration and structured audit logging
- v0.3.0: guarded merge-to-close policy (two-parent merge commits only;
  fast-forward, squash, and rebase merges are out of scope)
- v1.0.0: production-ready Redmine 6.1 release
- v2.0.0: optional GitHub/GitLab branch creation and PR/MR tracking

## Acknowledgements

The project is inspired by the MIT-licensed
[`redmine_git_branch_hook`](https://github.com/mikoto20000/redmine_git_branch_hook)
concept. This implementation is written for modern Redmine and does not claim
official compatibility or ownership of the original plugin.

## License

[MIT](LICENSE)
