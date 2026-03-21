# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "action_figure"

require "minitest/autorun"
require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
    t.string :email
  end
end

# Minimal AR fixture model used in formatter tests
class User < ActiveRecord::Base; end
