# frozen_string_literal: true

module ActionFigure
  # Provides formatter registration and lookup for ActionFigure.
  module FormatRegistry
    # Stores the mapping of format names to formatter modules.
    class Formats
      def initialize
        @formats = {}
      end

      def register_formatter(**formatters)
        @formats.merge!(formatters)
      end

      def fetch(name)
        @formats.fetch(name) do
          raise ArgumentError,
                "Unknown formatter: #{name}. Register it with ActionFigure.register_formatter(#{name}: MyFormatter)."
        end
      end
    end

    def register_formatter(**formatters)
      format_registry.register_formatter(**formatters)
    end

    def fetch(name)
      format_registry.fetch(name)
    end

    private

    def format_registry
      @format_registry ||= Formats.new
    end
  end
end
