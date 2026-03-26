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

      def UnprocessableContent(errors:)
        { json: { errors: errors }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { errors: errors }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { errors: errors }, status: :forbidden }
      end
    end
  end
end
