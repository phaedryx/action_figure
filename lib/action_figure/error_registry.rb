# frozen_string_literal: true

require "concurrent/map"
require "rack/utils"

module ActionFigure
  # Central registry mapping error-helper names (e.g. +:NotFound+) to the Rack
  # status symbol they render (e.g. +:not_found+). Single source of truth for
  # formatter error helpers and the Minitest/RSpec status assertions.
  #
  # Extended into ActionFigure, so the public API is ActionFigure.error_statuses
  # and ActionFigure.register_error.
  module ErrorRegistry
    # Built-in error statuses. Domain-owned 4xx only — no 5xx ships built-in.
    DEFAULTS = {
      UnprocessableContent: :unprocessable_content,
      NotFound: :not_found,
      Forbidden: :forbidden,
      Conflict: :conflict,
      PaymentRequired: :payment_required,
      Gone: :gone,
      Locked: :locked,
      UnavailableForLegalReasons: :unavailable_for_legal_reasons
    }.freeze

    # Live module holding one generated helper per registered error status.
    # ActionFigure::Formatter includes it, so the helpers reach every formatter
    # module and every composed format module through method lookup — including
    # classes that included a format module before a late +register_error+ call.
    # A helper hand-defined on a formatter shadows the generated one, because
    # the formatter sits ahead of this module in the ancestor chain.
    module Helpers; end

    def self.define_helper(name, status_symbol)
      Helpers.define_method(name) do |errors: nil, **extras|
        error_response(errors: errors, status: status_symbol, **extras)
      end
    end

    DEFAULTS.each { |name, status| define_helper(name, status) }

    # Populates the registry when ErrorRegistry is extended (at gem load,
    # single-threaded), so no lazy initialization races with reader threads.
    def self.extended(base)
      registry = Concurrent::Map.new
      DEFAULTS.each { |name, status| registry[name] = status }
      base.instance_variable_set(:@error_status_registry, registry)
    end

    # Statuses Rack itself doesn't map on every supported version:
    # Rack < 3.1 knows 422 only as :unprocessable_entity, Rack >= 3.1 only as
    # :unprocessable_content. Accept both everywhere.
    STATUS_CODE_FALLBACKS = { unprocessable_content: 422, unprocessable_entity: 422 }.freeze

    # A plain-Hash copy of the current registry (built-ins plus any registered).
    def error_statuses
      error_status_registry.each_pair.to_h
    end

    # Resolves a Rack-style status symbol to its numeric HTTP status code,
    # raising ArgumentError for symbols no supported Rack version knows.
    # Single resolution point for formatters and register_error validation.
    def status_code_for(status_symbol)
      Rack::Utils::SYMBOL_TO_STATUS_CODE[status_symbol] ||
        STATUS_CODE_FALLBACKS[status_symbol] ||
        raise(ArgumentError, "#{status_symbol.inspect} is not a known HTTP status symbol")
    end

    # Registers an additional error status. Add-only: does not remove or override.
    # Defines the generated helper on the live Helpers module (so it appears on
    # every formatter and already-included action class immediately) and patches
    # already-loaded test adapters.
    def register_error(name, status_symbol)
      name = name.to_sym
      status_symbol = status_symbol.to_sym
      validate_registration!(name, status_symbol)

      existing = error_status_registry.put_if_absent(name, status_symbol)
      if existing && existing != status_symbol
        raise ArgumentError,
              "Error status #{name.inspect} is already registered as #{existing.inspect}; " \
              "register_error is add-only and cannot override it"
      end
      return name if existing

      ErrorRegistry.define_helper(name, status_symbol)
      ActionFigure::Testing.define_error_helper(name, status_symbol) if defined?(ActionFigure::Testing)
      name
    end

    private

    attr_reader :error_status_registry

    # Rejects reserved helper names and unknown status symbols up front, so a
    # bad registration fails at boot instead of at render time.
    def validate_registration!(name, status_symbol)
      reserved = Formatter::REQUIRED_METHODS + [:NoContent]
      if reserved.include?(name)
        raise ArgumentError,
              "#{name.inspect} is reserved by the formatter contract and cannot be " \
              "registered as an error status"
      end

      status_code_for(status_symbol)
    end
  end
end
