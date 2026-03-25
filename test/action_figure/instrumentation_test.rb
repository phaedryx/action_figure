# frozen_string_literal: true

require "test_helper"
require "active_support/notifications"

class InstrumentationTest < Minitest::Test
  def test_instruments_successful_call
    ActionFigure.configuration.instrumentation = true

    action_class = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
      end

      def call(params:)
        Ok(resource: { id: params[:id] })
      end
    end

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
      events << event
    end

    action_class.call(params: { id: 1 })

    assert_equal 1, events.size
    event = events.first
    assert_equal "process.action_figure", event.name
    assert_equal :ok, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.instrumentation = false
  end

  def test_instruments_validation_failure
    ActionFigure.configuration.instrumentation = true

    action_class = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
      end

      def call(params:)
        Ok(resource: { id: params[:id] })
      end
    end

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
      events << event
    end

    action_class.call(params: { id: "not-an-integer" })

    assert_equal 1, events.size
    event = events.first
    assert_equal :unprocessable_content, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.instrumentation = false
  end

  def test_instruments_explicit_failure_from_call
    ActionFigure.configuration.instrumentation = true

    action_class = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
      end

      def call(params:)
        UnprocessableContent(errors: { id: ["oops"] })
      end
    end

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
      events << event
    end

    action_class.call(params: { id: 1 })

    assert_equal 1, events.size
    event = events.first
    assert_equal :unprocessable_content, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.instrumentation = false
  end

  def test_no_instrumentation_by_default
    action_class = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
      end

      def call(params:)
        Ok(resource: { id: params[:id] })
      end
    end

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
      events << event
    end

    action_class.call(params: { id: 1 })

    assert_empty events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
