# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"

module Users
  class Create
    include ActionFigure[:jsend]

    params_schema do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end

    rules do
      rule(:email) do
        key.failure("is already taken") if values[:email] == "taken@example.com"
      end
    end

    def create(params:, company: nil)
      user = User.create!(params)
      Ok(resource: { id: user.id, name: user.name, email: user.email, company: company })
    end
  end

  class Search
    include ActionFigure[:jsend]

    params_schema do
      required(:query).filled(:string)
      optional(:cursor).maybe(:string)
    end

    def search(*)
      results = User.all.map { |u| { name: u.name } }
      Ok(resource: results, meta: { next_cursor: "abc123", total: results.size })
    end
  end

  class Destroy
    include ActionFigure

    def destroy(id:, **)
      user = User.find_by(id: id)
      return NotFound(errors: { base: ["user not found"] }) unless user

      user.destroy!
      NoContent()
    end
  end
end

class IntegrationTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def setup
    User.delete_all
  end

  # --- Users::Create ---

  def test_create_returns_ok_with_valid_params
    result = Users::Create.create(params: { name: "Tad", email: "tad@example.com" })

    assert_Ok(result)
    assert_equal "Tad", result[:json][:data][:name]
    assert_equal "tad@example.com", result[:json][:data][:email]
    assert_equal "success", result[:json][:status]
  end

  def test_create_persists_the_user
    Users::Create.create(params: { name: "Tad", email: "tad@example.com" })

    assert_equal 1, User.count
    assert_equal "Tad", User.last.name
  end

  def test_create_passes_extra_kwargs_through
    result = Users::Create.create(params: { name: "Tad", email: "tad@example.com" }, company: "Acme")

    assert_Ok(result)
    assert_equal "Acme", result[:json][:data][:company]
  end

  def test_create_returns_unprocessable_content_when_params_invalid
    result = Users::Create.create(params: { name: "Tad" })

    assert_UnprocessableContent(result)
    assert_equal "fail", result[:json][:status]
    assert result[:json][:data].key?(:email), "expected errors to include :email"
  end

  def test_create_does_not_persist_when_params_invalid
    Users::Create.create(params: { name: "Tad" })

    assert_equal 0, User.count
  end

  def test_create_returns_unprocessable_content_when_rule_fails
    result = Users::Create.create(params: { name: "Tad", email: "taken@example.com" })

    assert_UnprocessableContent(result)
    assert_includes result[:json][:data][:email], "is already taken"
  end

  def test_create_does_not_persist_when_rule_fails
    Users::Create.create(params: { name: "Tad", email: "taken@example.com" })

    assert_equal 0, User.count
  end

  def test_create_coerces_string_keys_to_symbols
    result = Users::Create.create(params: { "name" => "Tad", "email" => "tad@example.com" })

    assert_Ok(result)
    assert_equal "Tad", result[:json][:data][:name]
  end

  # --- Users::Search (meta) ---

  def test_search_returns_results_with_meta
    User.create!(name: "Tad", email: "tad@example.com")
    User.create!(name: "Bob", email: "bob@example.com")

    result = Users::Search.search(params: { query: "all" })

    assert_Ok(result)
    assert_equal 2, result[:json][:data].size
    assert_equal "abc123", result[:json][:meta][:next_cursor]
    assert_equal 2, result[:json][:meta][:total]
  end

  def test_ok_without_meta_omits_meta_key
    result = Users::Create.create(params: { name: "Tad", email: "tad@example.com" })

    assert_Ok(result)
    refute result[:json].key?(:meta), "expected :meta key to be absent"
  end

  # --- Users::Destroy ---

  def test_destroy_returns_no_content
    user = User.create!(name: "Tad", email: "tad@example.com")

    result = Users::Destroy.destroy(id: user.id)

    assert_NoContent(result)
  end

  def test_destroy_removes_the_record
    user = User.create!(name: "Tad", email: "tad@example.com")

    Users::Destroy.destroy(id: user.id)

    assert_equal 0, User.count
  end

  def test_destroy_returns_not_found_for_missing_record
    result = Users::Destroy.destroy(id: 999999)

    assert_NotFound(result)
    assert_includes result[:json][:errors][:base], "user not found"
  end

  # --- render hash shape ---

  def test_ok_result_has_json_and_status_keys
    result = Users::Create.create(params: { name: "Tad", email: "tad@example.com" })

    assert result.key?(:json), "expected :json key for Rails render"
    assert result.key?(:status), "expected :status key for Rails render"
  end

  def test_no_content_result_has_status_but_no_json
    user = User.create!(name: "Tad", email: "tad@example.com")

    result = Users::Destroy.destroy(id: user.id)

    assert result.key?(:status)
    refute result.key?(:json), "NoContent should not have a :json key"
  end

  def test_error_result_has_json_and_status_keys
    result = Users::Create.create(params: {})

    assert result.key?(:json), "expected :json key on error"
    assert result.key?(:status), "expected :status key on error"
  end
end
