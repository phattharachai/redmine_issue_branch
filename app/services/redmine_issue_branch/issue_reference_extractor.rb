# frozen_string_literal: true

module RedmineIssueBranch
  class IssueReferenceExtractor
    Result = Struct.new(
      :status,
      :issue_id,
      :normalized_reference,
      :reason,
      keyword_init: true
    ) do
      def matched?
        status == :matched
      end
    end

    ISSUE_TOKEN = /(?:\A|[\/_-])redmine-(?<issue_id>[1-9]\d*)(?=\z|[\/_-])/i
    IGNORED_REFS = %r{\Arefs/(?:tags|pull)/}i
    LOCAL_HEAD_PREFIX = %r{\Arefs/heads/}i
    REMOTE_HEAD_PREFIX = %r{\Arefs/remotes/[^/]+/}i
    COMMON_REMOTE_PREFIX = %r{\A(?:origin|upstream)/}i

    def call(reference)
      raw_reference = reference.to_s.strip
      return no_match(raw_reference, 'empty_reference') if raw_reference.empty?
      return no_match(raw_reference, 'unsupported_ref') if raw_reference.match?(IGNORED_REFS)

      normalized = normalize(raw_reference)
      issue_ids = normalized.scan(ISSUE_TOKEN).flatten.map(&:to_i).uniq

      case issue_ids.length
      when 0
        no_match(normalized, 'issue_id_not_found')
      when 1
        Result.new(
          status: :matched,
          issue_id: issue_ids.first,
          normalized_reference: normalized
        )
      else
        Result.new(
          status: :ambiguous,
          normalized_reference: normalized,
          reason: 'multiple_issue_ids'
        )
      end
    rescue StandardError
      no_match(reference.to_s, 'parse_error')
    end

    private

    def normalize(reference)
      reference
        .sub(LOCAL_HEAD_PREFIX, '')
        .sub(REMOTE_HEAD_PREFIX, '')
        .sub(COMMON_REMOTE_PREFIX, '')
    end

    def no_match(reference, reason)
      Result.new(
        status: :no_match,
        normalized_reference: reference,
        reason: reason
      )
    end
  end
end
