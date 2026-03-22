# frozen_string_literal: true

module ActionFigure
  # Provides global configuration for ActionFigure via ActionFigure.configure.
  module Configuration
    # Holds ActionFigure configuration values.
    class Settings
      attr_accessor :format, :whiny_extra_params

      def initialize
        @format = :jsend
        @whiny_extra_params = false
      end

      def configure
        yield self
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
