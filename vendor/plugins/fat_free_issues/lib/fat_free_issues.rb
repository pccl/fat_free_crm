# fat_free_issues.rb

# Extend :account model to add :issues association.
Account.send(:include, AccountIssueAssociations)

ActivityObserver.instance.send :add_observer!, Issue

# Add :issues plugin helpers.
ActionView::Base.send(:include, IssuesHelper)
