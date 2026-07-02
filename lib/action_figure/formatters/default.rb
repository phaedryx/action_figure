# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements Rails-style response helpers for use in action classes.
    # Success responses use a { data: } envelope; errors live under an "errors" key on failure.
    module Default
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { data: resource }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { data: resource }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil, meta: nil)
        body = { data: resource }
        body[:meta] = meta if meta
        { json: body, status: :accepted }
      end

      def error_response(errors:, status:)
        { json: { errors: errors }, status: status }
      end
    end
  end
end
