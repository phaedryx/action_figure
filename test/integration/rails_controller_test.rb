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

# --- Routes ---

RailsIntegrationTestApp.routes.draw do
  scope "/default" do
    resources :users, only: %i[create destroy], controller: "default_users"
  end

  scope "/jsend" do
    resources :users, only: %i[create destroy], controller: "jsend_users"
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
