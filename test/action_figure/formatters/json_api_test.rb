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

  # --- UnprocessableContent ---

  def test_unprocessable_content_returns_422
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.UnprocessableContent(errors: { name: ["can't be blank"] })
    assert_equal :unprocessable_content, result[:status]
  end

  def test_unprocessable_content_converts_error_to_jsonapi_object
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.UnprocessableContent(errors: { name: ["can't be blank"] })
    error = result[:json][:errors].first
    assert_equal "422", error[:status]
    assert_equal "can't be blank", error[:detail]
    assert_equal "/data/attributes/name", error[:source][:pointer]
  end

  def test_unprocessable_content_multiple_messages_produce_multiple_errors
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.UnprocessableContent(errors: { name: ["can't be blank", "is too short"] })
    assert_equal 2, result[:json][:errors].length
    assert_equal "can't be blank", result[:json][:errors][0][:detail]
    assert_equal "is too short", result[:json][:errors][1][:detail]
  end

  def test_unprocessable_content_multiple_fields_produce_multiple_errors
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.UnprocessableContent(errors: { name: ["can't be blank"], email: ["is invalid"] })
    pointers = result[:json][:errors].map { _1[:source][:pointer] }
    assert_includes pointers, "/data/attributes/name"
    assert_includes pointers, "/data/attributes/email"
  end

  # --- NotFound ---

  def test_not_found_returns_404
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NotFound(errors: { base: ["not found"] })
    assert_equal :not_found, result[:status]
  end

  def test_not_found_error_has_404_status_string
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NotFound(errors: { base: ["not found"] })
    assert_equal "404", result[:json][:errors].first[:status]
  end

  def test_not_found_pointer_derived_from_error_key
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NotFound(errors: { record: ["not found"] })
    assert_equal "/data/attributes/record", result[:json][:errors].first[:source][:pointer]
  end

  def test_not_found_base_error_produces_data_pointer
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.NotFound(errors: { base: ["not found"] })
    assert_equal "/data", result[:json][:errors].first[:source][:pointer]
  end

  # --- Forbidden ---

  def test_forbidden_returns_403
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Forbidden(errors: { base: ["not authorized"] })
    assert_equal :forbidden, result[:status]
  end

  def test_forbidden_error_has_403_status_string
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Forbidden(errors: { base: ["not authorized"] })
    error = result[:json][:errors].first
    assert_equal "403", error[:status]
    assert_equal "not authorized", error[:detail]
    assert_equal "/data", error[:source][:pointer]
  end

  # --- Conflict ---

  def test_conflict_returns_409
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Conflict(errors: { base: ["already exists"] })
    assert_equal :conflict, result[:status]
  end

  def test_conflict_error_has_409_status_string
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.Conflict(errors: { base: ["already exists"] })
    error = result[:json][:errors].first
    assert_equal "409", error[:status]
    assert_equal "already exists", error[:detail]
    assert_equal "/data", error[:source][:pointer]
  end

  # --- PaymentRequired ---

  def test_payment_required_returns_402
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.PaymentRequired(errors: { base: ["subscription overdue"] })
    assert_equal :payment_required, result[:status]
  end

  def test_payment_required_error_has_402_status_string
    formatter = Object.new.extend(ActionFigure::Formatters::JsonApi)
    result = formatter.PaymentRequired(errors: { base: ["subscription overdue"] })
    error = result[:json][:errors].first
    assert_equal "402", error[:status]
    assert_equal "subscription overdue", error[:detail]
    assert_equal "/data", error[:source][:pointer]
  end
end

class JsonApiFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::JsonApi.ancestors, ActionFigure::Formatter
  end
end
