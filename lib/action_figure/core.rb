# frozen_string_literal: true

require "dry/validation"

require_relative "core/request_validation"

Dry::Schema.load_extensions(:info)

module ActionFigure
  # Provides the validation pipeline and DSL mixed into action classes via ActionFigure.[].
  module Core
    # Extended into dry-validation contract classes to provide cross-param rule helpers.
    module CrossParamRuleHelpers
      def exclusive_rule(*fields, message)
        rule(*fields) do
          present = fields.select { |f| values.key?(f) && !values[f].nil? }
          present.each { |f| key(f).failure(message) } if present.size > 1
        end
      end

      def any_rule(*fields, message)
        rule(*fields) do
          present = fields.select { |f| values.key?(f) && !values[f].nil? }
          fields.each { |f| key(f).failure(message) } if present.empty?
        end
      end

      def one_rule(*fields, message)
        rule(*fields) do
          present = fields.select { |f| values.key?(f) && !values[f].nil? }
          fields.each { |f| key(f).failure(message) } unless present.size == 1
        end
      end

      def all_rule(*fields, message)
        rule(*fields) do
          present = fields.select { |f| values.key?(f) && !values[f].nil? }
          fields.each { |f| key(f).failure(message) } unless present.empty? || present.size == fields.size
        end
      end
    end

    # One factory for every validation contract class — params_schema contracts
    # and request_schema location contracts — so contract-wide concerns
    # (cross-param helpers, future config) cannot drift between the two.
    def self.build_contract_class(schema_block, rules_block)
      Class.new(Dry::Validation::Contract) do
        extend CrossParamRuleHelpers

        params(&schema_block)
        class_eval(&rules_block) if rules_block
      end
    end

    # DSL class methods extended into action classes: params_schema, rules, entry_point.
    #
    # Note: ActionFigure does not support class inheritance. +params_schema+, +rules+, and
    # +entry_point+ store state in class-level instance variables that are not inherited by
    # subclasses. Define each action class independently.
    module ClassMethods
      def params_schema(&block)
        disallow_second_schema!(:params_schema)

        @params_schema_block = block
        @contract = nil
      end

      # Block form declares and compiles the schema; no-args form returns the
      # compiled ActionFigure::RequestSchema (or nil), mirroring api_version.
      def request_schema(&)
        return @request_schema unless block_given?

        disallow_second_schema!(:request_schema)

        @request_schema = RequestSchema.new(&)
      end

      def rules(location = nil, &block)
        return @request_schema.attach_rules(location, &block) if @request_schema

        if location && @params_schema_block
          raise ArgumentError,
                "rules(#{location.inspect}) — locations are a request_schema concept; " \
                "params_schema actions take a bare rules block"
        end
        if location
          raise ArgumentError,
                "rules(#{location.inspect}) requires request_schema to be declared first — " \
                "move the request_schema block above rules(#{location.inspect})"
        end
        raise ArgumentError, "rules requires params_schema to be defined" unless @params_schema_block

        @rules_block = block
        @contract = nil
      end

      # Declares an alternative entry point method name (e.g. +entry_point :search+).
      # May only be called once per class. Inheritance of action classes is not supported —
      # +params_schema+, +rules+, and +entry_point+ are not inherited by subclasses.
      def entry_point(name)
        if @entry_point_name
          raise ArgumentError,
                "entry_point already defined as '#{@entry_point_name}' — " \
                "each action class may declare only one entry point"
        end

        @explicit_entry_point = true
        @entry_point_name = name
        singleton_class.define_method(name) do |**kwargs|
          notify { new.validated_call(**kwargs) }
        end
      end

      def entry_point_name
        @entry_point_name
      end

      def api_version(value = :_unset)
        value == :_unset ? @api_version : (@api_version = value)
      end

      def contract
        return nil unless @params_schema_block

        @contract ||= build_contract
      end

      private

      # Schemas are mutually exclusive and single-shot: declaring a second one
      # of either kind raises at class load.
      def disallow_second_schema!(declaring)
        { params_schema: @params_schema_block, request_schema: @request_schema }
          .each do |kind, existing|
            next unless existing

            detail = if kind == declaring
                       "each action class may declare only one schema"
                     else
                       "an action class declares params_schema or request_schema, not both"
                     end
            raise ArgumentError, "#{kind} already defined — #{detail}"
          end
      end

      # no-op when notifications aren't turned on
      def notify
        yield
      end

      def method_added(name)
        disallow_action_initialize(name)

        return if @explicit_entry_point || !public_method_defined?(name)
        return unless instance_method(name).owner == self

        if @entry_point_name
          raise IndeterminateEntryPointError,
                "Multiple public methods defined in #{self}: " \
                ":#{@entry_point_name} and :#{name}. " \
                "Either make one private or declare " \
                "`entry_point :#{@entry_point_name}` to disambiguate."
        end

        @entry_point_name = name
        singleton_class.define_method(name) do |**kwargs|
          notify { new.validated_call(**kwargs) }
        end
      ensure
        super
      end

      def disallow_action_initialize(method_name)
        return unless method_name == :initialize
        return unless instance_method(:initialize).owner == self

        raise InitializationNotSupportedError,
              "#{self} must not define initialize — ActionFigure invokes new with no " \
              "arguments. Pass dependencies via the entry method's keyword arguments " \
              "or use class-level collaborators."
      end

      def build_contract
        Core.build_contract_class(@params_schema_block, @rules_block).new
      end
    end

    def entry_point_name
      self.class.entry_point_name
    end

    def contract
      self.class.contract
    end

    def validated_call(**kwargs)
      return request_validate_and_call(**kwargs) if self.class.request_schema

      kwargs = normalize_params(kwargs)

      if contract && kwargs.key?(:params)
        validate_and_call(**kwargs)
      else
        public_send(entry_point_name, **kwargs)
      end
    end

    # Overrides ClassMethods#notify with ActiveSupport::Notifications when available.
    # Extended onto action classes at include-time so the check happens once, not per call.
    module Notifications
      private

      def notify
        payload = {
          action: name,
          entry_point: entry_point_name
        }
        ActiveSupport::Notifications.instrument("process.action_figure", payload) do
          result = yield
          payload[:status] = result[:status]
          result
        end
      end
    end

    include RequestValidation

    private

    def normalize_params(kwargs)
      return kwargs unless contract

      raw = kwargs[:params]
      return kwargs unless raw.respond_to?(:to_unsafe_h)

      kwargs.merge(params: raw.to_unsafe_h)
    end

    def validate_and_call(**kwargs)
      result = contract.call(kwargs[:params])

      return UnprocessableContent(errors: result.errors.to_h) if result.failure?

      extra_params_error = check_extra_params(kwargs[:params], result)
      return extra_params_error if extra_params_error

      public_send(entry_point_name, **kwargs.except(:params), params: result.to_h)
    end

    def check_extra_params(raw_params, result)
      return unless ActionFigure.configuration.whiny_extra_params

      errors = find_extra_keys(raw_params, result.to_h)
      return if errors.empty?

      UnprocessableContent(errors: errors)
    end

    def find_extra_keys(raw, validated, prefix = nil)
      top_level = extra_keys_at_level(raw, validated, prefix)
      nested = nested_extra_keys(raw, validated, prefix)
      top_level.merge(nested)
    end

    def extra_keys_at_level(raw, validated, prefix)
      (raw.keys.map(&:to_sym) - validated.keys).to_h do |k|
        [prefix ? :"#{prefix}.#{k}" : k, ["is not allowed"]]
      end
    end

    def nested_extra_keys(raw, validated, prefix)
      validated.each_with_object({}) do |(key, value), errors|
        next unless value.is_a?(Hash) && raw[key].is_a?(Hash)

        nested_prefix = [prefix, key].compact.join(".")
        errors.merge!(find_extra_keys(raw[key], value, nested_prefix))
      end
    end
  end
end
