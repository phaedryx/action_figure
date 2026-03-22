# frozen_string_literal: true

require_relative "action_figure/version"
require_relative "action_figure/configuration"
require_relative "action_figure/format_registry"
require_relative "action_figure/core"
require_relative "action_figure/formatters/jsend"

# ActionFigure provides explicit, purpose-driven operation classes for Rails controller actions.
module ActionFigure
  extend Configuration
  extend FormatRegistry

  def self.[](format = configuration.format)
    @format_modules ||= {}
    @format_modules[format] ||= build_format_module(fetch(format))
  end

  def self.included(base)
    base.include(self[])
  end

  def self.register_formatter(**formatters)
    formatters.each_key { |name| clear_format_module_cache(name) }
    super
  end

  def self.clear_format_module_cache(name)
    @format_modules&.delete(name)
  end

  def self.build_format_module(formatter)
    Module.new do
      def self.included(base)
        base.extend(ActionFigure::Core::ClassMethods)
      end

      include ActionFigure::Core
      include formatter
    end
  end
  private_class_method :build_format_module

  register_formatter(jsend: Formatters::Jsend)
end
