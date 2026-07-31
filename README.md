# Redmine Issue Branch

`redmine_issue_branch` is a Redmine 6.1 plugin for safely resolving Redmine
issue IDs from Git branch references and enriching imported changeset messages.

## Compatibility

- Redmine 6.1.x
- Ruby 3.2, 3.3, or 3.4
- Rails 7.2 (provided by Redmine 6.1)
- PostgreSQL 14 or later
- Git repositories managed by Redmine

The v0.1.0 compatibility PoC does not create remote branches and does not yet
patch Redmine's changeset import lifecycle. It establishes the plugin loading,
settings, branch parser, message enricher, and automated test foundation needed
to select the safest Redmine 6.1 integration point.

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

## Install for compatibility testing

```bash
cd /usr/src/redmine/plugins
git clone https://github.com/phattharachai/redmine_issue_branch.git
cd /usr/src/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

This version has no database migrations. Restart Redmine after installation,
then review the plugin under **Administration → Plugins → Configure**.

Keep processing disabled until the Redmine changeset integration is implemented
and validated in staging.

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
- Automatic issue closing is disabled and unavailable in v0.1.0.
- Only the explicit `redmine-<positive integer>` token is accepted.
- Ambiguous references fail closed.
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
