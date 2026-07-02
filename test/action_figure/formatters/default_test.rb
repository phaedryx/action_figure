# frozen_string_literal: true

require "test_helper"

class DefaultFormatterTest < Minitest::Test
  # --- Ok ---

  def test_ok_returns_200
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Ok(resource: { id: 1 })
    assert_equal :ok, result[:status]
  end

  def test_ok_wraps_resource_in_data_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Ok(resource: { id: 1, name: "Tad" })
    assert_equal({ id: 1, name: "Tad" }, result[:json][:data])
  end

  def test_ok_accepts_activerecord_resource
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = formatter.Ok(resource: user)
    assert_equal :ok, result[:status]
    assert_equal "Tad", result[:json][:data].name
    assert_equal "tad@example.com", result[:json][:data].email
  end

  def test_ok_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Ok(resource: { id: 1 })
    assert result[:json].key?(:data)
    refute result[:json].key?(:meta)
  end

  def test_ok_with_meta_includes_meta_alongside_data
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Ok(resource: { id: 1 }, meta: { next_cursor: "abc123" })
    assert_equal({ id: 1 }, result[:json][:data])
    assert_equal({ next_cursor: "abc123" }, result[:json][:meta])
  end

  # --- Created ---

  def test_created_returns_201
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Created(resource: { id: 1 })
    assert_equal :created, result[:status]
  end

  def test_created_wraps_resource_in_data_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Created(resource: { id: 1 })
    assert_equal({ id: 1 }, result[:json][:data])
  end

  def test_created_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Created(resource: { id: 1 })
    assert result[:json].key?(:data)
    refute result[:json].key?(:meta)
  end

  def test_created_with_meta_includes_meta_alongside_data
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Created(resource: { id: 1 }, meta: { token: "xyz" })
    assert_equal({ id: 1 }, result[:json][:data])
    assert_equal({ token: "xyz" }, result[:json][:meta])
  end

  # --- Accepted ---

  def test_accepted_returns_202
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Accepted()
    assert_equal :accepted, result[:status]
  end

  def test_accepted_without_resource_wraps_nil_in_data_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Accepted()
    assert_equal({ data: nil }, result[:json])
  end

  def test_accepted_with_resource_wraps_in_data_envelope
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Accepted(resource: { job_id: "abc" })
    assert_equal({ job_id: "abc" }, result[:json][:data])
  end

  def test_accepted_with_meta_includes_meta_alongside_data
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Accepted(resource: { job_id: "abc" }, meta: { estimated_time: "5m" })
    assert_equal :accepted, result[:status]
    assert_equal({ job_id: "abc" }, result[:json][:data])
    assert_equal({ estimated_time: "5m" }, result[:json][:meta])
  end

  def test_accepted_without_meta_omits_meta_key
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.Accepted(resource: { job_id: "abc" })
    assert_equal :accepted, result[:status]
    assert result[:json].key?(:data)
    refute result[:json].key?(:meta)
  end

  # --- NoContent ---

  def test_no_content_returns_204
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.NoContent()
    assert_equal :no_content, result[:status]
  end

  def test_no_content_has_no_json_body
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.NoContent()
    refute result.key?(:json)
  end

  # --- error_response ---

  def test_error_response_wraps_errors_under_errors_key
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    result = formatter.error_response(errors: { base: ["nope"] }, status: :not_found)
    assert_equal({ errors: { base: ["nope"] } }, result[:json])
  end

  def test_error_response_uses_the_given_status
    formatter = Object.new.extend(ActionFigure::Formatters::Default)
    assert_equal :conflict, formatter.error_response(errors: {}, status: :conflict)[:status]
    assert_equal :gone, formatter.error_response(errors: {}, status: :gone)[:status]
  end
end

class DefaultFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::Default.ancestors, ActionFigure::Formatter
  end
end
