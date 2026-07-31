# frozen_string_literal: true

module RedmineIssueBranch
  class RevisionMessageEnricher
    DEFAULT_KEYWORD = 'refs'
    KEYWORD_FORMAT = /\A[a-z][a-z0-9_-]*\z/i

    def initialize(reference_keyword: DEFAULT_KEYWORD)
      @reference_keyword = valid_keyword(reference_keyword)
    end

    def call(message:, issue_id:)
      original_message = message.to_s
      normalized_issue_id = Integer(issue_id.to_s, 10)
      return original_message unless normalized_issue_id.positive?
      return original_message if references_issue?(original_message, normalized_issue_id)

      [original_message.rstrip, "#{@reference_keyword} ##{normalized_issue_id}"]
        .reject(&:empty?)
        .join("\n\n")
    rescue ArgumentError, TypeError
      original_message
    end

    private

    def valid_keyword(keyword)
      normalized = keyword.to_s.strip
      normalized.match?(KEYWORD_FORMAT) ? normalized : DEFAULT_KEYWORD
    end

    def references_issue?(message, issue_id)
      message.match?(/(?:\A|\s)#{Regexp.escape(@reference_keyword)}\s+##{issue_id}(?:\D|\z)/i)
    end
  end
end
