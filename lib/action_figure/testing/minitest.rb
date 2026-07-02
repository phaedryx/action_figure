# frozen_string_literal: true

require_relative "statuses"

module ActionFigure
  module Testing
    # Minitest assertions for ActionFigure response results.
    #
    # Include in your test class to get assert_Ok, assert_Created, etc.
    # (and the negated refute_Ok, refute_Created, ...):
    #
    #   class Users::CreateTest < Minitest::Test
    #     include ActionFigure::Testing::Minitest
    #   end
    #
    # The status helpers are generated from ActionFigure::Testing.statuses so the
    # Minitest and RSpec adapters never drift.
    module Minitest
      def self.define_status_assertions(name, status)
        define_method(:"assert_#{name}") do |result, msg = nil|
          assert_status(status, result, msg)
        end

        define_method(:"refute_#{name}") do |result, msg = nil|
          refute_status(status, result, msg)
        end
      end

      Testing.statuses.each { |name, status| define_status_assertions(name, status) }

      def assert_valid_params(action_class, params, msg = nil)
        result = action_contract(action_class).call(params)
        message = msg || "Expected params to be valid, but got errors: #{result.errors.to_h.inspect}"
        assert result.success?, message
      end

      def assert_invalid_params(action_class, params, on: nil, msg: nil)
        result = action_contract(action_class).call(params)

        if on.nil?
          message = msg || "Expected params to be invalid, but the contract accepted them"
          assert result.failure?, message
        else
          errored = result.errors.to_h.key?(on)
          message = msg || "Expected params to be invalid on #{on.inspect}, " \
                           "but errors were: #{result.errors.to_h.inspect}"
          assert errored, message
        end
      end

      # Asserts +result[:json]+ contains the given fragment as a (possibly nested) subset.
      # Mirrors the RSpec +have_action_json+ matcher: nested Hashes match as subsets and
      # Regexp values match against strings.
      #
      #   assert_action_json(result, status: "success", data: { name: "Jane" })
      def assert_action_json(result, fragment, msg = nil)
        flunk(msg || "Expected an ActionFigure result hash, got #{result.inspect}") unless result.is_a?(Hash)
        unless result.key?(:json)
          flunk(msg || "Expected #{result.inspect} to include key :json (ActionFigure render hash)")
        end

        message = msg || "Expected result[:json] to include #{fragment.inspect}, got #{result[:json].inspect}"
        assert json_subset?(result[:json], fragment), message
      end

      def refute_action_json(result, fragment, msg = nil)
        json = result.is_a?(Hash) ? result[:json] : nil
        message = msg || "Expected result[:json] not to include #{fragment.inspect}"
        refute(json.is_a?(Hash) && json_subset?(json, fragment), message)
      end

      private

      def json_subset?(actual, expected)
        return false unless actual.is_a?(Hash)

        expected.all? do |key, value|
          actual.key?(key) && json_value_match?(actual[key], value)
        end
      end

      def json_value_match?(actual, expected)
        case expected
        when Hash then json_subset?(actual, expected)
        when Regexp then expected.match?(actual.to_s)
        else actual == expected
        end
      end

      def action_contract(action_class)
        ActionFigure::Testing.contract_for(action_class)
      end

      def assert_status(expected, result, msg)
        flunk(msg || "Expected an ActionFigure result hash, got #{result.inspect}") unless result.is_a?(Hash)

        actual = result[:status]
        message = msg || "Expected result status to be #{expected.inspect}, but got #{actual.inspect}"
        assert actual == expected, message
      end

      def refute_status(expected, result, msg)
        flunk(msg || "Expected an ActionFigure result hash, got #{result.inspect}") unless result.is_a?(Hash)

        actual = result[:status]
        message = msg || "Expected result status not to be #{expected.inspect}"
        refute actual == expected, message
      end
    end
  end
end
