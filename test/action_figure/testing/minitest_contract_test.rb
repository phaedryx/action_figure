# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"

class MinitestContractHelpersTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def build_action(&schema)
    Class.new do
      include ActionFigure[:jsend]

      params_schema(&schema)

      def call(params:) = Ok(resource: params)
    end
  end

  def test_assert_valid_params_passes_when_contract_succeeds
    action = build_action do
      required(:email).filled(:string)
    end

    assert_valid_params(action, { email: "jane@example.com" })
  end

  def test_assert_invalid_params_passes_when_contract_fails
    action = build_action do
      required(:email).filled(:string)
    end

    assert_invalid_params(action, { email: "" })
  end

  def test_assert_invalid_params_scoped_to_a_field_passes_when_that_field_errors
    action = build_action do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end

    assert_invalid_params(action, { name: "Jane" }, on: :email)
  end

  def test_assert_invalid_params_scoped_to_a_field_fails_when_a_different_field_errors
    action = build_action do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end

    # name is missing (so :name errors), but we assert the error is on :email
    error = assert_raises(Minitest::Assertion) do
      assert_invalid_params(action, { email: "jane@example.com" }, on: :email)
    end

    assert_includes error.message, ":email"
  end

  def test_assert_invalid_params_fails_when_params_are_valid
    action = build_action do
      required(:email).filled(:string)
    end

    error = assert_raises(Minitest::Assertion) do
      assert_invalid_params(action, { email: "jane@example.com" })
    end

    assert_includes error.message, "invalid"
  end

  def test_omitting_params_entirely_raises
    action = build_action do
      required(:email).filled(:string)
    end

    error = assert_raises(ArgumentError) { assert_invalid_params(action) }
    assert_match(/no params given/, error.message)

    assert_raises(ArgumentError) { assert_valid_params(action) }
  end

  def test_mixing_positional_params_with_keywords_raises
    action = build_action do
      required(:email).filled(:string)
    end

    error = assert_raises(ArgumentError) do
      assert_invalid_params(action, { email: "" }, om: :email)
    end

    assert_match(/:om/, error.message)
  end

  def test_contract_helpers_raise_for_actions_without_a_schema
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Ok(resource: {})
    end

    error = assert_raises(ArgumentError) { assert_valid_params(action, {}) }
    assert_includes error.message, "params_schema"
  end
end

class MinitestRequestSchemaContractHelpersTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def build_action
    Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:workspace_id).filled(:integer) }
        body  { required(:name).filled(:string) }
      end

      def create(request:) = Ok(resource: request.body.to_h)
    end
  end

  def test_assert_valid_params_validates_locations_against_their_contracts
    assert_valid_params(build_action, query: { workspace_id: "1" }, body: { name: "Roadmap" })
  end

  def test_assert_invalid_params_scopes_to_a_field_across_locations
    assert_invalid_params(build_action, query: { workspace_id: "1" }, body: { name: "" }, on: :name)
  end

  def test_omitted_locations_validate_as_empty_matching_runtime
    assert_invalid_params(build_action, body: { name: "Roadmap" }, on: :workspace_id)
  end

  def test_unknown_location_raises_with_declared_locations
    error = assert_raises(ArgumentError) do
      assert_valid_params(build_action, headers: { token: "x" })
    end

    assert_match(/unknown location/, error.message)
    assert_match(/:query, :body/, error.message)
  end

  def test_same_key_errors_in_two_locations_are_both_reported
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:limit).filled(:integer) }
        body  { required(:limit).filled(:string) }
      end

      def update(request:) = Ok(resource: request.body.to_h)
    end

    check = ActionFigure::Testing.check(action, query: { limit: "abc" }, body: {})

    refute check.success?
    assert_equal ["must be an integer", "is missing"], check.errors[:limit]
  end
end
