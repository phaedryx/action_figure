# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"
require "action_controller/railtie"

# --- Minimal Rails App ---

class RailsIntegrationTestApp < Rails::Application
  config.eager_load = false
  config.secret_key_base = "test-secret-key-base"
  config.hosts.clear
  config.logger = Logger.new(nil)
end

RailsIntegrationTestApp.initialize!

# --- Action Classes: Default ---

class DefaultCreateAction
  include ActionFigure[:default]

  params_schema do
    required(:name).filled(:string)
  end

  def create(params:)
    user = User.create!(name: params[:name])
    Created(resource: { id: user.id, name: user.name })
  end
end

class DefaultDestroyAction
  include ActionFigure[:default]

  def destroy(params:)
    User.find(params[:id]).destroy!
    NoContent()
  end
end

# --- Controllers: Default ---

class DefaultUsersController < ActionController::Base
  def create
    render DefaultCreateAction.create(params: request.request_parameters)
  end

  def destroy
    result = DefaultDestroyAction.destroy(params: { id: params[:id] })
    result.key?(:json) ? render(result) : head(result[:status])
  end
end

# --- Action Classes: JSend ---

class JsendCreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:name).filled(:string)
  end

  def create(params:)
    user = User.create!(name: params[:name])
    Created(resource: { id: user.id, name: user.name })
  end
end

class JsendDestroyAction
  include ActionFigure[:jsend]

  def destroy(params:)
    User.find(params[:id]).destroy!
    NoContent()
  end
end

# --- Controllers: JSend ---

class JsendUsersController < ActionController::Base
  def create
    render JsendCreateAction.create(params: request.request_parameters)
  end

  def destroy
    result = JsendDestroyAction.destroy(params: { id: params[:id] })
    result.key?(:json) ? render(result) : head(result[:status])
  end
end

# --- Action Classes: JSON:API ---

class JsonApiCreateAction
  include ActionFigure[:jsonapi]

  params_schema do
    required(:name).filled(:string)
  end

  def create(params:)
    user = User.create!(name: params[:name])
    Created(resource: user)
  end
end

class JsonApiDestroyAction
  include ActionFigure[:jsonapi]

  def destroy(params:)
    User.find(params[:id]).destroy!
    NoContent()
  end
end

# --- Controllers: JSON:API ---

class JsonApiUsersController < ActionController::Base
  def create
    render JsonApiCreateAction.create(params: request.request_parameters)
  end

  def destroy
    result = JsonApiDestroyAction.destroy(params: { id: params[:id] })
    result.key?(:json) ? render(result) : head(result[:status])
  end
end

# --- Action Classes: Wrapped ---

class WrappedCreateAction
  include ActionFigure[:wrapped]

  params_schema do
    required(:name).filled(:string)
  end

  def create(params:)
    user = User.create!(name: params[:name])
    Created(resource: { id: user.id, name: user.name })
  end
end

class WrappedDestroyAction
  include ActionFigure[:wrapped]

  def destroy(params:)
    User.find(params[:id]).destroy!
    NoContent()
  end
end

# --- Controllers: Wrapped ---

class WrappedUsersController < ActionController::Base
  def create
    render WrappedCreateAction.create(params: request.request_parameters)
  end

  def destroy
    result = WrappedDestroyAction.destroy(params: { id: params[:id] })
    result.key?(:json) ? render(result) : head(result[:status])
  end
end

# --- Routes ---

RailsIntegrationTestApp.routes.draw do
  scope "/default" do
    resources :users, only: %i[create destroy], controller: "default_users"
  end

  scope "/jsend" do
    resources :users, only: %i[create destroy], controller: "jsend_users"
  end

  scope "/json_api" do
    resources :users, only: %i[create destroy], controller: "json_api_users"
  end

  scope "/wrapped" do
    resources :users, only: %i[create destroy], controller: "wrapped_users"
  end
end

# --- Tests ---

class DefaultFormatterIntegrationTest < ActionDispatch::IntegrationTest
  include ActionFigure::Testing::Minitest

  def setup
    User.delete_all
  end

  def test_create_returns_201_with_resource
    action_result = DefaultCreateAction.create(params: { name: "Tad" })
    assert_Created(action_result)

    post "/default/users", params: { name: "Tad" }, as: :json
    assert_response :created

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "Tad", body[:data][:name]
  end

  def test_create_returns_422_for_invalid_params
    action_result = DefaultCreateAction.create(params: {})
    assert_UnprocessableContent(action_result)

    post "/default/users", params: {}, as: :json
    assert_response :unprocessable_content

    body = JSON.parse(response.body, symbolize_names: true)
    assert body[:errors].key?(:name), "expected errors to include :name"
  end

  def test_destroy_returns_204_with_empty_body
    user = User.create!(name: "Tad")

    action_result = DefaultDestroyAction.destroy(params: { id: user.id })
    assert_NoContent(action_result)

    another_user = User.create!(name: "Bob")
    delete "/default/users/#{another_user.id}", as: :json
    assert_response :no_content
    assert response.body.blank?
  end
