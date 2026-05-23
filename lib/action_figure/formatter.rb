# frozen_string_literal: true

module ActionFigure
  # Base module for ActionFigure response formatters.
  # Include this in your formatter module to get a NoContent default
  # and to signal that your module implements the formatter interface.
  module Formatter
    # Response helper names every formatter must define (+NoContent+ lives on +Formatter+, not required here).
    # Update every built-in formatter when you extend this list; +register_formatter+ validates against it at load time.
    REQUIRED_METHODS = %i[Ok Created Accepted UnprocessableContent NotFound Forbidden Conflict PaymentRequired].freeze

    def NoContent
      { status: :no_content }
    end
  end
end
