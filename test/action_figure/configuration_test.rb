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

  def test_configure_yields_self
    settings = ActionFigure::Configuration::Settings.new

    settings.configure { |c| c.format = :jsonapi }

    assert_equal :jsonapi, settings.format
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

class JsonApiConfigurationTest < Minitest::Test
  def test_actionfigure_jsonapi_returns_a_module
    assert_kind_of Module, ActionFigure[:jsonapi]
  end

  def test_actionfigure_jsonapi_includes_jsonapi_formatter
    action_class = Class.new do
      include ActionFigure[:jsonapi]

      def call(*)
        Ok(resource: { type: "user", id: "1", attributes: { name: "Tad" } })
      end
    end

    result = action_class.call
    assert result[:json].key?(:data)
    refute result[:json].key?(:status)
  end

  def test_global_format_jsonapi_uses_jsonapi_formatter
    original = ActionFigure.configuration.format
    ActionFigure.configure { |c| c.format = :jsonapi }

    action_class = Class.new do
      include ActionFigure

      def call(*)
        Ok(resource: { type: "user", id: "1", attributes: { name: "Tad" } })
      end
    end

    result = action_class.call
    assert result[:json].key?(:data)
    refute result[:json].key?(:status)
  ensure
    ActionFigure.configure { |c| c.format = original }
  end
end
