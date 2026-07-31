# AGENTS.md

## Scope

These instructions apply to the entire `redmine_issue_branch` repository.
If a nested directory later contains its own `AGENTS.md`, the nearest file
takes precedence for files in that directory.

## Project contract

`redmine_issue_branch` is a Redmine 6.1 plugin that resolves an Issue ID from
Git branch names and enriches the changeset message stored by Redmine. It must
never modify the Git commit, branch, or repository history.

Supported runtime:

- Redmine 6.1.x
- Rails 7.2 as supplied by Redmine
- Ruby 3.2, 3.3, and 3.4
- PostgreSQL 14 or later
- Git repositories managed by Redmine

Treat `README.md` as the user-facing behavior contract. Keep it aligned with
any functional, compatibility, configuration, or security change.

## Repository map

- `init.rb`: plugin registration, version, compatibility, and safe defaults.
- `lib/redmine_issue_branch.rb`: bootstrapping, settings access, and
  idempotent patch registration.
- `lib/redmine_issue_branch/patches/`: narrow Redmine/SCM integration points.
- `app/services/redmine_issue_branch/`: parsing and changeset enrichment
  business logic.
- `app/views/settings/`: Redmine plugin configuration UI.
- `config/locales/`: English and Thai translations.
- `test/unit/`: ActiveSupport/Minitest unit and bare-Git integration tests.
- `.github/workflows/test.yml`: Redmine 6.1 test matrix.

## Required workflow

1. Read `README.md`, `init.rb`, and the directly affected implementation and
   tests before editing.
2. Keep changes narrowly scoped. Do not refactor unrelated code.
3. Add or update tests with every behavior change or bug fix.
4. Run the available validation commands.
5. Review the complete diff for credentials, unsafe logging, accidental API
   expansion, and unrelated files.
6. Open a Draft PR; do not commit directly to `main`.

Use conventional branch names:

```text
feature/redmine-<issue-id>-short-description
fix/redmine-<issue-id>-short-description
docs/short-description
test/short-description
refactor/short-description
chore/short-description
hotfix/redmine-<issue-id>-short-description
```

If no Redmine Issue exists, omit the `redmine-<issue-id>` token. Use concise,
imperative commit messages and keep one logical change per commit.

## Development setup

The plugin must be checked out at this exact path inside a Redmine source tree:

```text
<redmine-root>/plugins/redmine_issue_branch
```

From `<redmine-root>`, install Redmine dependencies using the Ruby version
under test. Do not add a plugin-level dependency or Gemfile unless the change
requires it and the PR explains why Redmine's existing dependency set is
insufficient.

This plugin currently has no database migrations. Do not run or add a
production migration for a change that does not require persistent data.

## Validation

Run syntax checks for every changed Ruby file:

```bash
git diff --name-only --diff-filter=ACMR \
  | awk '/\.rb$/ { print }' \
  | xargs -r -n1 ruby -c
```

Run plugin unit tests from the Redmine application root:

```bash
RAILS_ENV=test bundle exec rake \
  redmine:plugins:test:units \
  NAME=redmine_issue_branch
```

Before merging, GitHub Actions must pass the full Redmine 6.1 matrix:

- Ruby 3.2
- Ruby 3.3
- Ruby 3.4
- PostgreSQL 14

Do not claim a runtime is supported unless it is covered by CI. If local
validation cannot run because Redmine, Ruby, PostgreSQL, or Git is unavailable,
state exactly what was not run and rely on CI before merging.

## Coding conventions

- Use Ruby with `# frozen_string_literal: true`.
- Follow the existing two-space indentation and ActiveSupport test style.
- Keep public behavior in small service objects under
  `RedmineIssueBranch`.
- Prefer keyword arguments at service boundaries.
- Keep Redmine core patches minimal and delegate logic to testable services.
- Apply patches with `Module#prepend`; do not use `alias_method_chain`.
- Patch registration must remain idempotent and safe during Rails development
  reloads.
