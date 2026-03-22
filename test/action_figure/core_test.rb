# frozen_string_literal: true

require "test_helper"

# --- Basic call ---

class CoreBasicCallTest < Minitest::Test
  def test_call_without_params_invokes_call_with_other_kwargs
    action = Class.new do
      include ActionFigure[:jsend]

      def call(current_user:)
        Ok(resource: { user: current_user })
      end
    end

    result = action.call(current_user: "alice")

    assert_equal "success", result[:json][:status]
    assert_equal({ user: "alice" }, result[:json][:data])
  end

  def test_non_params_kwargs_pass_through_to_call_untouched
    action = Class.new do
      include ActionFigure[:jsend]

      def call(current_user:, company:)
        Ok(resource: { current_user:, company: })
      end
    end

    result = action.call(current_user: "alice", company: "Acme")

    assert_equal({ current_user: "alice", company: "Acme" }, result[:json][:data])
  end
end

# --- Params schema ---

class CoreParamsSchemaTest < Minitest::Test
  def test_params_are_coerced_before_call
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:age).filled(:integer)
      end

      def call(params:)
        Ok(resource: { age: params[:age] })
      end
    end

    result = action.call(params: { age: "25" })

    assert_equal 25, result[:json][:data][:age]
  end

  def test_validation_failure_returns_unprocessable_content_with_errors
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { name: "" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:name], "must be filled"
  end

  def test_validation_failure_does_not_invoke_call
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(*)
        raise "should not be called"
      end
    end

    result = action.call(params: { name: "" })

    assert_equal :unprocessable_content, result[:status]
  end

  def test_extra_params_are_stripped_by_default
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.call(params: { name: "Tad", extra: "ignored" })

    refute result[:json][:data].key?(:extra)
  end

  def test_passing_params_without_schema_raises_at_call_time
    action = Class.new do
      include ActionFigure[:jsend]

      def call(*)
        Ok(resource: {})
      end
    end

    assert_raises(ArgumentError) do
      action.call(params: { name: "Tad" })
    end
  end
end

# --- Rules ---

class CoreRulesTest < Minitest::Test
  def test_rule_failure_returns_unprocessable_content_with_error_on_field
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
      end

      rules do
        rule(:email) { key.failure("is invalid") unless values[:email].include?("@") }
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { email: "not-an-email" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:email], "is invalid"
  end

  def test_rules_without_params_schema_raises_at_class_load
    assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        rules do
          rule(:email) { key.failure("is invalid") }
        end
      end
    end
  end
end

# --- whiny_extra_params ---

class CoreWhinyExtraParamsTest < Minitest::Test
  def test_whiny_extra_params_rejects_undeclared_params
    original = ActionFigure.configuration.whiny_extra_params
    ActionFigure.configuration.whiny_extra_params = true

    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { name: "Tad", extra: "surprise" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:extra], "is not allowed"
  ensure
    ActionFigure.configuration.whiny_extra_params = original
  end
end

# --- Custom entry points ---

class CoreEntryPointTest < Minitest::Test
  def test_custom_entry_point_defines_class_method
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :search

      def search
        Ok(resource: [])
      end
    end

    result = action.search

    assert_equal "success", result[:json][:status]
  end

  def test_call_raises_when_custom_entry_point_declared
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :search

      def search
        Ok(resource: [])
      end
    end

    assert_raises(NoMethodError) do
      action.call
    end
  end

  def test_entry_point_raises_when_defined_twice
    assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        entry_point :search
        entry_point :find
      end
    end
  end

  def test_custom_entry_point_runs_validation_pipeline
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :search

      params_schema do
        required(:query).filled(:string)
      end

      def search(params:)
        Ok(resource: { query: params[:query] })
      end
    end

    result = action.search(params: { query: "hello" })

    assert_equal({ query: "hello" }, result[:json][:data])
  end

  def test_custom_entry_point_without_params_skips_validation
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :destroy

      def destroy(*)
        NoContent()
      end
    end

    result = action.destroy(current_user: "alice")

    assert_equal :no_content, result[:status]
  end
end

# --- Cross-param rule helpers ---

