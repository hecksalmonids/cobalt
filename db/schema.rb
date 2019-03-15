# This file contains the schema for the database.
# Under most circumstances, you shouldn't need to run this file directly.
require 'sequel'

module Schema
  Sequel.sqlite(ENV['DB_PATH']) do |db|
    db.create_table?(:custom_commands) do
      String :key, :size=>255
      String :content, :size=>255
      Integer :user
    end

    db.create_table?(:tags) do
      String :key, :size=>255
      String :content, :size=>255
      Integer :user
    end

    db.create_table?(:economy_users) do
      primary_key :id
      Integer :money, :default=>0
      DateTime :next_checkin
      String :color_role, :default=>"None", :size=>255
      DateTime :color_role_daily
    end
  end
end