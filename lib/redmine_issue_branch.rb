# frozen_string_literal: true

require_relative '../app/services/redmine_issue_branch/issue_reference_extractor'
require_relative '../app/services/redmine_issue_branch/revision_message_enricher'

module RedmineIssueBranch
  PLUGIN_ID = :redmine_issue_branch
  VERSION = '0.1.0'

  class << self
    def settings
      Setting.plugin_redmine_issue_branch || {}
    end

    def enabled?
      settings.fetch('enabled', '0') == '1'
    end

    def close_by_merge?
      settings.fetch('close_by_merge', '0') == '1'
    end

    def reference_keyword
      settings.fetch('reference_keyword', 'refs')
    end

    def merge_branches
      settings.fetch('merge_branches', "main\nmaster")
              .lines
              .map(&:strip)
              .reject(&:empty?)
              .uniq
    end
  end
end
