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

    def apply_patches!
      git_adapter = Redmine::Scm::Adapters::GitAdapter
      repository_git = Repository::Git

      unless git_adapter.ancestors.include?(Patches::GitAdapterPatch)
        git_adapter.prepend(Patches::GitAdapterPatch)
      end

      unless repository_git.ancestors.include?(Patches::RepositoryGitPatch)
        repository_git.prepend(Patches::RepositoryGitPatch)
      end
    end
  end
end

Rails.application.config.to_prepare do
  RedmineIssueBranch.apply_patches!
end

# Redmine loads plugin init files after the application's initial prepare pass.
# Apply once during boot, then retain to_prepare for development class reloads.
RedmineIssueBranch.apply_patches!
