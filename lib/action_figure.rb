# frozen_string_literal: true

require_relative "action_figure/version"
require_relative "action_figure/configuration"
require_relative "action_figure/format_registry"
require_relative "action_figure/formatter"
require_relative "action_figure/core"
require_relative "action_figure/formatters/jsend"
require_relative "action_figure/formatters/json_api"
require_relative "action_figure/formatters/default"
require_relative "action_figure/formatters/wrapped"

# ActionFigure provides explicit, purpose-driven operation classes for Rails controller actions.
module ActionFigure
  extend Configuration
  extend FormatRegistry

  class IndeterminantEntryPointError < StandardError; end

  register_formatter(jsend: Formatters::Jsend)
  register_formatter(jsonapi: Formatters::JsonApi)
  register_formatter(default: Formatters::Default)
  register_formatter(wrapped: Formatters::Wrapped)

  def self.[](format = configuration.format)
    format_modules.compute_if_absent(format) { build_format_module(format, fetch(format)) }
  end

  def self.included(base)
    base.include(self[])
  end

  def self.register_formatter(**formatters)
    formatters.each_value do |mod|
      missing = Formatter::REQUIRED_METHODS.reject { |m| mod.method_defined?(m) }
      raise ArgumentError, "#{mod} is missing formatter methods: #{missing.join(", ")}" if missing.any?
    end
    formatters.each_key { |name| clear_format_module_cache(name) }
    super
  end

  def self.clear_format_module_cache(name)
    format_modules.delete(name)
  end

  def self.build_format_module(name, formatter)
    mod = new_format_module(formatter)
    const_name = :"Format_#{name}"
    remove_const(const_name) if const_defined?(const_name, false)
    const_set(const_name, mod)
  end
  private_class_method :build_format_module

  def self.new_format_module(formatter)
    Module.new do
      def self.included(base)
        base.extend(ActionFigure::Core::ClassMethods)
        return unless defined?(ActiveSupport::Notifications) &&
                      ActionFigure.configuration.activesupport_notifications

        base.extend(ActionFigure::Core::Notifications)
      end

      include ActionFigure::Core
      include formatter
    end
  end
  private_class_method :new_format_module

  def self.format_modules
    @format_modules ||= Concurrent::Map.new
  end
  private_class_method :format_modules
end
