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

  def test_nested_params_are_validated_and_coerced
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:user).hash do
          required(:name).filled(:string)
          required(:email).filled(:string)
        end
      end

      def call(params:)
        Ok(resource: params[:user])
      end
    end

    result = action.call(params: { user: { name: "Tad", email: "tad@example.com" } })

    assert_equal :ok, result[:status]
    assert_equal({ name: "Tad", email: "tad@example.com" }, result[:json][:data])
  end

  def test_nested_params_validation_failure_returns_errors
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:user).hash do
          required(:name).filled(:string)
          required(:email).filled(:string)
        end
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { user: { name: "Tad" } })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:user][:email], "is missing"
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

  def test_params_with_to_unsafe_h_are_unwrapped_before_validation
    # Simulate ActionController::Parameters which responds to to_unsafe_h
    fake_params = Class.new do
      def initialize(hash)
        @hash = hash
      end

      def to_unsafe_h
        @hash
      end
    end

    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.call(params: fake_params.new({ name: "Tad" }))

    assert_equal :ok, result[:status]
    assert_equal "Tad", result[:json][:data][:name]
  end

  def test_params_pass_through_without_schema
    action = Class.new do
      include ActionFigure[:jsend]

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.call(params: { name: "Tad" })

    assert_equal :ok, result[:status]
    assert_equal({ name: "Tad" }, result[:json][:data])
  end

  def test_params_with_to_unsafe_h_are_unwrapped_without_schema
    fake_params = Class.new do
      def initialize(hash) = @hash = hash
      def to_unsafe_h = @hash
    end

    action = Class.new do
      include ActionFigure[:jsend]

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.call(params: fake_params.new({ name: "Tad" }))

    assert_equal :ok, result[:status]
    assert_equal({ name: "Tad" }, result[:json][:data])
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

  def test_redefining_params_schema_after_rules_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        params_schema do
          required(:name).filled(:string)
        end

        rules do
          rule(:name) { key.failure("too short") if values[:name].length < 2 }
        end

        params_schema do
          required(:email).filled(:string)
        end
      end
    end

    assert_match(/silently drop/, error.message)
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

  def test_whiny_extra_params_rejects_nested_undeclared_params
    original = ActionFigure.configuration.whiny_extra_params
    ActionFigure.configuration.whiny_extra_params = true

    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:user).hash do
          required(:name).filled(:string)
        end
      end

      def call(*)
        Ok(resource: {})
      end
    end

    result = action.call(params: { user: { name: "Tad", extra: "surprise" } })

    assert_equal :unprocessable_content, result[:status]
    assert_includes result[:json][:data][:"user.extra"], "is not allowed"
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

# --- Entry point discovery ---

class CoreEntryPointDiscoveryTest < Minitest::Test
  def test_auto_discovers_single_public_method
    action = Class.new do
      include ActionFigure[:jsend]

      def create(params:)
        Created(resource: params)
      end
    end

    result = action.create(params: { name: "Tad" })

    assert_equal :created, result[:status]
    assert_equal({ name: "Tad" }, result[:json][:data])
  end

  def test_sets_entry_point_name_to_discovered_method
    action = Class.new do
      include ActionFigure[:jsend]

      def create(params:)
        Created(resource: params)
      end
    end

    assert_equal :create, action.entry_point_name
  end

  def test_private_methods_are_ignored_by_discovery
    action = Class.new do
      include ActionFigure[:jsend]

      def create(params:)
        Created(resource: format_response(params))
      end

      private

      def format_response(params)
        params.transform_keys(&:to_s)
      end
    end

    result = action.create(params: { name: "Tad" })

    assert_equal :created, result[:status]
  end

  def test_included_module_methods_are_ignored_by_discovery
    helper = Module.new do
      def format_response(data)
        data.transform_keys(&:to_s)
      end
    end

    action = Class.new do
      include ActionFigure[:jsend]
      include helper

      def create(params:)
        Created(resource: format_response(params))
      end
    end

    result = action.create(params: { name: "Tad" })

    assert_equal :created, result[:status]
  end

  def test_raises_indeterminant_entry_point_error_for_second_public_method
    error = assert_raises(ActionFigure::IndeterminantEntryPointError) do
      Class.new do
        include ActionFigure[:jsend]

        def create(params:)
          Created(resource: params)
        end

        def update(params:)
          Ok(resource: params)
        end
      end
    end

    assert_match(/create/, error.message)
    assert_match(/update/, error.message)
    assert_match(/entry_point/, error.message)
  end

  def test_explicit_entry_point_suppresses_discovery
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :search

      def search(params:)
        Ok(resource: params)
      end

      def format_results(data)
        data
      end
    end

    result = action.search(params: { q: "ruby" })

    assert_equal :ok, result[:status]
    assert_equal :search, action.entry_point_name
  end

  def test_discovered_entry_point_runs_validation_pipeline
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def create(params:)
        Created(resource: params)
      end
    end

    valid_result = action.create(params: { name: "Tad" })

    assert_equal :created, valid_result[:status]

    invalid_result = action.create(params: { name: "" })

    assert_equal :unprocessable_content, invalid_result[:status]
    assert_equal "fail", invalid_result[:json][:status]
    assert_includes invalid_result[:json][:data][:name], "must be filled"
  end

  def test_class_does_not_respond_to_call_unless_method_is_named_call
    action = Class.new do
      include ActionFigure[:jsend]

      def create(params:)
        Created(resource: params)
      end
    end

    refute action.respond_to?(:call)
    assert action.respond_to?(:create)
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
    assert_equal "Tad", result[:json][:data][:name]
  end
