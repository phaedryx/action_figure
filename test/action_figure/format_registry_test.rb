# frozen_string_literal: true

require "test_helper"

class FormatRegistryFormatsTest < Minitest::Test
  def test_register_and_fetch
    formats = ActionFigure::FormatRegistry::Formats.new
    mod = Module.new

    formats.register(:test_fmt, mod)

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

    host.register(:test_fmt, mod)

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
