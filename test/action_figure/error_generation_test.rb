# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"

class ErrorGenerationTest < Minitest::Test
  # A throwaway consumer that mixes in a composed format module, mirroring how an
  # action class gains the response helpers.
  def build_consumer(format)
    Class.new do
      include ActionFigure[format]
    end.new
  end

  def test_named_error_helpers_are_generated_for_each_builtin_format
    %i[default jsend jsonapi wrapped].each do |format|
      consumer = build_consumer(format)
      assert consumer.respond_to?(:NotFound), "#{format} should generate NotFound"
      assert consumer.respond_to?(:Gone),     "#{format} should generate Gone"
      assert consumer.respond_to?(:Locked),   "#{format} should generate Locked"
    end
  end

  def test_generated_helper_routes_through_error_response_with_correct_status
    consumer = build_consumer(:default)
    result = consumer.NotFound(errors: { base: ["x"] })
    assert_equal :not_found, result[:status]
    assert_equal({ errors: { base: ["x"] } }, result[:json])
  end

  def test_generated_helper_for_new_builtin_status
    consumer = build_consumer(:wrapped)
    result = consumer.Gone(errors: { base: ["gone"] })
    assert_equal :gone, result[:status]
    assert_equal({ data: nil, errors: { base: ["gone"] }, status: "error" }, result[:json])
  end

  def test_hand_defined_named_helper_is_not_clobbered_by_generation
    custom = Module.new do
      include ActionFigure::Formatter

      def Ok(resource:) = { json: { data: resource }, status: :ok }
      def Created(resource:) = { json: { data: resource }, status: :created }
      def Accepted(resource: nil) = { json: { data: resource }, status: :accepted }
      def error_response(errors:, status:) = { json: { errors: errors }, status: status }

      # Hand-written, intentionally distinctive body.
      def NotFound(errors:) = { json: { custom: errors }, status: :not_found }
    end

    ActionFigure.register_formatter(custom_notfound: custom)
    consumer = Class.new { include ActionFigure[:custom_notfound] }.new
    result = consumer.NotFound(errors: { base: ["x"] })

    assert_equal({ custom: { base: ["x"] } }, result[:json],
                 "generation must not overwrite a hand-defined NotFound")
  end
end

class RegisterErrorRoundTripTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_registering_bad_gateway_lights_up_every_formatter
    ActionFigure.register_error(:BadGateway, :bad_gateway)
    %i[default jsend jsonapi wrapped].each do |format|
      consumer = Class.new { include ActionFigure[format] }.new
      result = consumer.BadGateway(errors: { base: ["upstream down"] })
      assert_equal :bad_gateway, result[:status], "#{format} should route BadGateway"
    end
  end

  def test_registering_bad_gateway_defines_the_minitest_assertion
    ActionFigure.register_error(:BadGateway, :bad_gateway)
    assert_respond_to self, :assert_BadGateway
    assert_BadGateway({ status: :bad_gateway })
  end

  def test_late_registration_reaches_already_included_action_classes
    consumer = Class.new { include ActionFigure[:default] }.new
    refute_respond_to consumer, :ServiceUnavailable
    ActionFigure.register_error(:ServiceUnavailable, :service_unavailable)
    result = consumer.ServiceUnavailable(errors: { base: ["down"] })
    assert_equal :service_unavailable, result[:status]
    assert_equal({ errors: { base: ["down"] } }, result[:json])
  end

  def test_direct_extension_of_a_formatter_module_exposes_named_helpers
    formatter = Object.new.extend(ActionFigure::Formatters::Jsend)
    result = formatter.NotFound(errors: { base: ["x"] })
    assert_equal :not_found, result[:status]
    assert_equal({ status: "fail", data: { base: ["x"] } }, result[:json])
  end

  def test_testing_statuses_reflects_late_registrations
    ActionFigure.register_error(:NotImplemented, :not_implemented)
    assert_equal :not_implemented, ActionFigure::Testing.statuses[:NotImplemented]
    assert_equal :ok, ActionFigure::Testing.statuses[:Ok]
  end

  def test_format_module_identity_is_stable_across_registration
    before = ActionFigure[:jsend]
    ActionFigure.register_error(:GatewayTimeout, :gateway_timeout)
    assert_same before, ActionFigure[:jsend]
  end
end
