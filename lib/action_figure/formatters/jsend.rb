# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements JSend response helpers for use in action classes.
    module Jsend
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

      def Accepted(resource: nil)
        body = { status: "success" }
        body[:data] = resource unless resource.nil?
        { json: body, status: :accepted }
      end

      def NoContent
        { status: :no_content }
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
    end
  end
end
