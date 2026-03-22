# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"

# Simulated AR-style model for testing without a database
class FakeUser
  attr_reader :id, :name, :email, :errors

  def initialize(attrs = {})
    @id    = rand(1000)
    @name  = attrs[:name]
    @email = attrs[:email]
    @errors = FakeErrors.new
  end

  def persisted?
    @errors.empty?
  end

  FakeErrors = Struct.new(:messages) do
    def initialize
      super({})
    end

    def add(field, message)
      messages[field] ||= []
      messages[field] << message
    end

    def empty?
      messages.empty?
    end

    def to_h
      messages
    end
  end
end

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

    def call(params:, company: nil)
      user = FakeUser.new(params)
      Ok(resource: { id: user.id, name: user.name, email: user.email, company: company })
    end
  end

  class Search
    include ActionFigure[:jsend]

    params_schema do
      required(:query).filled(:string)
      optional(:cursor).maybe(:string)
    end

    def call(*)
      results = [{ name: "Tad" }, { name: "Bob" }]
      Ok(resource: results, meta: { next_cursor: "abc123", total: 2 })
    end
  end

  class Destroy
    include ActionFigure

    def call(*)
      NoContent()
    end
  end
end

class IntegrationTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  # --- Users::Create ---

  def test_create_returns_ok_with_valid_params
    result = Users::Create.call(params: { name: "Tad", email: "tad@example.com" })
    assert_Ok(result)
    assert_equal "Tad", result[:json][:data][:name]
    assert_equal "success", result[:json][:status]
  end

  def test_create_passes_extra_kwargs_through
    result = Users::Create.call(params: { name: "Tad", email: "tad@example.com" }, company: "Acme")
    assert_Ok(result)
    assert_equal "Acme", result[:json][:data][:company]
  end

  def test_create_returns_unprocessable_entity_when_params_invalid
    result = Users::Create.call(params: { name: "Tad" }) # missing email
    assert_UnprocessableEntity(result)
    assert_equal "fail", result[:json][:status]
    assert result[:json][:data].key?(:email)
  end

  def test_create_returns_unprocessable_entity_when_rule_fails
    result = Users::Create.call(params: { name: "Tad", email: "taken@example.com" })
    assert_UnprocessableEntity(result)
    assert_includes result[:json][:data][:email], "is already taken"
  end

  def test_create_coerces_types
    # params_schema coerces string keys from ActionController::Parameters-style input
    result = Users::Create.call(params: { "name" => "Tad", "email" => "tad@example.com" })
    assert_Ok(result)
  end

  # --- Users::Search (meta) ---

  def test_search_returns_meta
    result = Users::Search.call(params: { query: "tad" })
    assert_Ok(result)
    assert_equal "abc123", result[:json][:meta][:next_cursor]
    assert_equal 2, result[:json][:meta][:total]
  end

  def test_ok_without_meta_omits_meta_key
    result = Users::Create.call(params: { name: "Tad", email: "tad@example.com" })
    assert_Ok(result)
    refute result[:json].key?(:meta)
  end

  # --- Users::Destroy (no params:) ---

  def test_destroy_returns_no_content
    result = Users::Destroy.call(current_user: Object.new)
    assert_NoContent(result)
  end

  # --- render hash shape ---

  def test_ok_result_is_renderable_by_rails
    result = Users::Create.call(params: { name: "Tad", email: "tad@example.com" })
    # Rails render expects :json and :status keys
    assert result.key?(:json)
    assert result.key?(:status)
  end
end
