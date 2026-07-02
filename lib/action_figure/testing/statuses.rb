# frozen_string_literal: true

require "action_figure"

module ActionFigure
  # Helpers shared by the Minitest and RSpec testing adapters.
  module Testing
    # Converts a helper name (+:UnprocessableContent+) to its Rack-style status
    # symbol (+:unprocessable_content+).
    def self.status_symbol(name)
      name.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
    end

    # Resolves an action class's validation contract, raising a clear error when
    # the class declares no +params_schema+ (and therefore has no contract).
    def self.contract_for(action_class)
      contract = action_class.contract
      return contract if contract

      raise ArgumentError,
            "#{action_class} defines no params_schema, so it has no contract to validate against"
    end

    # Single source of truth for the status-helper names exposed by the testing
    # adapters, mapping each helper name to the status symbol Rails uses in
    # +render+. Both the Minitest assertions (+assert_Ok+, +refute_Ok+, ...) and
    # the RSpec matchers (+be_Ok+, ...) are generated from this map so the two
    # adapters never drift.
    #
    # +NoContent+ lives on +Formatter+ rather than +Formatter::REQUIRED_METHODS+,
    # so it is added here explicitly.
    STATUSES = ActionFigure::Formatter::REQUIRED_METHODS
               .to_h { |name| [name, status_symbol(name)] }
               .merge(NoContent: :no_content)
               .freeze
  end
end
