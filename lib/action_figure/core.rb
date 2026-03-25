# frozen_string_literal: true

require "dry/validation"

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

      def implies_rule(antecedent, consequent, message)
        rule(antecedent, consequent) do
          present = ->(f) { values.key?(f) && !values[f].nil? }
          if present.call(antecedent) && !present.call(consequent)
            key(antecedent).failure(message)
            key(consequent).failure(message)
          end
        end
      end
    end

    # DSL class methods extended into action classes: params_schema, rules, entry_point, call.
    #
    # Note: ActionFigure does not support class inheritance. +params_schema+, +rules+, and
    # +entry_point+ store state in class-level instance variables that are not inherited by
    # subclasses. Define each action class independently.
    module ClassMethods
      def params_schema(&block)
        @params_schema_block = block
        @contract = nil
      end

      def rules(&block)
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

        @entry_point_name = name
        singleton_class.define_method(name) do |**kwargs|
          instrument { new.validated_call(**kwargs) }
        end
      end

      def entry_point_name
        @entry_point_name
      end

      def api_version(value = :_unset)
        value == :_unset ? @api_version : (@api_version = value)
      end

      def call(**)
        if @entry_point_name
          raise NoMethodError, "undefined method 'call' for #{self} (use '#{@entry_point_name}' instead)"
        end

        instrument { new.validated_call(**) }
      end

      def contract
        return nil unless @params_schema_block

        @contract ||= build_contract
      end

      private

      def instrument
        yield
      end

      def build_contract
        schema_block = @params_schema_block
        rules_block = @rules_block

        contract_class = Class.new(Dry::Validation::Contract) do
          extend ActionFigure::Core::CrossParamRuleHelpers

          params(&schema_block)
          class_eval(&rules_block) if rules_block
        end

        contract_class.new
      end
    end

    def entry_point_name
      self.class.entry_point_name || :call
    end

    def contract
      self.class.contract
    end

    def validated_call(**kwargs)
      raise ArgumentError, "params: passed but no params_schema defined" if kwargs.key?(:params) && !contract

      if kwargs.key?(:params)
        call_with_params(**kwargs)
      else
        call_without_params(**kwargs)
      end
    end

    # Overrides ClassMethods#instrument with ActiveSupport::Notifications when available.
    # Extended onto action classes at include-time so the check happens once, not per call.
    module Instrumentation
      private

      def instrument
        payload = { action: name }
        ActiveSupport::Notifications.instrument("process.action_figure", payload) do
          result = yield
          payload[:status] = result[:status]
          result
        end
      end
    end

    private

    def call_with_params(**kwargs)
      raw_params = kwargs[:params]
      raw_params = raw_params.to_unsafe_h if raw_params.respond_to?(:to_unsafe_h)

      result = contract.call(raw_params)

      return UnprocessableContent(errors: result.errors.to_h) if result.failure?

      extra_params_error = check_extra_params(raw_params, result)
      return extra_params_error if extra_params_error

      public_send(entry_point_name, **kwargs, params: result.to_h)
    end

    def check_extra_params(raw_params, result)
      return unless ActionFigure.configuration.whiny_extra_params

      extra_keys = raw_params.keys.map(&:to_sym) - result.to_h.keys
      return if extra_keys.empty?

      errors = extra_keys.to_h { |k| [k, ["is not allowed"]] }
      UnprocessableContent(errors: errors)
    end

    def call_without_params(**)
      public_send(entry_point_name, **)
    end
  end
end
