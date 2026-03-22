# frozen_string_literal: true

module ActionFigure
  # Base module for ActionFigure response formatters.
  # Include this in your formatter module to get a NoContent default
  # and to signal that your module implements the formatter interface.
  module Formatter
    REQUIRED_METHODS = %i[Ok Created Accepted UnprocessableContent NotFound Forbidden].freeze

    def NoContent
      { status: :no_content }
    end
  end
end
