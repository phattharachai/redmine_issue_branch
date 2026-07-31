# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../test_helper'

class GitAdapterPatchTest < ActiveSupport::TestCase
  test 'finds local branches containing a revision in a bare repository' do
    Dir.mktmpdir('redmine-issue-branch') do |root|
      work_path = File.join(root, 'work')
      bare_path = File.join(root, 'repository.git')
      FileUtils.mkdir_p(work_path)

      git(root, 'init', '--bare', bare_path)
      git(work_path, 'init', '--initial-branch=main')
      git(work_path, 'config', 'user.name', 'Redmine Test')
      git(work_path, 'config', 'user.email', 'redmine@example.test')

      File.write(File.join(work_path, 'README.md'), "base\n")
      git(work_path, 'add', 'README.md')
      git(work_path, 'commit', '-m', 'Initial commit')
      git(work_path, 'switch', '-c', 'feature/redmine-1842-add-export')

      File.write(File.join(work_path, 'feature.txt'), "feature\n")
      git(work_path, 'add', 'feature.txt')
      git(work_path, 'commit', '-m', 'Add export')
      feature_sha = git(work_path, 'rev-parse', 'HEAD').strip

      git(work_path, 'remote', 'add', 'origin', bare_path)
      git(work_path, 'push', '--all', 'origin')

      adapter = Redmine::Scm::Adapters::GitAdapter.new(bare_path)
      branches = adapter.branches_containing(feature_sha)

      assert_includes branches, 'feature/redmine-1842-add-export'
      assert_not_includes branches, 'main'
    end
  end

  test 'rejects a revision that is not a full Git SHA' do
    adapter = Redmine::Scm::Adapters::GitAdapter.allocate

    assert_empty adapter.branches_containing('HEAD')
    assert_empty adapter.branches_containing('a' * 39)
    assert_empty adapter.branches_containing("a" * 40 + "\n--help")
  end

  private

  def git(directory, *arguments)
    stdout, stderr, status = Open3.capture3('git', *arguments, chdir: directory)
    assert status.success?, "git #{arguments.join(' ')} failed: #{stderr}"
    stdout
  end
end
