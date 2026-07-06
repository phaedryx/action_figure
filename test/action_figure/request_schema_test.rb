# frozen_string_literal: true

require "test_helper"

# --- Declaration ---

class RequestSchemaDeclarationTest < Minitest::Test
  def test_locations_compile_to_coercing_contracts
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        path  { required(:id).filled(:integer) }
        query { required(:workspace_id).filled(:integer) }
        body  { required(:name).filled(:string) }
      end
    end

    assert_equal %i[path query body], action.request_schema.contracts.keys

    result = action.request_schema.contracts[:query].call(workspace_id: "42")
    assert_predicate result, :success?
    assert_equal({ workspace_id: 42 }, result.to_h)
  end

  def test_arrays_of_primitives_compile_and_coerce
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body { required(:ids).array(:integer) }
      end

      def create(request:)
        Ok(resource: { ids: request.body.ids })
      end
    end

    result = action.create(request: ActionFigure.request(body: { ids: %w[1 2] }))

    assert_equal :ok, result[:status]
    assert_equal [1, 2], result[:json][:data][:ids]
  end

  def test_blockless_array_of_hashes_compiles_and_stays_plain
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body { required(:tags).array(:hash) }
      end

      def create(request:)
        Ok(resource: { tags: request.body.tags })
      end
    end

    result = action.create(request: ActionFigure.request(body: { tags: [{ "name" => "a" }] }))

    assert_equal :ok, result[:status]
  end
end

# --- Invocation with request: ---

