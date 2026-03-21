# frozen_string_literal: true

require "test_helper"

class ConfigurationSettingsTest < Minitest::Test
  def test_default_format_is_jsend
    settings = ActionFigure::Configuration::Settings.new

    assert_equal :jsend, settings.format
  end

  def test_default_whiny_extra_params_is_false
    settings = ActionFigure::Configuration::Settings.new

    assert_equal false, settings.whiny_extra_params
  end

  def test_format_is_settable
    settings = ActionFigure::Configuration::Settings.new

    settings.format = :jsonapi

    assert_equal :jsonapi, settings.format
  end

  def test_whiny_extra_params_is_settable
    settings = ActionFigure::Configuration::Settings.new

    settings.whiny_extra_params = true

    assert_equal true, settings.whiny_extra_params
  end
end

class ConfigurationModuleTest < Minitest::Test
  def test_configuration_returns_settings_instance
    host = Module.new.tap { _1.extend(ActionFigure::Configuration) }

    assert_instance_of ActionFigure::Configuration::Settings, host.configuration
  end

  def test_configure_yields_settings
    host = Module.new.tap { _1.extend(ActionFigure::Configuration) }

    host.configure { |c| c.format = :jsonapi }

    assert_equal :jsonapi, host.configuration.format
  end
end
