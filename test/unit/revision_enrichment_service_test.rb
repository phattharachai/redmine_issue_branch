# frozen_string_literal: true

require_relative '../test_helper'

class RevisionEnrichmentServiceTest < ActiveSupport::TestCase
  Revision = Struct.new(:scmid, :message, keyword_init: true)
  Repository = Struct.new(:id, :scm, keyword_init: true)

  class FakeAdapter
    attr_reader :calls

    def initialize(branches)
      @branches = branches
      @calls = 0
    end

    def branches_containing(_scmid)
      @calls += 1
      @branches
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

  private

  def build_service(branches, adapter: FakeAdapter.new(branches), enabled: true)
    revision =
      Revision.new(
        scmid: 'a' * 40,
        message: 'Add export'
      )
    repository = Repository.new(id: 3, scm: adapter)
    logger = ActiveSupport::Logger.new(IO::NULL)

    service =
      RedmineIssueBranch::RevisionEnrichmentService.new(
        repository: repository,
        revision: revision,
        enabled: enabled,
        protected_branches: %w[main master],
        reference_keyword: 'refs',
        logger: logger
      )

    [revision, service]
  end
end
