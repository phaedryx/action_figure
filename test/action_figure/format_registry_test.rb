# frozen_string_literal: true

require "test_helper"

class FormatRegistryFormatsTest < Minitest::Test
  def test_register_and_fetch
    formats = ActionFigure::FormatRegistry::Formats.new
    mod = Module.new

    formats.register_formatter(test_fmt: mod)

    assert_equal mod, formats.fetch(:test_fmt)
  end

  def test_fetch_raises_for_unknown_formatter
    formats = ActionFigure::FormatRegistry::Formats.new

    error = assert_raises(ArgumentError) do
      formats.fetch(:nonexistent)
    end

    assert_match "Unknown formatter: nonexistent", error.message
  end
end

class FormatRegistryModuleTest < Minitest::Test
  def test_register_and_fetch
    host = Module.new.tap { _1.extend(ActionFigure::FormatRegistry) }
    mod = Module.new

    host.register_formatter(test_fmt: mod)

    assert_equal mod, host.fetch(:test_fmt)
  end

  def test_fetch_raises_for_unknown_formatter
    host = Module.new.tap { _1.extend(ActionFigure::FormatRegistry) }

    error = assert_raises(ArgumentError) do
      host.fetch(:nonexistent)
    end

    assert_match "Unknown formatter: nonexistent", error.message
  end
end

class FormatRegistryValidationTest < Minitest::Test
  def test_register_formatter_raises_for_missing_methods
    incomplete = Module.new do
      def Ok(resource:, **) = { json: { data: resource }, status: :ok }
    end

    error = assert_raises(ArgumentError) do
      ActionFigure.register_formatter(incomplete_test: incomplete)
    end

    assert_match "missing formatter methods", error.message
    assert_match "Created", error.message
  end

  def test_register_formatter_does_not_partially_register_on_failure
    complete = Module.new do
      ActionFigure::Formatter::REQUIRED_METHODS.each do |m|
        define_method(m) { |**| { json: {}, status: :ok } }
      end
    end
    incomplete = Module.new

    assert_raises(ArgumentError) do
      ActionFigure.register_formatter(fmt_should_not_register: complete, fmt_incomplete: incomplete)
    end

    assert_raises(ArgumentError) { ActionFigure.fetch(:fmt_should_not_register) }
  end
end
