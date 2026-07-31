# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../test_helper'

class StagingE2eHarnessTest < ActiveSupport::TestCase
  Revision = Struct.new(:scmid, :message, keyword_init: true)
  Repository = Struct.new(:id, :scm, :changesets, keyword_init: true)

  class NullChangesets
    def find_by(revision:)
      nil
    end
  end

  class RecordingAdapter
    include RedmineIssueBranch::Patches::GitAdapterPatch

    attr_reader :git_calls

    def initialize
      @git_calls = 0
    end

    private

    def git_cmd(*)
      @git_calls += 1
      raise 'Git must not be called for an invalid SHA'
    end
  end

  def setup
    @root = Dir.mktmpdir('redmine-issue-branch-e2e')
    @work_path = File.join(@root, 'work')
    @bare_path = File.join(@root, 'repository.git')
    FileUtils.mkdir_p(@work_path)

    git(@root, 'init', '--bare', @bare_path)
    git(@root, "--git-dir=#{@bare_path}", 'config', 'gc.auto', '0')
    git(@root, "--git-dir=#{@bare_path}", 'config', 'maintenance.auto', 'false')
    git(@work_path, 'init', '--initial-branch=main')
    git(@work_path, 'config', 'user.name', 'Redmine Test')
    git(@work_path, 'config', 'user.email', 'redmine@example.test')
    git(@work_path, 'config', 'gc.auto', '0')
    git(@work_path, 'config', 'maintenance.auto', 'false')
    git(@work_path, 'remote', 'add', 'origin', @bare_path)

    commit_file('base.txt', "base\n", 'Initial commit')
    git(@work_path, 'push', '-u', 'origin', 'main')
  end

  def teardown
    return unless @root && File.exist?(@root)

    attempts = 3
    begin
      FileUtils.remove_entry(@root)
    rescue Errno::ENOTEMPTY
      attempts -= 1
      raise if attempts.zero?

      sleep 0.05
      retry
    end
  end

  test 'enriches a positive issue branch through a bare Git repository' do
    sha = create_branch_commit('test/redmine-1842-import', 'Import candidate')

    original, enriched = enrich(sha, 'Import candidate')

    assert_not_same original, enriched
    assert_equal 'Import candidate', original.message
    assert_equal "Import candidate\n\nrefs #1842", enriched.message
    assert_equal(
      'Import candidate',
      git(@bare_path, 'show', '--no-patch', '--format=%s', sha).strip
    )
  end

  test 'does not enrich missing zero or malformed issue ids' do
    {
      'test/changeset-import' => 'Missing ID',
      'test/redmine-0-import' => 'Zero ID',
      'test/redmine-abc-import' => 'Malformed ID'
    }.each do |branch, message|
      reset_to_main
      sha = create_branch_commit(branch, message)
      original, enriched = enrich(sha, message)

      assert_same original, enriched, "expected #{branch} not to enrich"
    end
  end

  test 'fails closed for two issue tokens in one branch' do
    sha = create_branch_commit(
      'test/redmine-1842-redmine-2048',
      'Ambiguous token'
    )

    original, enriched = enrich(sha, 'Ambiguous token')

    assert_same original, enriched
  end

  test 'does not enrich a commit reachable from a protected branch' do
    sha = create_branch_commit('test/redmine-1842-import', 'Protected commit')
    git(@work_path, 'push', 'origin', 'HEAD:main')

    original, enriched = enrich(sha, 'Protected commit')

    assert_same original, enriched
  end

  test 'does not duplicate an existing issue reference' do
    message = "Import candidate\n\nrefs #1842"
    sha = create_branch_commit('test/redmine-1842-import', message)

    original, enriched = enrich(sha, message)

    assert_same original, enriched
    assert_equal 1, enriched.message.scan('refs #1842').length
  end

  test 'fails closed when containing branches resolve to different issues' do
    sha = create_branch_commit('test/redmine-1842-import', 'Shared commit')
    git(
      @work_path,
      'push',
      'origin',
      'HEAD:refs/heads/test/redmine-2048-import'
    )

    original, enriched = enrich(sha, 'Shared commit')

    assert_same original, enriched
  end

  test 'does not invoke Git for an invalid SHA' do
    adapter = RecordingAdapter.new
    revision = Revision.new(scmid: 'HEAD', message: 'Invalid SHA')

    result = service(adapter, revision).call

    assert_same revision, result
    assert_equal 0, adapter.git_calls
  end

  test 'fails open when Git lookup fails' do
    missing_repository = File.join(@root, 'missing.git')
    adapter = Redmine::Scm::Adapters::GitAdapter.new(missing_repository)
    revision = Revision.new(scmid: 'a' * 40, message: 'Git error')

    result = service(adapter, revision).call

    assert_same revision, result
  end

  test 'ignores tag and pull request refs' do
    git(@work_path, 'switch', '-c', 'temporary-import')
    commit_file('refs.txt', "refs\n", 'Refs only')
    sha = git(@work_path, 'rev-parse', 'HEAD').strip
    git(@work_path, 'tag', 'redmine-1842-import')
    git(@work_path, 'push', 'origin', 'refs/tags/redmine-1842-import')
    git(@work_path, 'push', 'origin', 'HEAD:refs/pull/1842/head')

    original, enriched = enrich(sha, 'Refs only')

    assert_same original, enriched
  end

  test 'closes an issue for a genuine merge commit landing on main' do
    feature_sha = create_branch_commit('test/redmine-1842-import', 'Add export')
    reset_to_main
    merge_sha = merge_into_current_branch(
      'test/redmine-1842-import',
      'Merge export'
    )
    git(@work_path, 'push', 'origin', 'main')

    original, enriched = close_via_merge(merge_sha, 'Merge export', close_keyword: 'closes')

    assert_not_same original, enriched
    assert_equal "Merge export\n\ncloses #1842", enriched.message
    assert_equal(
      'Merge export',
      git(@bare_path, 'show', '--no-patch', '--format=%s', merge_sha).strip
    )
    refute_nil feature_sha
  end

  test 'does not close a merge commit when close_by_merge is disabled' do
    create_branch_commit('test/redmine-1842-import', 'Add export')
    reset_to_main
    merge_sha = merge_into_current_branch(
      'test/redmine-1842-import',
      'Merge export'
    )
    git(@work_path, 'push', 'origin', 'main')

    revision = Revision.new(scmid: merge_sha, message: 'Merge export')
    adapter = Redmine::Scm::Adapters::GitAdapter.new(@bare_path)
    result = service(adapter, revision, close_by_merge: false, close_keyword: 'closes').call

    assert_same revision, result
  end

  test 'does not close a squash merge (no parent link to the source branch)' do
    create_branch_commit('test/redmine-1842-import', 'Add export')
    reset_to_main
    git(@work_path, 'merge', '--squash', 'test/redmine-1842-import')
    commit_file('squash.txt', "squash\n", 'Squash merge export')
    squash_sha = git(@work_path, 'rev-parse', 'HEAD').strip
    git(@work_path, 'push', 'origin', 'main')

    original, enriched = close_via_merge(squash_sha, 'Squash merge export', close_keyword: 'closes')

    assert_same original, enriched
  end

  test 'does not close an octopus merge' do
    git(@work_path, 'switch', '-c', 'test/redmine-1842-import')
    commit_file('first.txt', "first\n", 'Add export')

    reset_to_main
    git(@work_path, 'switch', '-c', 'test/redmine-2048-import')
    commit_file('second.txt', "second\n", 'Add another export')

    reset_to_main
    git(
      @work_path,
      'merge', '--no-ff', '-m', 'Octopus merge',
      'test/redmine-1842-import', 'test/redmine-2048-import'
    )
    octopus_sha = git(@work_path, 'rev-parse', 'HEAD').strip
    git(@work_path, 'push', 'origin', 'main')

    original, enriched = close_via_merge(octopus_sha, 'Octopus merge', close_keyword: 'closes')

    assert_same original, enriched
  end

  test 'does not close a merge landing on a branch outside the protected list' do
    create_branch_commit('test/redmine-1842-import', 'Add export')
    git(@work_path, 'switch', '-c', 'develop', 'main')
    merge_sha = merge_into_current_branch(
      'test/redmine-1842-import',
      'Merge export into develop'
    )
    git(@work_path, 'push', '-u', 'origin', 'develop')

    # The merge commit's own containing branch is only 'develop', which is
    # neither a configured protected branch nor a `redmine-<id>` token, so
    # the merge-close path is never attempted and the commit is left as-is
    # -- exactly like any other non-matching commit.
    original, enriched = close_via_merge(
      merge_sha,
      'Merge export into develop',
      close_keyword: 'closes'
    )

    assert_same original, enriched
  end

  test 'closes an issue using the real Redmine update-keywords setting' do
    original_update_keywords = Setting.commit_update_keywords
    begin
      Setting.commit_update_keywords = [{'keywords' => 'closes'}]

      create_branch_commit('test/redmine-1842-import', 'Add export')
      reset_to_main
      merge_sha = merge_into_current_branch(
        'test/redmine-1842-import',
        'Merge export'
      )
      git(@work_path, 'push', 'origin', 'main')

      revision = Revision.new(scmid: merge_sha, message: 'Merge export')
      adapter = Redmine::Scm::Adapters::GitAdapter.new(@bare_path)
      enriched = service(adapter, revision, close_by_merge: true).call

      assert_not_same revision, enriched
      assert_equal "Merge export\n\ncloses #1842", enriched.message
    ensure
      Setting.commit_update_keywords = original_update_keywords
    end
  end

  private

  def create_branch_commit(branch, message)
    git(@work_path, 'switch', '-c', branch)
    commit_file('case.txt', "#{branch}\n", message)
    git(@work_path, 'push', '-u', 'origin', branch)
    git(@work_path, 'rev-parse', 'HEAD').strip
  end

  def reset_to_main
    git(@work_path, 'switch', 'main')
  end

  def commit_file(path, content, message)
    File.write(File.join(@work_path, path), content)
    git(@work_path, 'add', path)
    git(@work_path, 'commit', '-m', message)
  end

  def merge_into_current_branch(branch, message)
    git(@work_path, 'merge', '--no-ff', '-m', message, branch)
    git(@work_path, 'rev-parse', 'HEAD').strip
  end

  def enrich(sha, message)
    revision = Revision.new(scmid: sha, message: message)
    adapter = Redmine::Scm::Adapters::GitAdapter.new(@bare_path)

    [revision, service(adapter, revision).call]
  end

  def close_via_merge(sha, message, close_keyword:)
    revision = Revision.new(scmid: sha, message: message)
    adapter = Redmine::Scm::Adapters::GitAdapter.new(@bare_path)

    [
      revision,
      service(adapter, revision, close_by_merge: true, close_keyword: close_keyword).call
    ]
  end

  def service(adapter, revision, close_by_merge: false, close_keyword: nil)
    RedmineIssueBranch::RevisionEnrichmentService.new(
      repository: Repository.new(id: 1842, scm: adapter, changesets: NullChangesets.new),
      revision: revision,
      enabled: true,
      protected_branches: %w[main master],
      reference_keyword: 'refs',
      close_by_merge: close_by_merge,
      close_keyword: close_keyword,
      logger: ActiveSupport::Logger.new(IO::NULL)
    )
  end

  def git(directory, *arguments)
    stdout, stderr, status = Open3.capture3('git', *arguments, chdir: directory)
    assert status.success?, "git #{arguments.join(' ')} failed: #{stderr}"
    stdout
  end
end
