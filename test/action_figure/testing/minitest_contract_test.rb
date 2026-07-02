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

  def test_contract_helpers_raise_for_actions_without_a_schema
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Ok(resource: {})
    end

    error = assert_raises(ArgumentError) { assert_valid_params(action, {}) }
    assert_includes error.message, "params_schema"
  end
end
