# frozen_string_literal: true

module ActionFigure
  module Core
    # The request_schema half of the validation pipeline, included into Core:
    # reads location sources off the request object, validates each declared
    # location, and invokes the entry point with the typed request value.
    module RequestValidation
      # Maps each schema location to the request reader that supplies it. Drives
      # both the duck-type check and source reads.
      LOCATION_SOURCES = {
        path: :path_parameters,
        query: :query_parameters,
        body: :request_parameters
      }.freeze

      # Messages a request-like object must answer to be accepted as request:.
      REQUEST_DUCK_TYPE = LOCATION_SOURCES.values.freeze

      private

      def request_validate_and_call(**kwargs)
        raw = kwargs[:request]
        verify_request_duck_type!(raw)

        schema = self.class.request_schema
        sources = request_sources(raw)
        results = schema.validate(sources)

        failure = request_validation_failure(sources, results)
        return failure if failure

        value = schema.build_value(results.transform_values(&:to_h))
        public_send(entry_point_name, **kwargs, request: value)
      end

      def request_validation_failure(sources, results)
        failures = results.select { |_location, result| result.failure? }
        return request_failure_response(failures) if failures.any?

        check_extra_request_params(sources, results)
      end

      def verify_request_duck_type!(raw)
        return if REQUEST_DUCK_TYPE.all? { |message| raw.respond_to?(message) }

        raise ArgumentError,
              "#{self.class} declares request_schema — pass request: " \
              "(the Rails request object (ActionDispatch::Request), or " \
              "ActionFigure.request(path:, query:, body:) in tests), got #{raw.inspect}"
      end

      # The path location is exempt: the router, not the client, defines path keys,
      # and path_parameters carries bookkeeping entries (:controller, :action, :format).
      def check_extra_request_params(sources, results)
        return unless ActionFigure.configuration.whiny_extra_params

        errors = sources.except(:path)
                        .map { |location, raw| find_extra_keys(raw, results.fetch(location).to_h) }
                        .reduce({}, :merge)
        return if errors.empty?

        UnprocessableContent(errors: errors)
      end

      # A path param failing its schema means the resource identity is malformed;
      # 404 matches what a find would produce. Identity wins on mixed failures.
      def request_failure_response(failures)
        errors = RequestSchema.merge_errors(failures.values)
        return NotFound(errors: errors) if failures.key?(:path)

        UnprocessableContent(errors: errors)
      end

      # Reads only the declared locations' sources — an undeclared body is never
      # parsed. Router bookkeeping keys (:controller, :action, :format) in
      # path_parameters need no stripping: locations validate declared keys only,
      # and the value factory exposes schema members only, so undeclared keys
      # never surface.
      def request_sources(raw)
        self.class.request_schema.contracts.keys.to_h do |location|
          [location, raw.public_send(LOCATION_SOURCES.fetch(location))]
        end
      end
    end
  end
end
