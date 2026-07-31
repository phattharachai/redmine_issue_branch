# frozen_string_literal: true

require_relative '../test_helper'

class RevisionEnrichmentServiceTest < ActiveSupport::TestCase
  Revision = Struct.new(:scmid, :message, keyword_init: true)
  Repository = Struct.new(:id, :scm, :changesets, keyword_init: true)
  Issue = Struct.new(:id, keyword_init: true)
  Changeset = Struct.new(:revision, :issues, keyword_init: true)

  class FakeAdapter
    attr_reader :calls

    def initialize(branches, parents: [], branch_heads: {})
      @branches = branches
      @parents = parents
      @branch_heads = branch_heads
      @calls = 0
    end

    def branches_containing(_scmid)
      @calls += 1
      @branches
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

  test 'enriches a revision contained in one issue branch' do
    original, service = build_service(['feature/redmine-1842-add-export'])

    enriched = service.call

    assert_not_same original, enriched
    assert_equal 'Add export', original.message
    assert_equal "Add export\n\nrefs #1842", enriched.message
  end

  test 'does not process revisions when the plugin is disabled' do
    adapter = FakeAdapter.new(['feature/redmine-1842-add-export'])
    original, service = build_service([], adapter: adapter, enabled: false)

    assert_same original, service.call
    assert_equal 0, adapter.calls
  end

  test 'skips a revision already contained in a protected branch' do
    original, service =
      build_service(['main', 'feature/redmine-1842-add-export'])

    assert_same original, service.call
  end

  test 'skips branches that resolve to different issue ids' do
    original, service =
      build_service(
        [
          'feature/redmine-1842-add-export',
          'bugfix/redmine-2048-fix-export'
        ]
      )

    assert_same original, service.call
  end

  test 'fails open when branch resolution raises an error' do
    adapter = Object.new
    def adapter.branches_containing(_scmid)
      raise 'SCM unavailable'
    end

    original, service = build_service([], adapter: adapter)

    assert_same original, service.call
  end

  test 'closes an issue for a genuine merge commit landing on a protected branch' do
    base_sha = 'a' * 40
    feature_sha = 'b' * 40
    adapter = FakeAdapter.new(
      ['main'],
      parents: [base_sha, feature_sha],
      branch_heads: {feature_sha => ['feature/redmine-1842-add-export']}
    )

    original, service =
      build_service(
        [],
        adapter: adapter,
        close_by_merge: true,
        close_keyword: 'closes'
      )

    enriched = service.call

    assert_not_same original, enriched
    assert_equal "Add export\n\ncloses #1842", enriched.message
  end

  test 'does not close when close_by_merge is disabled, even for a genuine merge commit' do
    base_sha = 'a' * 40
    feature_sha = 'b' * 40
    adapter = FakeAdapter.new(
      ['main'],
      parents: [base_sha, feature_sha],
      branch_heads: {feature_sha => ['feature/redmine-1842-add-export']}
    )

    original, service =
      build_service([], adapter: adapter, close_by_merge: false, close_keyword: 'closes')

    assert_same original, service.call
  end

  test 'does not close when no Redmine fix keyword is configured' do
    base_sha = 'a' * 40
    feature_sha = 'b' * 40
    adapter = FakeAdapter.new(
      ['main'],
      parents: [base_sha, feature_sha],
      branch_heads: {feature_sha => ['feature/redmine-1842-add-export']}
    )

    original, service =
      build_service([], adapter: adapter, close_by_merge: true, close_keyword: nil)

    assert_same original, service.call
  end

  test 'does not close a single-parent commit reachable from a protected branch' do
    adapter = FakeAdapter.new(['main'], parents: ['a' * 40])

    original, service =
      build_service([], adapter: adapter, close_by_merge: true, close_keyword: 'closes')

    assert_same original, service.call
  end

  test 'does not close an octopus merge' do
    adapter = FakeAdapter.new(
      ['main'],
      parents: ['a' * 40, 'b' * 40, 'c' * 40]
    )

    original, service =
      build_service([], adapter: adapter, close_by_merge: true, close_keyword: 'closes')

    assert_same original, service.call
  end

  test 'closes via an existing Changeset association when the source branch is gone' do
    base_sha = 'a' * 40
    feature_sha = 'b' * 40
    adapter = FakeAdapter.new(['main'], parents: [base_sha, feature_sha])
    changeset = Changeset.new(revision: feature_sha, issues: [Issue.new(id: 1842)])

    original, service =
      build_service(
        [],
        adapter: adapter,
        changesets: {feature_sha => changeset},
        close_by_merge: true,
        close_keyword: 'closes'
      )

    enriched = service.call

    assert_not_same original, enriched
    assert_equal "Add export\n\ncloses #1842", enriched.message
  end

  private

  def build_service(
    branches,
    adapter: FakeAdapter.new(branches),
    enabled: true,
    changesets: {},
    close_by_merge: false,
    close_keyword: nil
  )
    revision =
      Revision.new(
        scmid: 'a' * 40,
        message: 'Add export'
      )
    repository = Repository.new(id: 3, scm: adapter, changesets: FakeChangesets.new(changesets))
    logger = ActiveSupport::Logger.new(IO::NULL)

    service =
      RedmineIssueBranch::RevisionEnrichmentService.new(
        repository: repository,
        revision: revision,
        enabled: enabled,
        protected_branches: %w[main master],
        reference_keyword: 'refs',
        close_by_merge: close_by_merge,
        close_keyword: close_keyword,
        logger: logger
      )

    [revision, service]
  end
end
