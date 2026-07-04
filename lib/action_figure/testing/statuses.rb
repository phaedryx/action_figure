# frozen_string_literal: true

require "action_figure"

module ActionFigure
  # Helpers shared by the Minitest and RSpec testing adapters.
  module Testing
    # Success/no-body statuses with bespoke formatter bodies. These are not part of
    # the error registry (their bodies differ per outcome, not just per status).
    SUCCESS_STATUSES = {
      Ok: :ok,
      Created: :created,
      Accepted: :accepted,
      NoContent: :no_content
    }.freeze

    # Live full name→status map driving both adapters: success statuses plus
    # every error status registered so far (built-in and user-registered).
    # Each adapter iterates this at its own load time, so an adapter loaded
    # after a +register_error+ call still sees the full registry; registrations
    # made after an adapter loads are patched in via +define_error_helper+.
    def self.statuses
      SUCCESS_STATUSES.merge(ActionFigure.error_statuses)
    end

    # Resolves an action class's validation contract, raising a clear error when
    # the class declares no +params_schema+ (and therefore has no contract).
    def self.contract_for(action_class)
      contract = action_class.contract
      return contract if contract

      raise ArgumentError,
            "#{action_class} defines no params_schema, so it has no contract to validate against"
    end

    # Uniform contract-check result consumed by both adapters: +success?+ plus a
    # flat errors hash (merged across locations for request_schema actions).
    class Check
      attr_reader :errors

      def initialize(success:, errors:)
        @success = success
        @errors = errors
      end

      def success?
        @success
      end
    end

    # Validates +input+ against an action's schema, whichever kind it declares:
    # request_schema actions take locations ({query: {...}, body: {...}}, omitted
    # locations validating as empty — matching runtime); params_schema actions
    # take the params hash.
    def self.check(action_class, input)
      request_schema = action_class.respond_to?(:request_schema) && action_class.request_schema
      return check_locations(request_schema, input) if request_schema

      result = contract_for(action_class).call(input)
      Check.new(success: result.success?, errors: result.errors.to_h)
    end

    def self.check_locations(request_schema, locations_input)
      disallow_unknown_locations(request_schema, locations_input)

      results = request_schema.validate(locations_input)
      Check.new(success: results.each_value.all?(&:success?),
                errors: RequestSchema.merge_errors(results.values))
    end
    private_class_method :check_locations

    def self.disallow_unknown_locations(request_schema, locations_input)
      unknown = locations_input.keys - request_schema.contracts.keys
      return if unknown.empty?

      raise ArgumentError,
            "unknown location(s) #{unknown.map(&:inspect).join(", ")} — declared locations: " \
            "#{request_schema.contracts.keys.map(&:inspect).join(", ")}"
    end
    private_class_method :disallow_unknown_locations

    # Patches whichever adapters are loaded with one status's assertion/matcher.
    # Called by ActionFigure.register_error so a status registered after the
    # adapters have loaded still gets its assert_/refute_/be_ helpers.
    # +const_defined?(..., false)+ checks only this namespace — a bare
    # +defined?(Minitest)+ would find the top-level framework constant.
    def self.define_error_helper(name, status)
      Minitest.define_status_assertions(name, status) if const_defined?(:Minitest, false)
      RSpec.define_status_matcher(name, status) if const_defined?(:RSpec, false)
    end
  end
end