class RequestSchemaInvocationTest < Minitest::Test
  def build_action
    Class.new do
      include ActionFigure[:jsend]

      request_schema do
        path  { required(:id).filled(:integer) }
        query { required(:workspace_id).filled(:integer) }
        body  { required(:name).filled(:string) }
      end

      def update(request:, current_user:)
        Ok(resource: {
             id: request.path.id,
             workspace_id: request.query.workspace_id,
             name: request.body.name,
             current_user: current_user
           })
      end
    end
  end

  def test_locations_validate_against_their_sources_and_coerce
    action = build_action

    result = action.update(
      request: ActionFigure.request(
        path: { id: "7" },
        query: { workspace_id: "42" },
        body: { name: "Roadmap" }
      ),
      current_user: "alice"
    )

    assert_equal :ok, result[:status]
    assert_equal(
      { id: 7, workspace_id: 42, name: "Roadmap", current_user: "alice" },
      result[:json][:data]
    )
  end

  def test_validation_failures_render_unprocessable_content_with_flat_errors
    action = build_action

    result = action.update(
      request: ActionFigure.request(
        path: { id: "7" },
        query: { workspace_id: "42" },
        body: { name: "" }
      ),
      current_user: "alice"
    )

    assert_equal :unprocessable_content, result[:status]
    assert_equal ["must be filled"], result[:json][:data][:name]
  end

  def test_query_location_key_arriving_in_body_is_not_seen
    action = build_action

    result = action.update(
      request: ActionFigure.request(
        path: { id: "7" },
        query: {},
        body: { name: "Roadmap", workspace_id: "42" }
      ),
      current_user: "alice"
    )

    assert_equal :unprocessable_content, result[:status]
    assert_equal ["is missing"], result[:json][:data][:workspace_id]
  end

  def test_path_location_failure_renders_not_found
    action = build_action

    result = action.update(
      request: ActionFigure.request(
        path: { id: "abc" },
        query: { workspace_id: "42" },
        body: { name: "Roadmap" }
      ),
      current_user: "alice"
    )

    assert_equal :not_found, result[:status]
    assert_equal ["must be an integer"], result[:json][:data][:id]
  end

  def test_mixed_failures_render_not_found
    action = build_action

    result = action.update(
      request: ActionFigure.request(
        path: { id: "abc" },
        query: { workspace_id: "42" },
        body: { name: "" }
      ),
      current_user: "alice"
    )

    assert_equal :not_found, result[:status]
  end

  def test_passing_params_instead_of_request_raises_with_guidance
    action = build_action

    error = assert_raises(ArgumentError) do
      action.update(params: { name: "Roadmap" }, current_user: "alice")
    end

    assert_match(/declares request_schema/, error.message)
    assert_match(/ActionFigure\.request/, error.message)
  end

  def test_passing_a_plain_hash_as_request_raises_with_guidance
    action = build_action

    error = assert_raises(ArgumentError) do
      action.update(request: { name: "Roadmap" }, current_user: "alice")
    end

    assert_match(/ActionFigure\.request/, error.message)
  end

  def test_actions_may_declare_only_the_locations_they_have
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body { required(:name).filled(:string) }
      end

      def create(request:)
        Ok(resource: { name: request.body.name })
      end
    end

    result = action.create(request: ActionFigure.request(body: { name: "Roadmap" }))

    assert_equal :ok, result[:status]
    assert_equal({ name: "Roadmap" }, result[:json][:data])
  end

  def test_given_distinguishes_absent_from_explicit_nil
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:name).filled(:string)
          optional(:description).maybe(:string)
        end
      end

      def update(request:)
        Ok(resource: {
             description: request.body.description,
             description_given: request.body.given?(:description)
           })
      end
    end

    omitted = action.update(request: ActionFigure.request(body: { name: "x" }))
    explicit_nil = action.update(request: ActionFigure.request(body: { name: "x", description: nil }))

    assert_equal({ description: nil, description_given: false }, omitted[:json][:data])
    assert_equal({ description: nil, description_given: true }, explicit_nil[:json][:data])
  end

  def test_pattern_matching_matches_only_given_keys
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:name).filled(:string)
          optional(:description).maybe(:string)
        end
      end

      def update(request:)
        outcome =
          case request.body
          in { description: }
            { matched: true, description: description }
          else
            { matched: false }
          end
        Ok(resource: outcome)
      end
    end

    omitted = action.update(request: ActionFigure.request(body: { name: "x" }))
    explicit_nil = action.update(request: ActionFigure.request(body: { name: "x", description: nil }))

    assert_equal({ matched: false }, omitted[:json][:data])
    assert_equal({ matched: true, description: nil }, explicit_nil[:json][:data])
  end

  def test_to_h_returns_given_keys_only
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:name).filled(:string)
          optional(:description).maybe(:string)
        end
      end

      def update(request:)
        Ok(resource: request.body.to_h)
      end
    end

    result = action.update(request: ActionFigure.request(body: { name: "x" }))

    assert_equal({ name: "x" }, result[:json][:data])
  end

  def test_nested_hashes_become_nested_typed_values
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:project).hash do
            required(:name).filled(:string)
            optional(:settings).hash do
              optional(:visibility).filled(:string)
            end
          end
        end
      end

      def create(request:)
        project = request.body.project
        Ok(resource: {
             name: project.name,
             visibility: project.settings.visibility,
             visibility_given: project.settings.given?(:visibility)
           })
      end
    end

    result = action.create(
      request: ActionFigure.request(
        body: { project: { name: "Roadmap", settings: { visibility: "public" } } }
      )
    )

    assert_equal :ok, result[:status]
    assert_equal(
      { name: "Roadmap", visibility: "public", visibility_given: true },
      result[:json][:data]
    )
  end

  def test_arrays_of_hashes_become_arrays_of_typed_values
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:tags).array(:hash) do
            required(:label).filled(:string)
          end
        end
      end

      def create(request:)
        Ok(resource: { labels: request.body.tags.map(&:label) })
      end
    end

    result = action.create(
      request: ActionFigure.request(body: { tags: [{ label: "api" }, { label: "public" }] })
    )

    assert_equal :ok, result[:status]
    assert_equal({ labels: %w[api public] }, result[:json][:data])
  end

  def test_blockless_hash_stays_a_plain_hash
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:name).filled(:string)
          required(:metadata).filled(:hash)
        end
      end

      def create(request:)
        Ok(resource: { theme: request.body.metadata[:theme] })
      end
    end

    result = action.create(
      request: ActionFigure.request(body: { name: "x", metadata: { theme: "dark" } })
    )

    assert_equal :ok, result[:status]
    assert_equal({ theme: "dark" }, result[:json][:data])
  end

  def test_to_h_returns_plain_hashes_all_the_way_down
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body do
          required(:project).hash do
            required(:name).filled(:string)
            required(:tags).array(:hash) do
              required(:label).filled(:string)
            end
          end
        end
      end

      def create(request:)
        Ok(resource: request.body.to_h)
      end
    end

    result = action.create(
      request: ActionFigure.request(
        body: { project: { name: "Roadmap", tags: [{ label: "api" }] } }
      )
    )

    assert_equal(
      { project: { name: "Roadmap", tags: [{ label: "api" }] } },
      result[:json][:data]
    )
  end

  def test_typoed_key_access_raises_no_method_error
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body { required(:name).filled(:string) }
      end

      def create(request:)
        Ok(resource: { name: request.body.naem })
      end
    end

    assert_raises(NoMethodError) do
      action.create(request: ActionFigure.request(body: { name: "Roadmap" }))
    end
  end
end

# --- Rules ---

