# frozen_string_literal: true

module RedmineIssueBranch
  module Patches
    module GitAdapterPatch
      FULL_SHA = /\A[0-9a-f]{40}\z/i

      def branches_containing(scmid)
        revision = scmid.to_s
        return [] unless revision.match?(FULL_SHA)

        branches = []
        git_cmd(%W[branch --all --no-color --contains #{revision}]) do |io|
          io.each_line do |line|
            branch = normalize_containing_branch(line)
            branches << branch if branch
          end
        end
        branches.uniq
      rescue Redmine::Scm::Adapters::AbstractAdapter::ScmCommandAborted
        []
      end

      private

      def normalize_containing_branch(line)
        branch = line.to_s.strip.sub(/\A\*\s+/, '')
        return if branch.empty? || branch.include?(' -> ')

        branch
      end
    end
  end
end
