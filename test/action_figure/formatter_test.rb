# frozen_string_literal: true

require "test_helper"

class FormatterModuleTest < Minitest::Test
  def test_required_methods_lists_the_structural_contract
    expected = %i[Ok Created Accepted error_response]
    assert_equal expected, ActionFigure::Formatter::REQUIRED_METHODS
  end

  def test_no_content_returns_no_content_status
    formatter = Object.new.extend(ActionFigure::Formatter)
    result = formatter.NoContent
    assert_equal :no_content, result[:status]
  end

  def test_no_content_has_no_json_body
    formatter = Object.new.extend(ActionFigure::Formatter)
    result = formatter.NoContent
    refute result.key?(:json)
  end
end
