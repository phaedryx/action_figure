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

      def Accepted(resource: nil, meta: nil)
        body = resource.nil? ? {} : { data: Resource.serialize(resource) }
        body[:meta] = meta if meta
        { json: body, status: :accepted }
      end

      def error_response(errors:, status:)
        code = ActionFigure.status_code_for(status).to_s
        { json: { errors: convert_errors(errors, code) }, status: status }
      end

      private

      def convert_errors(errors, status, prefix = "/data/attributes")
        errors.flat_map do |field, messages|
          pointer = field.to_sym == :base ? "/data" : "#{prefix}/#{field}"

          if messages.is_a?(Hash)
            convert_errors(messages, status, pointer)
          else
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
end
