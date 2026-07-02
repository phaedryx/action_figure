# frozen_string_literal: true

require "test_helper"

class JsonApiFormatterTest < Minitest::Test
  # --- Ok ---

  def test_ok_returns_200
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Ok(resource: { type: "user", id: "1", attributes: {} })
    assert_equal :ok, result[:status]
  end

  def test_ok_wraps_resource_in_data
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    resource = { type: "user", id: "1", attributes: { name: "Tad" } }
    result = formatter.Ok(resource:)
    assert_equal resource, result[:json][:data]
  end

  def test_ok_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Ok(resource: { type: "user", id: "1", attributes: {} })
    refute result[:json].key?(:meta)
  end

  def test_ok_with_meta_includes_meta
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Ok(resource: { type: "user", id: "1", attributes: {} }, meta: { total: 5 })
    assert_equal({ total: 5 }, result[:json][:meta])
  end

  def test_ok_accepts_ar_object
    User.delete_all
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = formatter.Ok(resource: user)
    assert_equal "user", result[:json][:data][:type]
    assert_equal user.id.to_s, result[:json][:data][:id]
  end

  # --- Created ---

  def test_created_returns_201
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Created(resource: { type: "user", id: "1", attributes: {} })
    assert_equal :created, result[:status]
  end

  def test_created_wraps_resource_in_data
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    resource = { type: "user", id: "1", attributes: {} }
    result = formatter.Created(resource:)
    assert_equal resource, result[:json][:data]
  end

  def test_created_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Created(resource: { type: "user", id: "1", attributes: {} })
    refute result[:json].key?(:meta)
  end

  def test_created_with_meta_includes_meta
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Created(resource: { type: "user", id: "1", attributes: {} }, meta: { token: "xyz" })
    assert_equal({ token: "xyz" }, result[:json][:meta])
  end

  # --- Accepted ---

  def test_accepted_returns_202
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Accepted()
    assert_equal :accepted, result[:status]
  end

  def test_accepted_without_resource_returns_empty_json_body
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Accepted()
    assert_equal({}, result[:json])
  end

  def test_accepted_with_hash_resource_wraps_in_data
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    resource = { type: "user", id: "1", attributes: {} }
    result = formatter.Accepted(resource:)
    assert_equal resource, result[:json][:data]
  end

  def test_accepted_with_ar_resource_serializes_and_wraps_in_data
    User.delete_all
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = formatter.Accepted(resource: user)
    assert_equal "user", result[:json][:data][:type]
    assert_equal user.id.to_s, result[:json][:data][:id]
  end

  def test_accepted_with_meta_includes_meta_alongside_data
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    resource = { type: "job", id: "1", attributes: { status: "queued" } }
    result = formatter.Accepted(resource: resource, meta: { estimated_time: "5m" })
    assert_equal :accepted, result[:status]
    assert_equal resource, result[:json][:data]
    assert_equal({ estimated_time: "5m" }, result[:json][:meta])
  end

  def test_accepted_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    resource = { type: "job", id: "1", attributes: { status: "queued" } }
    result = formatter.Accepted(resource: resource)
    assert_equal :accepted, result[:status]
    refute result[:json].key?(:meta)
  end

  # --- NoContent ---

  def test_no_content_returns_204
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NoContent()
    assert_equal :no_content, result[:status]
  end

  def test_no_content_has_no_json_body
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NoContent()
    refute result.key?(:json)
  end

  # --- error_response ---

  def test_error_response_converts_errors_with_derived_status_code
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.error_response(errors: { name: ["bad"] }, status: :not_found)
    assert_equal :not_found, result[:status]
    first = result[:json][:errors].first
    assert_equal "404", first[:status]
    assert_equal "/data/attributes/name", first[:source][:pointer]
  end

  def test_error_response_derives_code_for_registered_style_statuses
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.error_response(errors: { base: ["gone"] }, status: :gone)
    assert_equal "410", result[:json][:errors].first[:status]
  end

  def test_error_response_base_error_produces_document_level_data_pointer
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.error_response(errors: { base: ["conflict"] }, status: :conflict)
    assert_equal "/data", result[:json][:errors].first[:source][:pointer]
  end

  def test_error_response_nested_errors_hash_produces_deep_pointer
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.error_response(
      errors: { address: { city: ["is required"] } },
      status: :unprocessable_content
    )
    errors = result[:json][:errors]
    assert_equal 1, errors.length
    assert_equal "/data/attributes/address/city", errors.first[:source][:pointer]
    assert_equal "422", errors.first[:status]
    assert_equal "is required", errors.first[:detail]
  end

  def test_error_response_multiple_messages_produces_multiple_entries
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.error_response(
      errors: { name: ["too short", "has invalid chars"] },
      status: :unprocessable_content
    )
    errors = result[:json][:errors]
    assert_equal 2, errors.length
    assert_equal "/data/attributes/name", errors.first[:source][:pointer]
    assert_equal "/data/attributes/name", errors.last[:source][:pointer]
    assert_equal "too short", errors.first[:detail]
    assert_equal "has invalid chars", errors.last[:detail]
    assert_equal "422", errors.first[:status]
  end
end

class JsonApiFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::JsonApi.ancestors, ActionFigure::Formatter
  end
end
