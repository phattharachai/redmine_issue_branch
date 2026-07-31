# frozen_string_literal: true

module RedmineIssueBranch
  module Patches
    module RepositoryGitPatch
      def save_revision(revision)
        enriched_revision =
          RedmineIssueBranch::RevisionEnrichmentService.new(
            repository: self,
            revision: revision
          ).call

        super(enriched_revision)
      end

      private :save_revision
    end
  end
end
