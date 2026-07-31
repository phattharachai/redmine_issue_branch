# frozen_string_literal: true

require_relative '../test_helper'

class MergeCommitIssueResolverTest < ActiveSupport::TestCase
  Revision = Struct.new(:scmid, :message, keyword_init: true)
  Repository = Struct.new(:id, :scm, :changesets, keyword_init: true)
  Issue = Struct.new(:id, keyword_init: true)
  Changeset = Struct.new(:revision, :issues, keyword_init: true)

  class FakeAdapter
    def initialize(parents: [], branch_heads: {})
      @parents = parents
      @branch_heads = branch_heads
    end

    def parents_of(_scmid)
      @parents
    end

    def branch_heads_at(scmid)
      @branch_heads.fetch(scmid, [])
    end
  end

  class FakeChangesets
    def initialize(records = {})
      @records = records
    end

    def find_by(revision:)
      @records[revision]
    end
  end

  BASE_SHA = 'a' * 40
  FEATURE_SHA = 'b' * 40

  test 'resolves the issue from an existing Changeset association on the incoming parent' do
    changeset = Changeset.new(revision: FEATURE_SHA, issues: [Issue.new(id: 1842)])
    resolver = build_resolver(
      parents: [BASE_SHA, FEATURE_SHA],
      changesets: {FEATURE_SHA => changeset}
    )

    result = resolver.call

    assert result.matched?
    assert_equal 1842, result.issue_id
    assert_equal 'changeset_lookup', result.reason
  end

  test 'falls back to a branch whose tip matches the incoming parent when no Changeset exists' do
    resolver = build_resolver(
      parents: [BASE_SHA, FEATURE_SHA],
      branch_heads: {FEATURE_SHA => ['feature/redmine-1842-add-export']}
    )

    result = resolver.call

    assert result.matched?
    assert_equal 1842, result.issue_id
    assert_equal 'branch_head_lookup', result.reason
  end

  test 'falls back to branch heads when the Changeset has no linked issue' do
    changeset = Changeset.new(revision: FEATURE_SHA, issues: [])
    resolver = build_resolver(
      parents: [BASE_SHA, FEATURE_SHA],
      changesets: {FEATURE_SHA => changeset},
      branch_heads: {FEATURE_SHA => ['feature/redmine-1842-add-export']}
    )

    result = resolver.call

    assert result.matched?
    assert_equal 1842, result.issue_id
    assert_equal 'branch_head_lookup', result.reason
  end

  test 'fails closed when the incoming parent Changeset links multiple issues' do
    changeset = Changeset.new(
      revision: FEATURE_SHA,
      issues: [Issue.new(id: 1842), Issue.new(id: 2048)]
    )
    resolver = build_resolver(
      parents: [BASE_SHA, FEATURE_SHA],
      changesets: {FEATURE_SHA => changeset}
    )

    result = resolver.call

    assert_equal :ambiguous, result.status
    assert_equal 'changeset_multiple_issues', result.reason
  end

  test 'fails closed when no Changeset or branch head resolves an issue' do
    resolver = build_resolver(parents: [BASE_SHA, FEATURE_SHA])

    result = resolver.call

    assert_equal :no_match, result.status
    assert_equal 'no_source_branch_issue', result.reason
  end

  test 'fails closed when branch heads resolve to more than one issue' do
    resolver = build_resolver(
      parents: [BASE_SHA, FEATURE_SHA],
      branch_heads: {
        FEATURE_SHA => ['feature/redmine-1842-x', 'bugfix/redmine-2048-y']
      }
    )

    result = resolver.call

    assert_equal :ambiguous, result.status
    assert_equal 'ambiguous_issue_ids', result.reason
  end

  test 'does not resolve a single-parent commit' do
    resolver = build_resolver(parents: [BASE_SHA])

    result = resolver.call

    assert_equal :no_match, result.status
    assert_equal 'not_a_merge_commit', result.reason
  end

  test 'fails closed for an octopus merge' do
    resolver = build_resolver(parents: [BASE_SHA, FEATURE_SHA, 'c' * 40])

    result = resolver.call

    assert_equal :ambiguous, result.status
    assert_equal 'octopus_unsupported', result.reason
  end

  private

  def build_resolver(parents:, branch_heads: {}, changesets: {})
    revision = Revision.new(scmid: 'd' * 40, message: 'Merge export')
    adapter = FakeAdapter.new(parents: parents, branch_heads: branch_heads)
    repository = Repository.new(id: 9, scm: adapter, changesets: FakeChangesets.new(changesets))

    RedmineIssueBranch::MergeCommitIssueResolver.new(repository: repository, revision: revision)
  end
end