class CoreCrossParamRulesTest < Minitest::Test
  def test_exclusive_rule_fails_when_both_params_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:username).filled(:string)
        optional(:email).filled(:string)
      end

      rules do
        exclusive_rule(:username, :email, "can't provide both")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { username: "tad", email: "tad@example.com" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:username], "can't provide both"
    assert_includes result[:json][:data][:email], "can't provide both"
  end

  def test_exclusive_rule_passes_when_only_one_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:username).filled(:string)
        optional(:email).filled(:string)
      end

      rules do
        exclusive_rule(:username, :email, "can't provide both")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { username: "tad" })

    assert_equal :ok, result[:status]
  end

  def test_any_rule_fails_when_none_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:phone).filled(:string)
        optional(:email).filled(:string)
      end

      rules do
        any_rule(:phone, :email, "must provide at least one contact method")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: {})

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:phone], "must provide at least one contact method"
    assert_includes result[:json][:data][:email], "must provide at least one contact method"
  end

  def test_any_rule_passes_when_at_least_one_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:phone).filled(:string)
        optional(:email).filled(:string)
      end

      rules do
        any_rule(:phone, :email, "must provide at least one contact method")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { email: "tad@example.com" })

    assert_equal :ok, result[:status]
  end

  def test_one_rule_fails_when_both_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:bank_account).filled(:string)
      end

      rules do
        one_rule(:credit_card, :bank_account, "choose exactly one payment method")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { credit_card: "4111...", bank_account: "123456" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:credit_card], "choose exactly one payment method"
    assert_includes result[:json][:data][:bank_account], "choose exactly one payment method"
  end

  def test_one_rule_fails_when_none_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:bank_account).filled(:string)
      end

      rules do
        one_rule(:credit_card, :bank_account, "choose exactly one payment method")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: {})

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:credit_card], "choose exactly one payment method"
    assert_includes result[:json][:data][:bank_account], "choose exactly one payment method"
  end

  def test_one_rule_passes_when_exactly_one_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:bank_account).filled(:string)
      end

      rules do
        one_rule(:credit_card, :bank_account, "choose exactly one payment method")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { credit_card: "4111..." })

    assert_equal :ok, result[:status]
  end

  def test_all_rule_fails_when_only_some_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:street).filled(:string)
        optional(:city).filled(:string)
        optional(:zip).filled(:string)
      end

      rules do
        all_rule(:street, :city, :zip, "address fields must all be present or all absent")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { street: "123 Main St", city: "Springfield" })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:street], "address fields must all be present or all absent"
    assert_includes result[:json][:data][:city], "address fields must all be present or all absent"
    assert_includes result[:json][:data][:zip], "address fields must all be present or all absent"
  end

  def test_all_rule_passes_when_all_absent
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:street).filled(:string)
        optional(:city).filled(:string)
        optional(:zip).filled(:string)
      end

      rules do
        all_rule(:street, :city, :zip, "address fields must all be present or all absent")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: {})

    assert_equal :ok, result[:status]
  end

  def test_all_rule_passes_when_all_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:street).filled(:string)
        optional(:city).filled(:string)
        optional(:zip).filled(:string)
      end

      rules do
        all_rule(:street, :city, :zip, "address fields must all be present or all absent")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { street: "123 Main St", city: "Springfield", zip: "62701" })

    assert_equal :ok, result[:status]
  end

  def test_implies_rule_fails_when_antecedent_present_but_consequent_absent
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:billing_address).filled(:string)
      end

      rules do
        implies_rule(:credit_card, :billing_address, "credit card requires a billing address")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { credit_card: "4111..." })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:credit_card], "credit card requires a billing address"
    assert_includes result[:json][:data][:billing_address], "credit card requires a billing address"
  end

  def test_implies_rule_passes_when_antecedent_absent
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:billing_address).filled(:string)
      end

      rules do
        implies_rule(:credit_card, :billing_address, "credit card requires a billing address")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: {})

    assert_equal :ok, result[:status]
  end

  def test_implies_rule_passes_when_both_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:credit_card).filled(:string)
        optional(:billing_address).filled(:string)
      end

      rules do
        implies_rule(:credit_card, :billing_address, "credit card requires a billing address")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { credit_card: "4111...", billing_address: "123 Main St" })

    assert_equal :ok, result[:status]
  end

  def test_exclusive_rule_treats_boolean_false_as_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:flag_a).filled(:bool)
        optional(:flag_b).filled(:bool)
      end

      rules do
        exclusive_rule(:flag_a, :flag_b, "can't provide both")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { flag_a: false, flag_b: false })

    assert_equal :unprocessable_content, result[:status]
    assert_includes result[:json][:data][:flag_a], "can't provide both"
    assert_includes result[:json][:data][:flag_b], "can't provide both"
  end

  def test_any_rule_treats_boolean_false_as_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:flag_a).filled(:bool)
        optional(:flag_b).filled(:bool)
      end

      rules do
        any_rule(:flag_a, :flag_b, "must provide at least one")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { flag_a: false })

    assert_equal :ok, result[:status]
  end

  def test_one_rule_treats_boolean_false_as_present
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:flag_a).filled(:bool)
        optional(:flag_b).filled(:bool)
      end

      rules do
        one_rule(:flag_a, :flag_b, "choose exactly one")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { flag_a: false, flag_b: false })

    assert_equal :unprocessable_content, result[:status]
    assert_includes result[:json][:data][:flag_a], "choose exactly one"
  end

  def test_implies_rule_fires_when_antecedent_is_false
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        optional(:notify).filled(:bool)
        optional(:email).filled(:string)
      end

      rules do
        implies_rule(:notify, :email, "notify requires an email address")
      end

      def call(*)
        Ok(resource: {})
      end
    end

    # false is present (non-nil), so the implication fires — email is required
    result = action.call(params: { notify: false })

    assert_equal :unprocessable_content, result[:status]
    assert_includes result[:json][:data][:notify], "notify requires an email address"
  end
end

# --- bare include ActionFigure ---

class CoreBareIncludeTest < Minitest::Test
  def test_bare_include_uses_configured_default_format
    action = Class.new do
      include ActionFigure

      params_schema do
        required(:name).filled(:string)
      end

      def call(params:)
        Ok(resource: { name: params[:name] })
      end
    end

    result = action.call(params: { name: "Tad" })

    assert_equal :ok, result[:status]
    assert_equal "success", result[:json][:status]
    assert_equal "Tad", result[:json][:data][:name]
  end
end

# --- register_formatter cache ---

class CoreRegisterFormatterTest < Minitest::Test
  def test_re_registering_formatter_is_reflected_in_subsequent_calls
    # Force the cache to be populated first so re-registration must clear it
    ActionFigure[:jsend]

    custom_formatter = Module.new do
      def Ok(resource:, **) = { json: { custom: true, data: resource }, status: :ok }
    end

    ActionFigure.register_formatter(jsend: custom_formatter)

    action = Class.new do
      include ActionFigure[:jsend]

      def call(current_user:)
        Ok(resource: { user: current_user })
      end
    end

    result = action.call(current_user: "alice")

    assert result[:json][:custom]
  ensure
    ActionFigure.register_formatter(jsend: ActionFigure::Formatters::Jsend)
    ActionFigure.clear_format_module_cache(:jsend)
  end
end
