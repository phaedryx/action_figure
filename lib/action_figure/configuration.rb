# frozen_string_literal: true

module ActionFigure
  # Provides global configuration for ActionFigure via ActionFigure.configure.
  module Configuration
    # Holds ActionFigure configuration values.
    class Settings
      attr_accessor :format, :whiny_extra_params, :api_version

      def initialize
        @format = :default
        @whiny_extra_params = false
      end

      def configure
        yield self
      end

      def register(**formatters)
        ActionFigure.register_formatter(**formatters)
      end
    end

    def configure(&)
      configuration.configure(&)
    end

    def configuration
      @configuration ||= Settings.new
    end
  end
end
