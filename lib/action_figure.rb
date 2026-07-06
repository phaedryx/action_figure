# frozen_string_literal: true

require_relative "action_figure/version"
require_relative "action_figure/configuration"
require_relative "action_figure/format_registry"
require_relative "action_figure/error_registry"
require_relative "action_figure/formatter"
require_relative "action_figure/request_schema"
require_relative "action_figure/core"
require_relative "action_figure/formatters/jsend"
require_relative "action_figure/formatters/json_api"
require_relative "action_figure/formatters/default"
require_relative "action_figure/formatters/wrapped"
require_relative "action_figure/formatters/rfc_9457"

# ActionFigure provides explicit, purpose-driven operation classes for Rails controller actions.
module ActionFigure
  @format_modules = Concurrent::Map.new

  extend Configuration
  extend FormatRegistry
  extend ErrorRegistry

  class IndeterminateEntryPointError < StandardError; end

  # Raised when an action class defines +initialize+. ActionFigure builds instances with
  # +new+ and passes no constructor arguments; use keyword arguments on the entry method
  # or class-level state instead of custom initializers.
  class InitializationNotSupportedError < StandardError; end

  register_formatter(jsend: Formatters::Jsend)
  register_formatter(jsonapi: Formatters::JsonApi)
  register_formatter(default: Formatters::Default)
  register_formatter(wrapped: Formatters::Wrapped)
  register_formatter(rfc_9457: Formatters::Rfc9457) # rubocop:disable Naming/VariableNumber

  # Duck-type stand-in for a Rails (ActionDispatch) request, for invoking request_schema
  # actions from tests and consoles: ActionFigure.request(path: {...}, body: {...}).
  RequestStub = Data.define(:path_parameters, :query_parameters, :request_parameters)

  def self.request(path: {}, query: {}, body: {})
    RequestStub.new(path_parameters: path, query_parameters: query, request_parameters: body)
  end

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
    @format_modules
  end
  private_class_method :format_modules
end