end

class JsendFormatterIntegrationTest < ActionDispatch::IntegrationTest
  include ActionFigure::Testing::Minitest

  def setup
    User.delete_all
  end

  def test_create_returns_201_with_jsend_envelope
    action_result = JsendCreateAction.create(params: { name: "Tad" })
    assert_Created(action_result)

    post "/jsend/users", params: { name: "Tad" }, as: :json
    assert_response :created

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "success", body[:status]
    assert_equal "Tad", body[:data][:name]
  end

  def test_create_returns_422_with_jsend_fail_envelope
    action_result = JsendCreateAction.create(params: {})
    assert_UnprocessableContent(action_result)

    post "/jsend/users", params: {}, as: :json
    assert_response :unprocessable_content

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "fail", body[:status]
    assert body[:data].key?(:name), "expected errors to include :name"
  end

  def test_destroy_returns_204_with_empty_body
    user = User.create!(name: "Tad")

    action_result = JsendDestroyAction.destroy(params: { id: user.id })
    assert_NoContent(action_result)

    another_user = User.create!(name: "Bob")
    delete "/jsend/users/#{another_user.id}", as: :json
    assert_response :no_content
    assert response.body.blank?
  end
end

class JsonApiFormatterIntegrationTest < ActionDispatch::IntegrationTest
  include ActionFigure::Testing::Minitest

  def setup
    User.delete_all
  end

  def test_create_returns_201_with_json_api_envelope
    action_result = JsonApiCreateAction.create(params: { name: "Tad" })
    assert_Created(action_result)

    post "/json_api/users", params: { name: "Tad" }, as: :json
    assert_response :created

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "user", body[:data][:type]
    assert body[:data].key?(:id)
    assert_equal "Tad", body[:data][:attributes][:name]
  end

  def test_create_returns_422_with_json_api_error_objects
    action_result = JsonApiCreateAction.create(params: {})
    assert_UnprocessableContent(action_result)

    post "/json_api/users", params: {}, as: :json
    assert_response :unprocessable_content

    body = JSON.parse(response.body, symbolize_names: true)
    errors = body[:errors]
    assert errors.is_a?(Array), "expected JSON:API errors array"
    assert_equal "422", errors.first[:status]
    assert errors.first[:source].key?(:pointer)
  end

  def test_destroy_returns_204_with_empty_body
    user = User.create!(name: "Tad")

    action_result = JsonApiDestroyAction.destroy(params: { id: user.id })
    assert_NoContent(action_result)

    another_user = User.create!(name: "Bob")
    delete "/json_api/users/#{another_user.id}", as: :json
    assert_response :no_content
    assert response.body.blank?
  end
end

class WrappedFormatterIntegrationTest < ActionDispatch::IntegrationTest
  include ActionFigure::Testing::Minitest

  def setup
    User.delete_all
  end

  def test_create_returns_201_with_wrapped_envelope
    action_result = WrappedCreateAction.create(params: { name: "Tad" })
    assert_Created(action_result)

    post "/wrapped/users", params: { name: "Tad" }, as: :json
    assert_response :created

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "success", body[:status]
    assert_nil body[:errors]
    assert_equal "Tad", body[:data][:name]
  end

  def test_create_returns_422_with_wrapped_error_envelope
    action_result = WrappedCreateAction.create(params: {})
    assert_UnprocessableContent(action_result)

    post "/wrapped/users", params: {}, as: :json
    assert_response :unprocessable_content

    body = JSON.parse(response.body, symbolize_names: true)
    assert_equal "error", body[:status]
    assert_nil body[:data]
    assert body[:errors].key?(:name), "expected errors to include :name"
  end

  def test_destroy_returns_204_with_empty_body
    user = User.create!(name: "Tad")

    action_result = WrappedDestroyAction.destroy(params: { id: user.id })
    assert_NoContent(action_result)

    another_user = User.create!(name: "Bob")
    delete "/wrapped/users/#{another_user.id}", as: :json
    assert_response :no_content
    assert response.body.blank?
  end
end
