# frozen_string_literal: true

require_relative '../test_helper'

class RevisionMessageEnricherTest < ActiveSupport::TestCase
  test 'appends a Redmine issue reference without changing the Git commit' do
    enriched = RedmineIssueBranch::RevisionMessageEnricher.new.call(
      message: 'Add candidate export',
      issue_id: 1842
    )

    assert_equal "Add candidate export\n\nrefs #1842", enriched
  end

  test 'does not duplicate an existing reference' do
    original = "Add candidate export\n\nrefs #1842"
    enriched = RedmineIssueBranch::RevisionMessageEnricher.new.call(
      message: original,
      issue_id: 1842
    )

    assert_equal original, enriched
  end

  test 'falls back to the safe default for an invalid keyword' do
    enriched = RedmineIssueBranch::RevisionMessageEnricher.new(
      reference_keyword: "refs\ncloses"
    ).call(message: 'Fix token refresh', issue_id: 42)

    assert_equal "Fix token refresh\n\nrefs #42", enriched
  end

  test 'returns the original message for an invalid issue id' do
    enriched = RedmineIssueBranch::RevisionMessageEnricher.new.call(
      message: 'No issue',
      issue_id: 'invalid'
    )

    assert_equal 'No issue', enriched
  end
end