end

# --- register_formatter cache ---

class CoreRegisterFormatterTest < Minitest::Test
  def test_re_registering_formatter_is_reflected_in_subsequent_calls
    ActionFigure[:jsend] # populate cache

    custom_formatter = Module.new do
      ActionFigure::Formatter::REQUIRED_METHODS.each do |m|
        define_method(m) { |**| { json: { custom: true }, status: :ok } }
      end
      def NoContent = { status: :no_content }
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

# --- api_version macro ---

class CoreApiVersionTest < Minitest::Test
  def test_api_version_returns_nil_by_default
    action = Class.new { include ActionFigure[:jsend] }

    assert_nil action.api_version
  end

  def test_api_version_setter_stores_value
    action = Class.new do
      include ActionFigure[:jsend]

      api_version "2.0"
    end

    assert_equal "2.0", action.api_version
  end

  def test_api_version_is_independent_between_classes
    action_a = Class.new do
      include ActionFigure[:jsend]

      api_version "1.0"
    end

    action_b = Class.new do
      include ActionFigure[:jsend]

      api_version "2.0"
    end

    assert_equal "1.0", action_a.api_version
    assert_equal "2.0", action_b.api_version
  end

  def test_api_version_accessible_from_formatter_instance
    action = Class.new do
      include ActionFigure[:jsend]

      api_version "3.0"

      def call
        Ok(resource: { version: self.class.api_version })
      end
    end

    result = action.call
    assert_equal "3.0", result[:json][:data][:version]
  end
end

# --- .contract introspection ---

class CoreContractTest < Minitest::Test
  def test_contract_returns_a_dry_validation_contract
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    assert_kind_of Dry::Validation::Contract, action.contract
  end

  def test_contract_returns_nil_without_params_schema
    action = Class.new do
      include ActionFigure[:jsend]

      def call
        Ok(resource: {})
      end
    end

    assert_nil action.contract
  end

  def test_contract_validates_input_without_executing_call
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
      end

      def call(*)
        raise "should not be called"
      end
    end

    result = action.contract.call(name: "Jane")

    assert result.failure?
    assert_includes result.errors.to_h[:email], "is missing"
  end

  def test_contract_returns_validated_params_on_success
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.contract.call(email: "jane@example.com", name: "Jane")

    assert result.success?
    assert_equal({ email: "jane@example.com", name: "Jane" }, result.to_h)
  end

  def test_contract_schema_exposes_declared_keys
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
        optional(:age).filled(:integer)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    keys = action.contract.schema.key_map.map(&:name)

    assert_includes keys, "email"
    assert_includes keys, "name"
    assert_includes keys, "age"
    assert_equal 3, keys.length
  end

  def test_contract_rules_exposes_declared_rules
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
      end

      rules do
        rule(:email) { key.failure("must include @") unless values[:email].include?("@") }
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    rule_keys = action.contract.rules.map(&:keys)

    assert_includes rule_keys, [:email]
  end

  def test_contract_runs_rules_not_just_schema
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
      end

      rules do
        rule(:email) { key.failure("must include @") unless values[:email].include?("@") }
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    result = action.contract.call(email: "not-an-email")

    assert result.failure?
    assert_includes result.errors.to_h[:email], "must include @"
  end

  def test_contract_rules_is_empty_without_rules_block
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:name).filled(:string)
      end

      def call(params:)
        Ok(resource: params)
      end
    end

    assert_empty action.contract.rules
  end
