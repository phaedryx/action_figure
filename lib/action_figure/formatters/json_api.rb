# frozen_string_literal: true

require_relative "json_api/resource"

module ActionFigure
  module Formatters
    # Implements JSON:API response helpers for use in action classes.
    module JsonApi
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { data: Resource.serialize(resource) }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { data: Resource.serialize(resource) }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil)
        body = resource.nil? ? {} : { data: Resource.serialize(resource) }
        { json: body, status: :accepted }
      end

      def UnprocessableContent(errors:)
        { json: { errors: convert_errors(errors, "422") }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { errors: convert_errors(errors, "404") }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { errors: convert_errors(errors, "403") }, status: :forbidden }
      end

      private

      def convert_errors(errors, status)
        errors.flat_map do |field, messages|
          pointer = field.to_sym == :base ? "/data" : "/data/attributes/#{field}"
          messages.map do |message|
            {
              status: status,
              detail: message,
              source: { pointer: pointer }
            }
          end
        end
      end
    end
  end
end
