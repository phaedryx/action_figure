# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements JSend response helpers for use in action classes.
    module Jsend
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { status: "success", data: resource }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { status: "success", data: resource }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil, meta: nil)
        body = { status: "success" }
        body[:data] = resource unless resource.nil?
        body[:meta] = meta if meta
        { json: body, status: :accepted }
      end

      def error_response(errors:, status:)
        { json: { status: "fail", data: errors }, status: status }
      end
    end
  end
end