end

# --- CRUD with model errors ---

# Subclass with its own validations — avoids mutating the shared User class
class ValidatedUser < User
  self.table_name = "users"
  validates :email, presence: true
end

class CoreCrudWithModelErrorsTest < Minitest::Test
  def setup
    User.delete_all
  end

  def test_create_returns_created_with_valid_params
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:user).hash do
          required(:name).filled(:string)
          required(:email).filled(:string)
        end
      end

      def call(params:)
        user = ValidatedUser.create(params[:user])
        return UnprocessableContent(errors: user.errors.messages) unless user.persisted?

        Created(resource: user.as_json(only: %i[id name email]))
      end
    end

    result = action.call(params: { user: { name: "Tad", email: "tad@example.com" } })

    assert_equal :created, result[:status]
    assert_equal "Tad", result[:json][:data]["name"]
    assert_equal "tad@example.com", result[:json][:data]["email"]
  end

  def test_create_returns_unprocessable_content_with_model_errors
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:user).hash do
          required(:name).filled(:string)
          optional(:email).maybe(:string)
        end
      end

      def call(params:)
        user = ValidatedUser.create(params[:user])
        return UnprocessableContent(errors: user.errors.messages) unless user.persisted?

        Created(resource: user.as_json(only: %i[id name email]))
      end
    end

    result = action.call(params: { user: { name: "Tad" } })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:email], "can't be blank"
  end

  def test_update_returns_ok_with_valid_params
    user = ValidatedUser.create!(name: "Tad", email: "tad@example.com")

    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
        required(:user).hash do
          optional(:name).filled(:string)
          optional(:email).filled(:string)
        end
      end

      def call(params:)
        user = ValidatedUser.find_by(id: params[:id])
        return NotFound(errors: { base: ["user not found"] }) unless user

        user.update(params[:user])
        return UnprocessableContent(errors: user.errors.messages) unless user.errors.empty?

        Ok(resource: user.as_json(only: %i[id name email]))
      end
    end

    result = action.call(params: { id: user.id, user: { name: "Bob" } })

    assert_equal :ok, result[:status]
    assert_equal "Bob", result[:json][:data]["name"]
  end

  def test_update_returns_unprocessable_content_with_model_errors
    user = ValidatedUser.create!(name: "Tad", email: "tad@example.com")

    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
        required(:user).hash do
          optional(:name).filled(:string)
          optional(:email).maybe(:string)
        end
      end

      def call(params:)
        user = ValidatedUser.find_by(id: params[:id])
        return NotFound(errors: { base: ["user not found"] }) unless user

        user.update(params[:user])
        return UnprocessableContent(errors: user.errors.messages) unless user.errors.empty?

        Ok(resource: user.as_json(only: %i[id name email]))
      end
    end

    result = action.call(params: { id: user.id, user: { email: nil } })

    assert_equal :unprocessable_content, result[:status]
    assert_equal "fail", result[:json][:status]
    assert_includes result[:json][:data][:email], "can't be blank"
  end

  def test_update_returns_not_found_for_missing_record
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
        required(:user).hash do
          optional(:name).filled(:string)
        end
      end

      def call(params:)
        user = User.find_by(id: params[:id])
        return NotFound(errors: { base: ["user not found"] }) unless user

        user.update(params[:user])
        return UnprocessableContent(errors: user.errors.messages) unless user.errors.empty?

        Ok(resource: user.as_json(only: %i[id name email]))
      end
    end

    result = action.call(params: { id: 999999, user: { name: "Ghost" } })

    assert_equal :not_found, result[:status]
    assert_includes result[:json][:data][:base], "user not found"
  end
end
