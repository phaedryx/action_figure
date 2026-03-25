# frozen_string_literal: true

require "test_helper"
require "action_figure/testing/minitest"

class MinitestHelpersPassTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_assert_Ok_passes_for_ok_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Ok(resource: { id: 1 })
    end

    result = action.call
    assert_Ok(result)
  end

  def test_assert_Created_passes_for_created_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Created(resource: { id: 1 })
    end

    result = action.call
    assert_Created(result)
  end

  def test_assert_Accepted_passes_for_accepted_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Accepted()
    end

    result = action.call
    assert_Accepted(result)
  end

  def test_assert_NoContent_passes_for_no_content_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = NoContent()
    end

    result = action.call
    assert_NoContent(result)
  end

  def test_assert_UnprocessableContent_passes_for_unprocessable_content_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = UnprocessableContent(errors: { name: ["can't be blank"] })
    end

    result = action.call
    assert_UnprocessableContent(result)
  end

  def test_assert_NotFound_passes_for_not_found_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = NotFound(errors: { base: ["not found"] })
    end

    result = action.call
    assert_NotFound(result)
  end

  def test_assert_Forbidden_passes_for_forbidden_result
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Forbidden(errors: { base: ["not allowed"] })
    end

    result = action.call
    assert_Forbidden(result)
  end
end

class MinitestHelpersFailureMessageTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_assert_Ok_fails_with_informative_message_when_status_wrong
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Created(resource: { id: 1 })
    end

    result = action.call
    error = assert_raises(Minitest::Assertion) { assert_Ok(result) }

    assert_includes error.message, ":ok"
    assert_includes error.message, ":created"
  end

  def test_assert_UnprocessableContent_fails_with_informative_message_when_status_wrong
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Ok(resource: {})
    end

    result = action.call
    error = assert_raises(Minitest::Assertion) { assert_UnprocessableContent(result) }

    assert_includes error.message, ":unprocessable_content"
    assert_includes error.message, ":ok"
  end
end
