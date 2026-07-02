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

class MinitestStatusRegistryTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  # Locks the full generated set: every statuses entry gets a working assert_*
  # and refute_*, including Conflict / PaymentRequired / NoContent.
  ActionFigure::Testing.statuses.each do |name, status|
    define_method(:"test_assert_and_refute_#{name}") do
      send(:"assert_#{name}", { status: status })
      send(:"refute_#{name}", { status: :some_other_status })
    end
  end
end

class MinitestStatusGuardAndNegationTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_assert_status_fails_clearly_for_non_hash
    error = assert_raises(Minitest::Assertion) { assert_Ok("nope") }
    assert_includes error.message, "result hash"
  end

  def test_refute_Ok_passes_when_status_differs
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Created(resource: {})
    end

    refute_Ok(action.call)
  end

  def test_refute_Ok_fails_when_status_matches
    action = Class.new do
      include ActionFigure[:jsend]

      def call = Ok(resource: {})
    end

    error = assert_raises(Minitest::Assertion) { refute_Ok(action.call) }
    assert_includes error.message, ":ok"
  end
end

class MinitestNewBuiltinStatusTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_new_builtin_status_assertions_exist
    assert_Gone({ status: :gone })
    assert_Locked({ status: :locked })
    assert_UnavailableForLegalReasons({ status: :unavailable_for_legal_reasons })
  end

  def test_new_builtin_negated_assertions_exist
    refute_Gone({ status: :ok })
    refute_Locked({ status: :ok })
    refute_UnavailableForLegalReasons({ status: :ok })
  end
end

class MinitestJsonAssertionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def build_action(&block)
    Class.new do
      include ActionFigure[:jsend]

      define_method(:call, &block)
    end
  end

  def test_assert_action_json_passes_on_matching_subset
    result = build_action { Ok(resource: { name: "Tad", id: 1 }) }.call

    assert_action_json(result, status: "success")
    assert_action_json(result, data: { name: "Tad", id: 1 })
  end

  def test_assert_action_json_matches_nested_subset
    result = build_action { Ok(resource: { name: "Tad", id: 1 }) }.call

    assert_action_json(result, status: "success", data: { name: "Tad" })
  end

  def test_assert_action_json_supports_regexp_values
    result = build_action { Ok(resource: { email: "jane@example.com" }) }.call

    assert_action_json(result, data: { email: /@example\.com\z/ })
  end

  def test_assert_action_json_fails_when_shape_differs
    result = build_action { Ok(resource: {}) }.call

    error = assert_raises(Minitest::Assertion) { assert_action_json(result, status: "fail") }
    assert_includes error.message, "fail"
  end

  def test_assert_action_json_fails_clearly_for_non_result
    error = assert_raises(Minitest::Assertion) { assert_action_json("nope", status: "success") }
    assert_includes error.message, "result hash"
  end

  def test_assert_action_json_fails_clearly_when_json_key_missing
    error = assert_raises(Minitest::Assertion) { assert_action_json({ status: :no_content }, foo: 1) }
    assert_includes error.message, ":json"
  end

  def test_refute_action_json_passes_when_subset_does_not_match
    result = build_action { Ok(resource: { name: "Tad" }) }.call

    refute_action_json(result, status: "fail")
  end
end
