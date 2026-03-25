# frozen_string_literal: true

require "test_helper"

class WrappedFormatterTest < Minitest::Test
  # --- Ok ---

  def test_ok_returns_200
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Ok(resource: { id: 1 })
    assert_equal :ok, result[:status]
  end

  def test_ok_wraps_in_uniform_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Ok(resource: { id: 1, name: "Tad" })
    assert_equal({ data: { id: 1, name: "Tad" }, error: nil, status: "success" }, result[:json])
  end

  def test_ok_accepts_activerecord_resource
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = formatter.Ok(resource: user)
    assert_equal :ok, result[:status]
    assert_equal user, result[:json][:data]
    assert_nil result[:json][:error]
    assert_equal "success", result[:json][:status]
  end

  def test_ok_without_meta_has_no_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Ok(resource: { id: 1 })
    refute result[:json].key?(:meta)
  end

  def test_ok_with_meta_includes_meta_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Ok(resource: { id: 1 }, meta: { next_cursor: "abc123" })
    assert_equal({ id: 1 }, result[:json][:data])
    assert_equal({ next_cursor: "abc123" }, result[:json][:meta])
    assert_nil result[:json][:error]
    assert_equal "success", result[:json][:status]
  end

  # --- Created ---

  def test_created_returns_201
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Created(resource: { id: 1 })
    assert_equal :created, result[:status]
  end

  def test_created_wraps_in_uniform_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Created(resource: { id: 1 })
    assert_equal({ data: { id: 1 }, error: nil, status: "success" }, result[:json])
  end

  def test_created_without_meta_has_no_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Created(resource: { id: 1 })
    refute result[:json].key?(:meta)
  end

  def test_created_with_meta_includes_meta_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Created(resource: { id: 1 }, meta: { token: "xyz" })
    assert_equal({ id: 1 }, result[:json][:data])
    assert_equal({ token: "xyz" }, result[:json][:meta])
    assert_equal "success", result[:json][:status]
  end

  # --- Accepted ---

  def test_accepted_returns_202
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Accepted()
    assert_equal :accepted, result[:status]
  end

  def test_accepted_without_resource_wraps_nil_data
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Accepted()
    assert_equal({ data: nil, error: nil, status: "success" }, result[:json])
  end

  def test_accepted_with_resource_wraps_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Accepted(resource: { job_id: "abc" })
    assert_equal({ data: { job_id: "abc" }, error: nil, status: "success" }, result[:json])
  end

  # --- NoContent ---

  def test_no_content_returns_204
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.NoContent()
    assert_equal :no_content, result[:status]
  end

  def test_no_content_has_no_json_body
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.NoContent()
    refute result.key?(:json)
  end

  # --- UnprocessableContent ---

  def test_unprocessable_content_returns_422
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.UnprocessableContent(errors: { name: ["can't be blank"] })
    assert_equal :unprocessable_content, result[:status]
  end

  def test_unprocessable_content_wraps_errors_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    errors = { name: ["can't be blank"] }
    result = formatter.UnprocessableContent(errors:)
    assert_equal({ data: nil, error: errors, status: "error" }, result[:json])
  end

  # --- NotFound ---

  def test_not_found_returns_404
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.NotFound(errors: { base: ["not found"] })
    assert_equal :not_found, result[:status]
  end

  def test_not_found_wraps_errors_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.NotFound(errors: { base: ["not found"] })
    assert_equal({ data: nil, error: { base: ["not found"] }, status: "error" }, result[:json])
  end

  # --- Forbidden ---

  def test_forbidden_returns_403
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Forbidden(errors: { base: ["not authorized"] })
    assert_equal :forbidden, result[:status]
  end

  def test_forbidden_wraps_errors_in_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Wrapped)
    result = formatter.Forbidden(errors: { base: ["not authorized"] })
    assert_equal({ data: nil, error: { base: ["not authorized"] }, status: "error" }, result[:json])
  end
end

class WrappedFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::Wrapped.ancestors, ActionFigure::Formatter
  end
end
