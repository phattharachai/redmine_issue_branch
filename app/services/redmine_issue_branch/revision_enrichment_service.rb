# frozen_string_literal: true

module RedmineIssueBranch
  class RevisionEnrichmentService
    LOG_PREFIX = '[redmine_issue_branch]'

    def initialize(
      repository:,
      revision:,
      enabled: RedmineIssueBranch.enabled?,
      protected_branches: RedmineIssueBranch.merge_branches,
      reference_keyword: RedmineIssueBranch.reference_keyword,
      close_by_merge: RedmineIssueBranch.close_by_merge?,
      close_keyword: RedmineIssueBranch.close_keyword,
      logger: Rails.logger
    )
      @repository = repository
      @revision = revision
      @enabled = enabled
      @protected_branches = Array(protected_branches)
      @extractor = IssueReferenceExtractor.new
      @enricher = RevisionMessageEnricher.new(reference_keyword: reference_keyword)
      @close_by_merge = close_by_merge
      @close_keyword = close_keyword
      @logger = logger
    end

    def call
      return revision unless enabled

      results = containing_branches.map {|branch| extractor.call(branch)}
      protected_branch = protected_branch_match(results)
      return handle_protected_revision(protected_branch) if protected_branch

      matched_results = results.select(&:matched?)
      issue_ids = matched_results.map(&:issue_id).uniq
      return revision if issue_ids.empty?

      if ambiguous?(results, issue_ids)
        audit('skipped', reason: 'ambiguous_issue_ids')
        return revision
      end

      enrich(matched_results.first, issue_ids.first)
    rescue StandardError => error
      audit('error', error_class: error.class.name)
      revision
    end

    private

    attr_reader :repository, :revision, :enabled, :protected_branches,
                :extractor, :enricher, :close_by_merge, :close_keyword, :logger

    def containing_branches
      Array(repository.scm.branches_containing(revision.scmid))
    end

    def protected_branch_match(results)
      normalized_branches = results.map(&:normalized_reference)
      (normalized_branches & protected_branches).first
    end

    def handle_protected_revision(branch)
      return close_via_merge if close_by_merge

      audit('skipped', reason: 'protected_branch', branch: branch)
      revision
    end

    def close_via_merge
      unless close_keyword
        audit('skipped', reason: 'fix_keyword_unset')
        return revision
      end

      result = MergeCommitIssueResolver.new(repository: repository, revision: revision).call
      return close(result.issue_id) if result.matched?

      audit('skipped', reason: "merge_#{result.reason}")
      revision
    end

    def close(issue_id)
      closer = RevisionMessageEnricher.new(reference_keyword: close_keyword)
      enriched_message = closer.call(message: revision.message, issue_id: issue_id)
      return revision if enriched_message == revision.message.to_s

      enriched_revision = revision.dup
      enriched_revision.message = enriched_message
      audit('closed', issue_id: issue_id)
      enriched_revision
    end

    def ambiguous?(results, issue_ids)
      issue_ids.length > 1 || results.any? {|result| result.status == :ambiguous}
    end

    def enrich(result, issue_id)
      enriched_message = enricher.call(message: revision.message, issue_id: issue_id)
      return revision if enriched_message == revision.message.to_s

      enriched_revision = revision.dup
      enriched_revision.message = enriched_message
      audit('enriched', issue_id: issue_id, branch: result.normalized_reference)
      enriched_revision
    end

    def audit(action, attributes = {})
      fields = {
        action: action,
        repository_id: repository.respond_to?(:id) ? repository.id : nil,
        revision: revision.scmid.to_s[0, 12]
      }.merge(attributes)

      payload =
        fields.filter_map do |key, value|
          next if value.nil?

          "#{key}=#{sanitize(value)}"
        end.join(' ')

      logger.info("#{LOG_PREFIX} #{payload}")
    end

    def sanitize(value)
      value.to_s.gsub(/[^a-zA-Z0-9_.\/-]/, '_')[0, 255]
    end
  end
end
