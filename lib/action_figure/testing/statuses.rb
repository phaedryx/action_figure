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
