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

      # params_schema actions take the params hash; request_schema actions take
      # locations as keywords: assert_valid_params(action, query: {...}, body: {...}).
      def assert_valid_params(action_class, params = nil, msg = nil, **locations)
        result = Testing.check(action_class, check_input(params, locations))
        message = msg || "Expected params to be valid, but got errors: #{result.errors.inspect}"
        assert result.success?, message
      end

      def assert_invalid_params(action_class, params = nil, on: nil, msg: nil, **locations)
        result = Testing.check(action_class, check_input(params, locations))

        if on.nil?
          message = msg || "Expected params to be invalid, but the contract accepted them"
          refute result.success?, message
        else
          errored = result.errors.key?(on)
          message = msg || "Expected params to be invalid on #{on.inspect}, " \
                           "but errors were: #{result.errors.inspect}"
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

      # A positional params hash and location keywords are mutually exclusive;
      # rejecting the mix here keeps typo'd keywords (om: for on:) from being
      # silently dropped, and rejecting neither keeps a forgotten params hash
      # from vacuously validating {}.
      def check_input(params, locations)
        if params && locations.any?
          raise ArgumentError,
                "pass either a params hash or location keywords, not both — " \
                "got both #{params.inspect} and #{locations.keys.map(&:inspect).join(", ")}"
        end
        return params if params

        if locations.empty?
          raise ArgumentError,
                "no params given — pass a params hash (params_schema) or " \
                "location keywords (request_schema)"
        end

        locations
      end

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
