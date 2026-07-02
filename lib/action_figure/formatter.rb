# frozen_string_literal: true

require_relative "error_registry"

module ActionFigure
  # Base module for ActionFigure response formatters.
  # Include this in your formatter module to get a NoContent default, the
  # generated named error helpers (NotFound, Conflict, and every registered
  # status), and to signal that your module implements the formatter interface.
  module Formatter
    include ErrorRegistry::Helpers

    # Structural methods every formatter must define: the three success helpers plus
    # the single error_response. Named error helpers are generated from
    # ActionFigure.error_statuses onto ErrorRegistry::Helpers (included here),
    # so they are NOT a per-formatter obligation.
    REQUIRED_METHODS = %i[Ok Created Accepted error_response].freeze

    def NoContent
      { status: :no_content }
    end
  end
end
