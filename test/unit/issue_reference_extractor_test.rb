# frozen_string_literal: true

require_relative '../test_helper'

class IssueReferenceExtractorTest < ActiveSupport::TestCase
  def setup
    @extractor = RedmineIssueBranch::IssueReferenceExtractor.new
  end

  test 'extracts an issue id from a local feature branch' do
    result = @extractor.call('feature/redmine-1842-add-candidate-export')

    assert result.matched?
    assert_equal 1842, result.issue_id
    assert_equal 'feature/redmine-1842-add-candidate-export', result.normalized_reference
  end

  test 'normalizes remote tracking references' do
    result = @extractor.call('refs/remotes/origin/bugfix/redmine-42-fix-token')

    assert result.matched?
    assert_equal 42, result.issue_id
    assert_equal 'bugfix/redmine-42-fix-token', result.normalized_reference
  end

  test 'normalizes refs returned by git branch all' do
    result = @extractor.call('remotes/origin/bugfix/redmine-42-fix-token')

    assert result.matched?
    assert_equal 42, result.issue_id
    assert_equal 'bugfix/redmine-42-fix-token', result.normalized_reference
  end

  test 'rejects tags and pull request references' do
    tag = @extractor.call('refs/tags/redmine-42')
    pull_request = @extractor.call('refs/pull/42/head')

    assert_equal :no_match, tag.status
    assert_equal 'unsupported_ref', tag.reason
    assert_equal :no_match, pull_request.status
    assert_equal 'unsupported_ref', pull_request.reason
  end

  test 'does not treat release numbers as issue ids' do
    result = @extractor.call('release/2026-07')

    assert_equal :no_match, result.status
    assert_equal 'issue_id_not_found', result.reason
  end

  test 'rejects ambiguous branch references' do
    result = @extractor.call('feature/redmine-123-redmine-456')

    assert_equal :ambiguous, result.status
    assert_nil result.issue_id
    assert_equal 'multiple_issue_ids', result.reason
  end
end