class RequestSchemaRulesTest < Minitest::Test
  def build_action
    Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:workspace_id).filled(:integer) }
        body do
          optional(:user_id).filled(:integer)
          optional(:email).filled(:string)
        end
      end

      rules(:body) do
        exclusive_rule(:user_id, :email, "provide one, not both")
      end

      def lookup(request:)
        Ok(resource: { user_id: request.body.user_id, email: request.body.email })
      end
    end
  end

  def test_cross_param_rule_failures_render_unprocessable_content
    action = build_action

    result = action.lookup(
      request: ActionFigure.request(
        query: { workspace_id: "1" },
        body: { user_id: 7, email: "tad@example.com" }
      )
    )

    assert_equal :unprocessable_content, result[:status]
    assert_includes result[:json][:data][:user_id], "provide one, not both"
    assert_includes result[:json][:data][:email], "provide one, not both"
  end

  def test_query_rules_enforce_cross_param_constraints
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query do
          required(:from).filled(:integer)
          required(:to).filled(:integer)
        end
      end

      rules(:query) do
        rule(:from, :to) do
          key(:from).failure("must be before to") if values[:from] > values[:to]
        end
      end

      def list(request:)
        Ok(resource: { from: request.query.from, to: request.query.to })
      end
    end

    invalid = action.list(request: ActionFigure.request(query: { from: "9", to: "3" }))
    valid   = action.list(request: ActionFigure.request(query: { from: "3", to: "9" }))

    assert_equal :unprocessable_content, invalid[:status]
    assert_includes invalid[:json][:data][:from], "must be before to"
    assert_equal :ok, valid[:status]
  end

  def test_rules_for_an_undeclared_location_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          query { required(:page).filled(:integer) }
        end

        rules(:body) do
          rule(:page) { key.failure("nope") }
        end
      end
    end

    assert_match(/no body location declared/, error.message)
    assert_match(/declared: :query/, error.message)
  end

  def test_bare_rules_on_a_request_schema_action_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body { required(:name).filled(:string) }
        end

        rules do
          rule(:name) { key.failure("nope") }
        end
      end
    end

    assert_match(/must name a location/, error.message)
  end

  def test_location_rules_on_a_params_schema_action_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        params_schema { required(:name).filled(:string) }

        rules(:body) do
          rule(:name) { key.failure("nope") }
        end
      end
    end

    assert_match(/locations are a request_schema concept/, error.message)
  end

  def test_location_rules_before_request_schema_points_at_declaration_order
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        rules(:body) do
          rule(:name) { key.failure("nope") }
        end

        request_schema do
          body { required(:name).filled(:string) }
        end
      end
    end

    assert_match(/requires request_schema to be declared first/, error.message)
  end

  def test_duplicate_rules_for_a_location_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body { required(:name).filled(:string) }
        end

        rules(:body) { rule(:name) { key.failure("first") } }
        rules(:body) { rule(:name) { key.failure("second") } }
      end
    end

    assert_match(/rules\(:body\) already defined/, error.message)
  end

  def test_path_rules_failures_render_not_found
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        path { required(:id).filled(:integer) }
      end

      rules(:path) do
        rule(:id) { key.failure("must be positive") unless values[:id].positive? }
      end

      def show(request:)
        Ok(resource: { id: request.path.id })
      end
    end

    result = action.show(request: ActionFigure.request(path: { id: "-1" }))

    assert_equal :not_found, result[:status]
    assert_includes result[:json][:data][:id], "must be positive"
  end

  def test_rules_pass_when_satisfied
    action = build_action

    result = action.lookup(
      request: ActionFigure.request(query: { workspace_id: "1" }, body: { user_id: 7 })
    )

    assert_equal :ok, result[:status]
    assert_equal({ user_id: 7, email: nil }, result[:json][:data])
  end
end

# --- request: duck type ---

class RequestSchemaDuckTypeTest < Minitest::Test
  def test_non_request_argument_raises_naming_actiondispatch
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        body { required(:name).filled(:string) }
      end

      def create(request:)
        Ok(resource: request.body.to_h)
      end
    end

    error = assert_raises(ArgumentError) { action.create(request: { name: "x" }) }

    assert_match(/ActionDispatch/, error.message)
    refute_match(%r{Rails/Rack}, error.message)
  end
end

# --- Source reads are lazy per declared location ---

class RequestSchemaSourceReadsTest < Minitest::Test
  def test_undeclared_locations_are_never_read_from_the_request
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:q).filled(:string) }
      end

      def search(request:)
        Ok(resource: request.query.to_h)
      end
    end

    request = Class.new do
      def path_parameters = {}
      def query_parameters = { q: "x" }
      def request_parameters = raise("body must not be parsed for a query-only schema")
    end.new

    result = action.search(request: request)

    assert_equal :ok, result[:status]
    assert_equal({ q: "x" }, result[:json][:data])
  end
end

# --- whiny_extra_params ---

