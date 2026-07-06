# frozen_string_literal: true

require "dry/validation"

module ActionFigure
  # The compiled form of a request_schema declaration: per-location coercing
  # contracts plus the typed value classes handed to the action as +request:+.
  # Built once at class load, where it also enforces the declaration guards
  # (path params always required, no reserved key names).
  class RequestSchema
    LOCATIONS = %i[path query body].freeze

    # Method names the generated request values define themselves; schema keys
    # with these names would be shadowed, so they are rejected at class load.
    RESERVED_KEYS = %i[given? given_keys to_h deconstruct_keys].freeze

    # Instance behavior for generated location classes. Each carries the set of
    # keys the client actually sent (+given_keys+), so absent and explicit-nil
    # stay distinguishable (PATCH semantics): reads return nil for both,
    # +given?+ tells them apart, and +to_h+/+deconstruct_keys+ expose given
    # keys only.
    module ValueBehavior
      def given?(key)
        given_keys.include?(key)
      end

      # Given keys only, plain hashes all the way down — safe to hand straight
      # to model layers. Pattern matching keeps typed values instead: see
      # +deconstruct_keys+.
      def to_h
        super.slice(*given_keys).transform_values { |value| ValueBehavior.unwrap(value) }
      end

      def deconstruct_keys(requested)
        given = super(nil).slice(*given_keys)
        requested.nil? ? given : given.slice(*requested)
      end

      def self.unwrap(value)
        case value
        when ValueBehavior then value.to_h
        when Array then value.map { |element| unwrap(element) }
        else value
        end
      end
    end

    # Collects the path/query/body location blocks of a request_schema declaration.
    class Locations
      attr_reader :blocks

      def initialize(&)
        @blocks = {}
        instance_eval(&)
      end

      LOCATIONS.each do |location|
        define_method(location) do |&blk|
          if @blocks.key?(location)
            raise ArgumentError,
                  "#{location} already declared — each location takes one block"
          end
          unless blk
            raise ArgumentError,
                  "#{location} location requires a block — " \
                  "e.g. #{location} { required(:key).filled(:string) }"
          end

          @blocks[location] = blk
        end
      end

      %i[required optional].each do |declaration|
        define_method(declaration) do |*|
          raise ArgumentError,
                "#{declaration} must be declared inside a path, query, or body location — " \
                "request_schema takes locations, not bare declarations"
        end
      end
    end

    # One Shape per hash level of a schema, generated at class load: a Data class
    # for the level's keys plus child shapes for nested hashes and arrays of
    # hashes. Levels the schema doesn't describe (blockless +hash+) have no
    # shape and stay plain hashes — typed exactly as deep as the contract is
    # explicit. Validated hashes omit absent optional keys (dry-schema
    # behavior), so each level's key set is exactly its given set.
    class Shape
      def initialize(keys_info)
        @keys = keys_info.keys.freeze
        @value_class = Data.define(*@keys, :given_keys)
        @value_class.include(ValueBehavior)
        @children = keys_info.filter_map do |key, meta|
          child = child_shape(meta)
          [key, child] if child
        end.to_h
      end

      def build(validated)
        values = @keys.to_h { |key| [key, build_member(key, validated[key])] }
        @value_class.new(**values, given_keys: validated.keys.freeze)
      end

      private

      def child_shape(meta)
        return Shape.new(meta[:keys]) if meta[:keys]

        member_keys = RequestSchema.member_keys(meta)
        ArrayShape.new(Shape.new(member_keys)) if member_keys
      end

      def build_member(member, value)
        child = @children[member]
        return value if child.nil? || value.nil?

        child.build(value)
      end
    end

    # Applies an element Shape across an array-of-hashes member.
    class ArrayShape
      def initialize(element_shape)
        @element_shape = element_shape
      end

      def build(values)
        values.map { |value| @element_shape.build(value) }
      end
    end

    # dry-schema's info extension emits member: "integer" (a type name) for
    # arrays of primitives and member: {keys: {...}} for arrays of hashes;
    # only the latter carries nested keys.
    def self.member_keys(meta)
      member = meta[:member]
      member[:keys] if member.is_a?(Hash)
    end

    # Flattens per-location validation results into one errors hash. Same-named
    # keys across locations are distinct parameters, so colliding messages
    # concatenate (and nested hashes deep-merge) instead of last-location-wins.
    def self.merge_errors(results)
      results.map { |result| result.errors.to_h }
             .reduce({}) { |merged, errors| deep_merge_errors(merged, errors) }
    end

    def self.deep_merge_errors(left, right)
      left.merge(right) do |_key, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge_errors(a, b) : Array(a) + Array(b)
      end
    end
    private_class_method :deep_merge_errors

    attr_reader :contracts

    def initialize(&)
      @ruled_locations = []
      @location_blocks = Locations.new(&).blocks
      @contracts = @location_blocks.transform_values { |blk| Dry::Schema.Params(&blk) }
      enforce_declaration_guards
      @location_shapes = @contracts.transform_values { |schema| Shape.new(schema.info[:keys]) }
      @container_class = Data.define(*@contracts.keys)
    end

    # Attaches a rules block to the named location, rebuilding that location's
    # contract as a Dry::Validation::Contract (schema + rules, cross-param
    # helpers included). Locations are explicit: rules(:query) { ... }.
    def attach_rules(location, &rules_block)
      location_block = ruleable_location_block(location)
      @ruled_locations << location

      contract_class = Core.build_contract_class(location_block, rules_block)
      @contracts = @contracts.merge(location => contract_class.new)
    end

    # Validates each declared location's source hash (missing sources validate
    # as empty), returning {location => result}. Both the runtime pipeline and
    # the testing adapters go through here so they cannot drift.
    def validate(sources)
      @contracts.to_h { |location, contract| [location, contract.call(sources.fetch(location, {}))] }
    end

    # Constructs the frozen request value from validated location hashes;
    # per-request work is construction only.
    def build_value(validated_by_location)
      locations = @location_shapes.to_h do |name, shape|
        [name, shape.build(validated_by_location.fetch(name))]
      end
      @container_class.new(**locations)
    end

    private

    def enforce_declaration_guards
      disallow_optional_path_params
      @contracts.each_value { |schema| disallow_reserved_keys(schema.info[:keys]) }
    end

    # Resolves and guards the location a rules block attaches to: it must be
    # named, declared, and not already ruled.
    def ruleable_location_block(location)
      unless location
        raise ArgumentError,
              "rules on a request_schema action must name a location — e.g. rules(:body) { ... }"
      end

      location_block = @location_blocks[location]
      unless location_block
        raise ArgumentError,
              "rules(#{location.inspect}) — no #{location} location declared " \
              "(declared: #{@location_blocks.keys.map(&:inspect).join(", ")})"
      end
      if @ruled_locations.include?(location)
        raise ArgumentError,
              "rules(#{location.inspect}) already defined — each location takes one rules block"
      end

      location_block
    end

    def disallow_optional_path_params
      path_schema = @contracts[:path]
      return unless path_schema

      optional_keys = path_schema.info[:keys].reject { |_key, meta| meta[:required] }.keys
      return if optional_keys.empty?

      raise ArgumentError,
            "optional(#{optional_keys.map(&:inspect).join(", ")}) in path location — " \
            "OpenAPI path parameters are always required"
    end

    def disallow_reserved_keys(keys_info)
      keys_info.each do |key, meta|
        if RESERVED_KEYS.include?(key)
          raise ArgumentError,
                "schema key #{key.inspect} is reserved by ActionFigure request values " \
                "(#{RESERVED_KEYS.map(&:inspect).join(", ")})"
        end

        nested = meta[:keys] || RequestSchema.member_keys(meta)
        disallow_reserved_keys(nested) if nested
      end
    end
  end
end
