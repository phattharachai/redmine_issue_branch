# frozen_string_literal: true

require_relative '../app/services/redmine_issue_branch/issue_reference_extractor'
require_relative '../app/services/redmine_issue_branch/revision_message_enricher'
require_relative '../app/services/redmine_issue_branch/revision_enrichment_service'
require_relative 'redmine_issue_branch/patches/git_adapter_patch'
require_relative 'redmine_issue_branch/patches/repository_git_patch'

module RedmineIssueBranch
  PLUGIN_ID = :redmine_issue_branch
  VERSION = '0.2.0'

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

Rails.application.config.to_prepare do
  git_adapter = Redmine::Scm::Adapters::GitAdapter
  repository_git = Repository::Git

  unless git_adapter.ancestors.include?(RedmineIssueBranch::Patches::GitAdapterPatch)
    git_adapter.prepend(RedmineIssueBranch::Patches::GitAdapterPatch)
  end

  unless repository_git.ancestors.include?(RedmineIssueBranch::Patches::RepositoryGitPatch)
    repository_git.prepend(RedmineIssueBranch::Patches::RepositoryGitPatch)
  end
end