class RequestSchemaWhinyExtraParamsTest < Minitest::Test
  def setup
    @original = ActionFigure.configuration.whiny_extra_params
    ActionFigure.configuration.whiny_extra_params = true
  end

  def teardown
    ActionFigure.configuration.whiny_extra_params = @original
  end

  def build_action
    Class.new do
      include ActionFigure[:jsend]

      request_schema do
        path { required(:id).filled(:integer) }
        body { required(:name).filled(:string) }
      end

      def update(request:)
        Ok(resource: request.body.to_h)
      end
    end
  end

  def test_whiny_extra_params_rejects_undeclared_keys_in_declared_locations
    result = build_action.update(
      request: ActionFigure.request(path: { id: "1" }, body: { name: "x", admin: true })
    )

    assert_equal :unprocessable_content, result[:status]
    assert_equal ["is not allowed"], result[:json][:data][:admin]
  end

  def test_whiny_extra_params_ignores_router_bookkeeping_in_path
    result = build_action.update(
      request: ActionFigure.request(
        path: { id: "1", controller: "users", action: "update", format: "json" },
        body: { name: "x" }
      )
    )

    assert_equal :ok, result[:status]
  end

  def test_extra_keys_pass_silently_when_whiny_is_off
    ActionFigure.configuration.whiny_extra_params = false

    result = build_action.update(
      request: ActionFigure.request(path: { id: "1" }, body: { name: "x", admin: true })
    )

    assert_equal :ok, result[:status]
    assert_equal({ name: "x" }, result[:json][:data])
  end
end

# --- Cross-location error merging ---

class RequestSchemaErrorMergeTest < Minitest::Test
  def build_action
    Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:limit).filled(:integer) }
        body  { required(:limit).filled(:string) }
      end

      def update(request:)
        Ok(resource: request.body.to_h)
      end
    end
  end

  def test_same_key_failing_in_two_locations_keeps_both_errors
    result = build_action.update(
      request: ActionFigure.request(query: { limit: "abc" }, body: {})
    )

    assert_equal :unprocessable_content, result[:status]
    assert_equal ["must be an integer", "is missing"], result[:json][:data][:limit]
  end

  def test_nested_errors_merge_across_locations
    action = Class.new do
      include ActionFigure[:jsend]

      request_schema do
        query { required(:filter).hash { required(:mode).filled(:string) } }
        body  { required(:filter).hash { required(:name).filled(:string) } }
      end

      def update(request:)
        Ok(resource: request.body.to_h)
      end
    end

    result = action.update(
      request: ActionFigure.request(query: { filter: {} }, body: { filter: {} })
    )

    assert_equal :unprocessable_content, result[:status]
    assert_equal({ mode: ["is missing"], name: ["is missing"] }, result[:json][:data][:filter])
  end
end

# --- Class-load guards ---

class RequestSchemaGuardsTest < Minitest::Test
  def test_request_schema_after_params_schema_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        params_schema { required(:name).filled(:string) }
        request_schema { body { required(:name).filled(:string) } }
      end
    end

    assert_match(/params_schema/, error.message)
  end

  def test_params_schema_after_request_schema_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema { body { required(:name).filled(:string) } }
        params_schema { required(:name).filled(:string) }
      end
    end

    assert_match(/request_schema/, error.message)
  end

  def test_optional_key_in_path_location_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          path { optional(:id).filled(:integer) }
        end
      end
    end

    assert_match(/path parameters are always required/, error.message)
  end

  def test_reserved_key_name_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body { required(:to_h).filled(:string) }
        end
      end
    end

    assert_match(/to_h.*reserved/, error.message)
  end

  def test_given_keys_is_a_reserved_key_name
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body { required(:given_keys).filled(:string) }
        end
      end
    end

    assert_match(/given_keys.*reserved/, error.message)
  end

  def test_nested_reserved_key_name_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body do
            required(:settings).hash do
              required(:deconstruct_keys).filled(:string)
            end
          end
        end
      end
    end

    assert_match(/deconstruct_keys.*reserved/, error.message)
  end

  def test_bare_declaration_outside_locations_raises_with_guidance
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          required(:name).filled(:string)
        end
      end
    end

    assert_match(/inside a path, query, or body location/, error.message)
  end

  def test_duplicate_location_block_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          body { required(:name).filled(:string) }
          body { required(:title).filled(:string) }
        end
      end
    end

    assert_match(/body already declared/, error.message)
  end

  def test_blockless_location_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema do
          path
          query { required(:q).filled(:string) }
        end
      end
    end

    assert_match(/path location requires a block/, error.message)
  end

  def test_duplicate_request_schema_raises
    error = assert_raises(ArgumentError) do
      Class.new do
        include ActionFigure[:jsend]

        request_schema { body { required(:name).filled(:string) } }
        request_schema { query { required(:page).filled(:integer) } }
      end
    end

    assert_match(/already defined/, error.message)
  end
end
