# frozen_string_literal: true

require "test_helper"
require "active_support/notifications"

class ActiveSupportNotificationsTest < Minitest::Test
  def test_notifications_successful_call
    ActionFigure.configuration.activesupport_notifications = true

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
    assert_equal :call, event.payload[:entry_point]
    assert_equal :ok, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.activesupport_notifications = false
  end

  def test_notifications_validation_failure
    ActionFigure.configuration.activesupport_notifications = true

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
    assert_equal :call, event.payload[:entry_point]
    assert_equal :unprocessable_content, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.activesupport_notifications = false
  end

  def test_notifications_explicit_failure_from_call
    ActionFigure.configuration.activesupport_notifications = true

    action_class = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:id).filled(:integer)
      end

      def call(*)
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
    assert_equal :call, event.payload[:entry_point]
    assert_equal :unprocessable_content, event.payload[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.activesupport_notifications = false
  end

  def test_notifications_entry_point_reflects_explicit_entry_point_macro
    ActionFigure.configuration.activesupport_notifications = true

    action_class = Class.new do
      include ActionFigure[:jsend]

      entry_point :lookup

      def lookup(params:)
        Ok(resource: params[:id])
      end
    end

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
      events << event
    end

    action_class.lookup(params: { id: 2 })

    assert_equal 1, events.size
    assert_equal :lookup, events.first.payload[:entry_point]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    ActionFigure.configuration.activesupport_notifications = false
  end

  def test_no_notifications_by_default
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
