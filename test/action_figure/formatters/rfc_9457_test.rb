# frozen_string_literal: true

require "test_helper"
require "action_figure/formatters/rfc_9457"

class Rfc9457FormatterTest < Minitest::Test
  def formatter
    Object.new.extend(ActionFigure::Formatters::Rfc9457)
  end

  # --- Ok ---

  def test_ok_returns_200
    result = formatter.Ok(resource: { id: 1 })
    assert_equal :ok, result[:status]
  end

  def test_ok_derives_type_and_title_from_hash_resource
    result = formatter.Ok(resource: { id: 1 })
    assert_equal "resource-ok", result[:json][:type]
    assert_equal "Resource ok", result[:json][:title]
  end

  def test_ok_places_hash_resource_under_data_key
    result = formatter.Ok(resource: { id: 1 })
    assert_equal({ id: 1 }, result[:json][:data])
  end

  def test_ok_derives_type_and_key_from_model_class
    user = User.new(name: "Tad")
    result = formatter.Ok(resource: user)
    assert_equal "user-ok", result[:json][:type]
    assert_equal "User ok",  result[:json][:title]
    assert_equal user,       result[:json][:user]
    refute result[:json].key?(:data)
  end

  def test_ok_as_kwarg_overrides_derived_name
    result = formatter.Ok(resource: { id: 1 }, as: :project)
    assert_equal "project-ok",  result[:json][:type]
    assert_equal "Project ok",  result[:json][:title]
    assert_equal({ id: 1 },     result[:json][:project])
    refute result[:json].key?(:data)
  end

  def test_ok_as_kwarg_with_underscored_name_dasherizes_type_and_title
    result = formatter.Ok(resource: { id: 1 }, as: :user_profile)
    assert_equal "user-profile-ok",  result[:json][:type]
    assert_equal "User profile ok",  result[:json][:title]
    assert_equal({ id: 1 },          result[:json][:user_profile])
  end

  def test_ok_type_kwarg_overrides_derived_type
    result = formatter.Ok(resource: { id: 1 }, type: "my-type")
    assert_equal "my-type", result[:json][:type]
  end

  def test_ok_title_kwarg_overrides_derived_title
    result = formatter.Ok(resource: { id: 1 }, title: "My title")
    assert_equal "My title", result[:json][:title]
  end

  def test_ok_without_meta_omits_meta_key
    result = formatter.Ok(resource: { id: 1 })
    refute result[:json].key?(:meta)
  end

  def test_ok_with_meta_includes_meta_key
    result = formatter.Ok(resource: { id: 1 }, meta: { page: 2 })
    assert_equal({ page: 2 }, result[:json][:meta])
  end

  def test_ok_has_no_content_type_key
    result = formatter.Ok(resource: { id: 1 })
    refute result.key?(:content_type)
  end

  # --- Created ---

  def test_created_returns_201
    result = formatter.Created(resource: { id: 1 })
    assert_equal :created, result[:status]
  end

  def test_created_derives_type_and_title_from_hash_resource
    result = formatter.Created(resource: { id: 1 })
    assert_equal "resource-created", result[:json][:type]
    assert_equal "Resource created", result[:json][:title]
  end

  def test_created_derives_type_and_key_from_model_class
    user = User.new(name: "Tad")
    result = formatter.Created(resource: user)
    assert_equal "user-created", result[:json][:type]
    assert_equal "User created", result[:json][:title]
    assert_equal user,           result[:json][:user]
    refute result[:json].key?(:data)
  end

  def test_created_with_namespaced_class
    # Admin::UserProfile -> key :admin_user_profile, type "admin-user-profile-created"
    klass = Class.new do
      def self.name = "Admin::UserProfile"
    end
    obj = klass.new
    result = formatter.Created(resource: obj)
    assert_equal "admin-user-profile-created", result[:json][:type]
    assert_equal "Admin user profile created", result[:json][:title]
    assert result[:json].key?(:admin_user_profile)
  end

  def test_created_strips_action_suffix_from_resource_class
    klass = Class.new do
      def self.name = "Projects::CreateAction"
    end
    result = formatter.Created(resource: klass.new)
    assert_equal "projects-create-created", result[:json][:type]
    assert result[:json].key?(:projects_create)
  end

  def test_created_anonymous_class_falls_back_to_resource
    klass = Class.new # name is nil
    result = formatter.Created(resource: klass.new)
    assert_equal "resource-created", result[:json][:type]
    assert_equal "Resource created", result[:json][:title]
    assert result[:json].key?(:data)
  end

  # --- Accepted ---

  def test_accepted_returns_202
    result = formatter.Accepted()
    assert_equal :accepted, result[:status]
  end

  def test_accepted_with_no_resource_uses_generic_defaults
    result = formatter.Accepted()
    assert_equal "resource-accepted", result[:json][:type]
    assert_equal "Resource accepted", result[:json][:title]
    refute result[:json].key?(:data)
  end

  def test_accepted_with_resource_places_it_under_derived_key
    user = User.new(name: "Tad")
    result = formatter.Accepted(resource: user)
    assert_equal "user-accepted", result[:json][:type]
    assert result[:json].key?(:user)
  end

  # --- NoContent ---

  def test_no_content_returns_204
    result = formatter.NoContent()
    assert_equal :no_content, result[:status]
  end

  def test_no_content_has_no_json_body
    result = formatter.NoContent()
    refute result.key?(:json)
  end

  # --- error_response ---

  def test_error_response_includes_type_title_status_members
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: { id: ["x"] }, status: :not_found)
    assert_equal "Not Found",     result[:json][:title]
    assert_equal 404,             result[:json][:status]
    assert result[:json][:type].end_with?("-not-found-error")
    assert_equal "application/problem+json", result[:content_type]
  end

  def test_error_response_omits_errors_key_when_nil
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found)
    refute result[:json].key?(:errors)
  end

  def test_error_response_includes_errors_when_given
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: { id: ["not found"] }, status: :not_found)
    assert_equal({ id: ["not found"] }, result[:json][:errors])
  end

  def test_error_response_includes_detail_when_given
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found, detail: "Project 42 not found")
    assert_equal "Project 42 not found", result[:json][:detail]
  end

  def test_error_response_includes_instance_when_given
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found, instance: "/projects/42")
    assert_equal "/projects/42", result[:json][:instance]
  end

  def test_error_response_omits_detail_and_instance_when_not_given
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found)
    refute result[:json].key?(:detail)
    refute result[:json].key?(:instance)
  end

  def test_error_response_passes_arbitrary_extra_kwargs_as_extension_members
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found, balance: 0)
    assert_equal 0, result[:json][:balance]
  end

  def test_error_response_type_overridden_by_kwarg
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found, type: "https://example.com/not-found")
    assert_equal "https://example.com/not-found", result[:json][:type]
  end

  def test_error_response_title_overridden_by_kwarg
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :not_found, title: "Custom Not Found")
    assert_equal "Custom Not Found", result[:json][:title]
  end

  def test_error_response_status_member_is_numeric
    f = Object.new.extend(ActionFigure::Formatters::Rfc9457)
    result = f.error_response(errors: nil, status: :conflict)
    assert_equal 409, result[:json][:status]
  end
end

class Rfc9457FormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::Rfc9457.ancestors, ActionFigure::Formatter
  end
end
