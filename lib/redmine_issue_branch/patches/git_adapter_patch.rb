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

      def parents_of(scmid)
        revision = scmid.to_s
        return [] unless revision.match?(FULL_SHA)

        parents = []
        git_cmd(%W[rev-list --parents -n 1 #{revision}]) do |io|
          io.each_line do |line|
            parents = line.to_s.strip.split(/\s+/).drop(1)
          end
        end
        parents.select {|parent| parent.match?(FULL_SHA)}
      rescue Redmine::Scm::Adapters::AbstractAdapter::ScmCommandAborted
        []
      end

      def branch_heads_at(scmid)
        revision = scmid.to_s
        return [] unless revision.match?(FULL_SHA)

        branches = []
        git_cmd(
          %W[for-each-ref --points-at=#{revision} --format=%(refname:short)
             refs/heads refs/remotes]
        ) do |io|
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
