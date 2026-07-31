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

## Test

From the Redmine application root:

```bash
RAILS_ENV=test bundle exec rake \
  redmine:plugins:test:units \
  NAME=redmine_issue_branch
```

CI validates the plugin against Redmine's `6.1-stable` branch with Ruby 3.2,
3.3, and 3.4 using PostgreSQL 14.

## Security defaults

- Plugin processing is disabled by default.
- Automatic issue closing is disabled and unavailable in v0.2.0.
- Only the explicit `redmine-<positive integer>` token is accepted.
- Ambiguous references fail closed.
- Full 40-character hexadecimal commit IDs are required before invoking Git.
- Shared history reachable from protected base branches is not enriched.
- The plugin stores no repository credentials or access tokens.
- Parser failures must not interrupt Redmine repository imports.

## Roadmap

- v0.1.0: Redmine 6.1 compatibility PoC and reference engine
- v0.2.0: changeset import integration and structured audit logging
- v0.3.0: guarded merge-to-close policy
- v1.0.0: production-ready Redmine 6.1 release
- v2.0.0: optional GitHub/GitLab branch creation and PR/MR tracking

## Acknowledgements

The project is inspired by the MIT-licensed
[`redmine_git_branch_hook`](https://github.com/mikoto20000/redmine_git_branch_hook)
concept. This implementation is written for modern Redmine and does not claim
official compatibility or ownership of the original plugin.

## License

[MIT](LICENSE)
