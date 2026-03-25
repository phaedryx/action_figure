# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements uniform envelope response helpers for use in action classes.
    # Every response uses the same { data:, error:, status: } shape.
    module Wrapped
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { data: resource, error: nil, status: "success" }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { data: resource, error: nil, status: "success" }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil)
        { json: { data: resource, error: nil, status: "success" }, status: :accepted }
      end

      def UnprocessableContent(errors:)
        { json: { data: nil, error: errors, status: "error" }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { data: nil, error: errors, status: "error" }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { data: nil, error: errors, status: "error" }, status: :forbidden }
      end
    end
  end
end
