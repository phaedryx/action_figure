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

      def UnprocessableContent(errors:)
        { json: { status: "fail", data: errors }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { status: "fail", data: errors }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { status: "fail", data: errors }, status: :forbidden }
      end

      def Conflict(errors:)
        { json: { status: "fail", data: errors }, status: :conflict }
      end

      def PaymentRequired(errors:)
        { json: { status: "fail", data: errors }, status: :payment_required }
      end
    end
  end
end
