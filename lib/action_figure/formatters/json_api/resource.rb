# frozen_string_literal: true

module ActionFigure
  module Formatters
    module JsonApi
      # Simple resource serialization
      class Resource
        def self.serialize(resource)
          if resource.is_a?(Hash)
            resource
          elsif resource.respond_to?(:attributes)
            serialize_one(resource)
          elsif resource.respond_to?(:each)
            resource.map { |r| serialize(r) }
          else # rubocop:disable Lint/DuplicateBranch
            resource
          end
        end

        def self.serialize_one(resource)
          {
            type: resource.class.model_name.element,
            id: resource.id.to_s,
            attributes: resource.attributes.except("id")
          }
        end

        private_class_method :serialize_one
      end
    end
  end
end
