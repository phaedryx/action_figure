# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements uniform envelope response helpers for use in action classes.
    # Every response uses the same { data:, errors:, status: } shape.
    module Wrapped
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { data: resource, errors: nil, status: "success" }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { data: resource, errors: nil, status: "success" }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil, meta: nil)
        body = { data: resource, errors: nil, status: "success" }
        body[:meta] = meta if meta
        { json: body, status: :accepted }
      end

      def error_response(errors:, status:)
        { json: { data: nil, errors: errors, status: "error" }, status: status }
      end
    end
  end
end
