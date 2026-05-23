# frozen_string_literal: true

require "test_helper"

class FormatterProtocolTest < Minitest::Test
  BUILTIN_FORMATS = %i[jsend jsonapi default wrapped].freeze

  def test_registered_builtin_formatters_honour_formatter_contract
    BUILTIN_FORMATS.each do |name|
      formatter = ActionFigure.fetch(name)
      ActionFigure::Formatter::REQUIRED_METHODS.each do |method_name|
        assert formatter.method_defined?(method_name),
               "formatter #{name.inspect} must define ##{method_name}"
      end
      assert formatter.method_defined?(:NoContent),
             "formatter #{name.inspect} must define #NoContent (from Formatter)"
    end
  end
end
