# frozen_string_literal: true

require_relative 'lib/redmine_issue_branch'

Redmine::Plugin.register :redmine_issue_branch do
  name 'Redmine Issue Branch'
  author 'Phattharachai Vongkoon'
  description 'Links Redmine issues to Git branch references during changeset import.'
  version '0.1.0'
  url 'https://github.com/phattharachai/redmine_issue_branch'
  author_url 'https://github.com/phattharachai'

  requires_redmine version_or_higher: '6.1.0'

  settings(
    default: {
      'enabled' => '0',
      'reference_keyword' => 'refs',
      'close_by_merge' => '0',
      'merge_branches' => "main\nmaster"
    },
    partial: 'settings/redmine_issue_branch'
  )
end