- Avoid global monkey patches and changes outside the plugin namespace.
- Preserve method visibility when patching Redmine internals.
- Use English for code, identifiers, logs, comments, and technical
  documentation.
- Update both `config/locales/en.yml` and `config/locales/th.yml` for
  user-facing settings.

## Behavioral invariants

Preserve these rules unless a reviewed design explicitly replaces them:

- Plugin processing is disabled by default.
- `close_by_merge` is disabled by default. When enabled, it only appends a
  close keyword for a revision with exactly two parents (a genuine merge
  commit) landing on a configured protected base branch, whose incoming
  parent resolves unambiguously to exactly one Issue. Any other shape
  (single-parent commit, octopus merge, zero or multiple resolved Issues,
  or no configured Redmine fix keyword/status) fails closed, identically to
  the existing protected-branch skip.
- `close_by_merge` must never call `Issue#update`/`update_column` or any
  other direct Issue mutation. The only write path is Redmine's own
  untouched `Changeset#scan_for_issues`, using Redmine's own configured
  `Setting.commit_fix_keywords`/`commit_fix_status_id`. The plugin must never
  add a separate plugin-level close-keyword setting that could drift from
  Redmine's own configured fix keywords.
- Only an explicit `redmine-<positive-integer>` branch token is valid.
- Tags, pull-request refs, zero IDs, malformed IDs, and missing IDs do not
  match.
- A branch containing multiple Issue IDs is ambiguous and must fail closed.
- Multiple containing branches resolving to different Issue IDs must fail
  closed.
- Commits reachable from a configured protected base branch must not be
  enriched.
- Git commands accept only a full 40-character hexadecimal commit SHA.
- SCM lookup, parsing, or enrichment errors must fail open by returning the
  original revision so repository synchronization continues.
- Never mutate the original revision object; enrich a duplicate.
- Never duplicate an existing Redmine Issue reference.
- Let Redmine's native `Changeset#scan_for_issues` enforce project and
  cross-project policies.

When changing branch parsing or protected-branch behavior, include positive,
negative, ambiguity, and normalization tests. When changing SCM integration,
include a test using a temporary bare Git repository.

## Security and privacy

- Never commit secrets, tokens, credentials, private repository URLs,
  production configuration, or customer data.
- Do not shell-interpolate a revision, branch, path, or setting. Pass Git
  arguments as an array through Redmine's adapter.
- Validate untrusted inputs before invoking Git.
- Keep logging structured and sanitized.
- Logs may include only non-sensitive operational fields such as action,
  repository ID, shortened revision, sanitized branch, Issue ID, reason, and
  exception class.
- Never log repository credentials, repository URLs, full commit messages,
  access tokens, environment variables, stack traces, or exception messages
  that may contain sensitive paths or command output.
- Keep GitHub Actions permissions least-privileged. The test workflow requires
  only `contents: read`.
- Do not enable processing or automatic issue transitions in production as
  part of an installation, test, or migration.

## Versioning and documentation

The version exists in both:

- `init.rb`
- `RedmineIssueBranch::VERSION` in `lib/redmine_issue_branch.rb`

If a release changes the version, update both locations in the same commit and
update the compatibility/roadmap text in `README.md`.

Use semantic versioning:

- patch: backward-compatible fixes and documentation corrections
- minor: backward-compatible behavior or configuration additions
- major: breaking behavior, configuration, data, or compatibility changes

Retain the MIT license and acknowledgements when reusing ideas or code derived
from the original MIT-licensed project.

## Pull request checklist

A PR is ready for review only when:

- The diff is limited to the requested behavior.
- New and changed behavior has tests.
- Existing safe defaults and failure modes are preserved.
- Ruby syntax validation passes.
- The Redmine plugin test suite passes.
- The Ruby 3.2-3.4 CI matrix passes.
- English and Thai locale changes are synchronized.
- `README.md` documents user-visible changes.
- Version constants match when a version bump is included.
- No credentials or sensitive data appear in the diff or logs.
- Deployment, migration, rollback, and compatibility impact are stated when
  applicable.

