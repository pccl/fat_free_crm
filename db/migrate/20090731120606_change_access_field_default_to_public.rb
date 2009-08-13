class ChangeAccessFieldDefaultToPublic < ActiveRecord::Migration
  def self.up
    tables_with_access_field.each do |table|
      change_column_default(table, :access, "Public")
    end
  end

  def self.down
    tables_with_access_field.each do |table|
      change_column_default(table, :access, "Private")
    end
  end

  def self.tables_with_access_field
    [:accounts, :campaigns, :contacts, :leads, :opportunities,  (:issues if defined?(Issue))].compact
  end
end
