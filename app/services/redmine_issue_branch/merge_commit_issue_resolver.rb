# frozen_string_literal: true

module RedmineIssueBranch
  # Resolves a candidate Issue ID for a genuine two-parent merge commit.
  #
  # The first parent is treated as the branch merged into (matching Git's own
  # convention for `git merge`, including GitHub/GitLab merge-commit
  # creation); the second parent is the incoming branch. Resolution never
  # mutates an Issue or Changeset; it only returns a candidate ID for the
  # caller to hand to RevisionMessageEnricher.
  class MergeCommitIssueResolver
    Result = Struct.new(
      :status,
      :issue_id,
      :reason,
      keyword_init: true
    ) do
      def matched?
        status == :matched
      end
    end

    def initialize(repository:, revision:, extractor: IssueReferenceExtractor.new)
      @repository = repository
      @revision = revision
      @extractor = extractor
    end

    def call
      parents = Array(repository.scm.parents_of(revision.scmid))

      return no_match('not_a_merge_commit') if parents.length < 2
      return ambiguous('octopus_unsupported') if parents.length > 2

      resolve_incoming_parent(parents.last)
    end

    private

    attr_reader :repository, :revision, :extractor

    def resolve_incoming_parent(parent_scmid)
      resolve_from_changeset(parent_scmid) || resolve_from_branch_heads(parent_scmid)
    end

    def resolve_from_changeset(parent_scmid)
      changeset = repository.changesets.find_by(revision: parent_scmid)
      return nil unless changeset

      issue_ids = changeset.issues.map(&:id).uniq

      case issue_ids.length
      when 0
        nil
      when 1
        matched(issue_ids.first, 'changeset_lookup')
      else
        ambiguous('changeset_multiple_issues')
      end
    end

    def resolve_from_branch_heads(parent_scmid)
      branches = Array(repository.scm.branch_heads_at(parent_scmid))
      results = branches.map {|branch| extractor.call(branch)}
      matched_results = results.select(&:matched?)
      issue_ids = matched_results.map(&:issue_id).uniq

      return no_match('no_source_branch_issue') if issue_ids.empty?

      if issue_ids.length > 1 || results.any? {|result| result.status == :ambiguous}
        return ambiguous('ambiguous_issue_ids')
      end

      matched(issue_ids.first, 'branch_head_lookup')
    end

    def matched(issue_id, reason)
      Result.new(status: :matched, issue_id: issue_id, reason: reason)
    end

    def no_match(reason)
      Result.new(status: :no_match, reason: reason)
    end

    def ambiguous(reason)
      Result.new(status: :ambiguous, reason: reason)
    end
  end
end
