# Custom Formatter Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ActionFigure::Formatter` as an explicit base module for formatters, validate the interface at registration time, and expose `api_version` as an opt-in affordance for custom formatter authors.

**Architecture:** `ActionFigure::Formatter` is a plain Ruby module that provides the `NoContent` default and documents the required interface via `REQUIRED_METHODS`. Validation runs in `ActionFigure.register_formatter` before any registration occurs. `api_version` is a dual-purpose setter/reader macro added to `Core::ClassMethods`, mirrored by an `attr_accessor` on `Configuration::Settings`, and readable from formatter instances via `self.class.api_version`.

**Tech Stack:** Ruby 3.1+, Minitest, dry-validation

**Worktree:** All work happens in `action_figure/custom-format/`. Create it from the parent directory with `just new custom-format` before starting.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/action_figure/formatter.rb` | Create | `ActionFigure::Formatter` module — `REQUIRED_METHODS` constant, `NoContent` default |
| `lib/action_figure.rb` | Modify | Require `formatter.rb` before formatter files; add validation to `register_formatter` |
| `lib/action_figure/formatters/jsend.rb` | Modify | Add `include ActionFigure::Formatter`; add explicit `def NoContent; super; end` |
| `lib/action_figure/formatters/json_api.rb` | Modify | Same as above |
| `lib/action_figure/core.rb` | Modify | Add `api_version` dual-purpose macro to `Core::ClassMethods` |
| `lib/action_figure/configuration.rb` | Modify | Add `api_version` attr_accessor; add `Settings#register` |
| `test/action_figure/formatter_test.rb` | Create | Tests for `ActionFigure::Formatter` |
| `test/action_figure/format_registry_test.rb` | Modify | Add validation tests |
| `test/action_figure/core_test.rb` | Modify | Fix broken `CoreRegisterFormatterTest`; add `api_version` macro tests |
| `test/action_figure/formatters/jsend_test.rb` | Modify | Add `ActionFigure::Formatter` inclusion test |
| `test/action_figure/formatters/json_api_test.rb` | Modify | Add `ActionFigure::Formatter` inclusion test |
| `test/action_figure/configuration_test.rb` | Modify | Add `api_version` and `register` tests |

---

## Task 1: `ActionFigure::Formatter` module

**Files:**
- Create: `lib/action_figure/formatter.rb`
- Create: `test/action_figure/formatter_test.rb`
- Modify: `lib/action_figure.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/action_figure/formatter_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class FormatterModuleTest < Minitest::Test
  def test_required_methods_lists_six_expected_symbols
    expected = %i[Ok Created Accepted UnprocessableContent NotFound Forbidden]
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```
bundle exec ruby -Ilib -Itest test/action_figure/formatter_test.rb
```

Expected: `NameError: uninitialized constant ActionFigure::Formatter`

- [ ] **Step 3: Create `lib/action_figure/formatter.rb`**

```ruby
# frozen_string_literal: true

module ActionFigure
  # Base module for ActionFigure response formatters.
  # Include this in your formatter module to get a NoContent default
  # and to signal that your module implements the formatter interface.
  module Formatter
    REQUIRED_METHODS = %i[Ok Created Accepted UnprocessableContent NotFound Forbidden].freeze

    def NoContent
      { status: :no_content }
    end
  end
end
```

- [ ] **Step 4: Add the require to `lib/action_figure.rb`**

Add `require_relative "action_figure/formatter"` after the `format_registry` require and before the formatter files. The order in `lib/action_figure.rb` must be:

```ruby
require_relative "action_figure/version"
require_relative "action_figure/configuration"
require_relative "action_figure/format_registry"
require_relative "action_figure/formatter"
require_relative "action_figure/core"
require_relative "action_figure/formatters/jsend"
require_relative "action_figure/formatters/json_api"
```

- [ ] **Step 5: Run the tests to verify they pass**

```
bundle exec ruby -Ilib -Itest test/action_figure/formatter_test.rb
```

Expected: 3 tests, 0 failures

- [ ] **Step 6: Run the full test suite to confirm nothing is broken**

```
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/action_figure/formatter.rb lib/action_figure.rb test/action_figure/formatter_test.rb
git commit -m "Add ActionFigure::Formatter base module with NoContent default"
```

---

## Task 2: Registration validation

Validate the formatter interface at `ActionFigure.register_formatter` time. Validate all formatters before registering any (atomic batch).

**Files:**
- Modify: `lib/action_figure.rb`
- Modify: `test/action_figure/format_registry_test.rb`
- Modify: `test/action_figure/core_test.rb`

- [ ] **Step 1: Write the failing validation tests**

Add a new test class to the bottom of `test/action_figure/format_registry_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```
bundle exec ruby -Ilib -Itest test/action_figure/format_registry_test.rb
```

Expected: 2 failures — no error is raised yet

- [ ] **Step 3: Add validation to `ActionFigure.register_formatter` in `lib/action_figure.rb`**

Replace the existing `self.register_formatter` method:

```ruby
def self.register_formatter(**formatters)
  formatters.each do |_name, mod|
    missing = Formatter::REQUIRED_METHODS.reject { |m| mod.method_defined?(m) }
    raise ArgumentError, "#{mod} is missing formatter methods: #{missing.join(', ')}" if missing.any?
  end
  formatters.each_key { |name| clear_format_module_cache(name) }
  super
end
```

- [ ] **Step 4: Run the validation tests to verify they pass**

```
bundle exec ruby -Ilib -Itest test/action_figure/format_registry_test.rb
```

Expected: all pass

- [ ] **Step 5: Fix `CoreRegisterFormatterTest` in `test/action_figure/core_test.rb`**

The existing `test_re_registering_formatter_is_reflected_in_subsequent_calls` test registers a formatter with only `Ok` defined, which now fails validation. Replace the `custom_formatter` definition with a complete one:

```ruby
class CoreRegisterFormatterTest < Minitest::Test
  def test_re_registering_formatter_is_reflected_in_subsequent_calls
    ActionFigure[:jsend]  # populate cache

    custom_formatter = Module.new do
      ActionFigure::Formatter::REQUIRED_METHODS.each do |m|
        define_method(m) { |**| { json: { custom: true }, status: :ok } }
      end
      def NoContent = { status: :no_content }
    end

    ActionFigure.register_formatter(jsend: custom_formatter)

    action = Class.new do
      include ActionFigure[:jsend]

      def call(current_user:)
        Ok(resource: { user: current_user })
      end
    end

    result = action.call(current_user: "alice")

    assert result[:json][:custom]
  ensure
    ActionFigure.register_formatter(jsend: ActionFigure::Formatters::Jsend)
    ActionFigure.clear_format_module_cache(:jsend)
  end
end
```

- [ ] **Step 6: Run the full test suite**

```
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/action_figure.rb test/action_figure/format_registry_test.rb test/action_figure/core_test.rb
git commit -m "Validate formatter interface at registration time"
```

---

## Task 3: Include `ActionFigure::Formatter` in JSend and JSON:API

Add `include ActionFigure::Formatter` to both formatters and add explicit `def NoContent; super; end` so all seven methods are visible in source.

**Files:**
- Modify: `lib/action_figure/formatters/jsend.rb`
- Modify: `lib/action_figure/formatters/json_api.rb`
- Modify: `test/action_figure/formatters/jsend_test.rb`
- Modify: `test/action_figure/formatters/json_api_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to the bottom of `test/action_figure/formatters/jsend_test.rb`:

```ruby
class JsendFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::Jsend.ancestors, ActionFigure::Formatter
  end
end
```

Add to the bottom of `test/action_figure/formatters/json_api_test.rb`:

```ruby
class JsonApiFormatterAncestorsTest < Minitest::Test
  def test_includes_action_figure_formatter
    assert_includes ActionFigure::Formatters::JsonApi.ancestors, ActionFigure::Formatter
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```
bundle exec ruby -Ilib -Itest test/action_figure/formatters/jsend_test.rb test/action_figure/formatters/json_api_test.rb
```

Expected: 2 failures — `ActionFigure::Formatter` not in ancestors

- [ ] **Step 3: Update `lib/action_figure/formatters/jsend.rb`**

Add `include ActionFigure::Formatter` at the top of the module body, and replace the existing `def NoContent` with one that calls `super`:

```ruby
# frozen_string_literal: true

module ActionFigure
  module Formatters
    # Implements JSend response helpers for use in action classes.
    module Jsend
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { status: "success", data: resource }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { status: "success", data: resource }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil)
        body = { status: "success" }
        body[:data] = resource unless resource.nil?
        { json: body, status: :accepted }
      end

      def NoContent
        super
      end

      def UnprocessableContent(errors:)
        { json: { status: "fail", data: errors }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { status: "fail", data: errors }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { status: "fail", data: errors }, status: :forbidden }
      end
    end
  end
end
```

- [ ] **Step 4: Update `lib/action_figure/formatters/json_api.rb`**

Add `include ActionFigure::Formatter` at the top of the module body, and replace the existing `def NoContent` with one that calls `super`:

```ruby
# frozen_string_literal: true

require_relative "json_api/resource"

module ActionFigure
  module Formatters
    # Implements JSON:API response helpers for use in action classes.
    module JsonApi
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil)
        body = { data: Resource.serialize(resource) }
        body[:meta] = meta if meta
        { json: body, status: :ok }
      end

      def Created(resource:, meta: nil)
        body = { data: Resource.serialize(resource) }
        body[:meta] = meta if meta
        { json: body, status: :created }
      end

      def Accepted(resource: nil)
        body = resource.nil? ? {} : { data: Resource.serialize(resource) }
        { json: body, status: :accepted }
      end

      def NoContent
        super
      end

      def UnprocessableContent(errors:)
        { json: { errors: convert_errors(errors, "422") }, status: :unprocessable_content }
      end

      def NotFound(errors:)
        { json: { errors: convert_errors(errors, "404") }, status: :not_found }
      end

      def Forbidden(errors:)
        { json: { errors: convert_errors(errors, "403") }, status: :forbidden }
      end

      private

      def convert_errors(errors, status)
        errors.flat_map do |field, messages|
          pointer = field.to_sym == :base ? "/data" : "/data/attributes/#{field}"
          messages.map do |message|
            {
              status: status,
              detail: message,
              source: { pointer: pointer }
            }
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run the full test suite**

```
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/action_figure/formatters/jsend.rb lib/action_figure/formatters/json_api.rb \
        test/action_figure/formatters/jsend_test.rb test/action_figure/formatters/json_api_test.rb
git commit -m "Include ActionFigure::Formatter in Jsend and JsonApi formatters"
```

---

## Task 4: `api_version` class macro

Add `api_version` as a dual-purpose setter/reader macro on `Core::ClassMethods`. When called with an argument it sets; when called without it reads (defaulting to `nil`).

**Files:**
- Modify: `lib/action_figure/core.rb`
- Modify: `test/action_figure/core_test.rb`

- [ ] **Step 1: Write the failing tests**

Add a new test class to the bottom of `test/action_figure/core_test.rb`:

```ruby
class CoreApiVersionTest < Minitest::Test
  def test_api_version_returns_nil_by_default
    action = Class.new { include ActionFigure[:jsend] }

    assert_nil action.api_version
  end

  def test_api_version_setter_stores_value
    action = Class.new do
      include ActionFigure[:jsend]
      api_version "2.0"
    end

    assert_equal "2.0", action.api_version
  end

  def test_api_version_is_independent_between_classes
    action_a = Class.new do
      include ActionFigure[:jsend]
      api_version "1.0"
    end

    action_b = Class.new do
      include ActionFigure[:jsend]
      api_version "2.0"
    end

    assert_equal "1.0", action_a.api_version
    assert_equal "2.0", action_b.api_version
  end

  def test_api_version_accessible_from_formatter_instance
    action = Class.new do
      include ActionFigure[:jsend]
      api_version "3.0"

      def call
        Ok(resource: { version: self.class.api_version })
      end
    end

    result = action.call
    assert_equal "3.0", result[:json][:data][:version]
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```
bundle exec ruby -Ilib -Itest test/action_figure/core_test.rb
```

Expected: 4 failures — `NoMethodError: undefined method 'api_version'`

- [ ] **Step 3: Add `api_version` macro to `Core::ClassMethods` in `lib/action_figure/core.rb`**

Add after the `entry_point_name` reader method (around line 85):

```ruby
def api_version(value = :_unset)
  value == :_unset ? @api_version : (@api_version = value)
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```
bundle exec ruby -Ilib -Itest test/action_figure/core_test.rb
```

Expected: all pass

- [ ] **Step 5: Run the full test suite**

```
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/action_figure/core.rb test/action_figure/core_test.rb
git commit -m "Add api_version class macro to Core::ClassMethods"
```

---

## Task 5: `api_version` global config and `config.register`

Add `api_version` as a plain `attr_accessor` on `Configuration::Settings` (nil = not set). Add `Settings#register` that delegates to `ActionFigure.register_formatter`.

**Files:**
- Modify: `lib/action_figure/configuration.rb`
- Modify: `test/action_figure/configuration_test.rb`

- [ ] **Step 1: Write the failing tests**

Add two new test classes to the bottom of `test/action_figure/configuration_test.rb`:

```ruby
class ConfigurationApiVersionTest < Minitest::Test
  def test_api_version_defaults_to_nil
    settings = ActionFigure::Configuration::Settings.new

    assert_nil settings.api_version
  end

  def test_api_version_is_settable
    settings = ActionFigure::Configuration::Settings.new

    settings.api_version = "2.0"

    assert_equal "2.0", settings.api_version
  end

  def test_global_api_version_accessible_via_configuration
    original = ActionFigure.configuration.api_version
    ActionFigure.configure { |c| c.api_version = "2.0" }

    assert_equal "2.0", ActionFigure.configuration.api_version
  ensure
    ActionFigure.configure { |c| c.api_version = original }
  end
end

class ConfigurationRegisterTest < Minitest::Test
  def test_register_makes_formatter_available_via_fetch
    complete = Module.new do
      ActionFigure::Formatter::REQUIRED_METHODS.each do |m|
        define_method(m) { |**| { json: {}, status: :ok } }
      end
    end

    ActionFigure.configure do |config|
      config.register(config_register_test: complete)
    end

    assert_equal complete, ActionFigure.fetch(:config_register_test)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```
bundle exec ruby -Ilib -Itest test/action_figure/configuration_test.rb
```

Expected: failures for `api_version` and `register`

- [ ] **Step 3: Update `lib/action_figure/configuration.rb`**

Add `api_version` to the `attr_accessor` line and add the `register` method:

```ruby
# frozen_string_literal: true

module ActionFigure
  # Provides global configuration for ActionFigure via ActionFigure.configure.
  module Configuration
    # Holds ActionFigure configuration values.
    class Settings
      attr_accessor :format, :whiny_extra_params, :api_version

      def initialize
        @format = :jsend
        @whiny_extra_params = false
      end

      def configure
        yield self
      end

      def register(**formatters)
        ActionFigure.register_formatter(**formatters)
      end
    end

    def configure(&)
      configuration.configure(&)
    end

    def configuration
      @configuration ||= Settings.new
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```
bundle exec ruby -Ilib -Itest test/action_figure/configuration_test.rb
```

Expected: all pass

- [ ] **Step 5: Run the full test suite**

```
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/action_figure/configuration.rb test/action_figure/configuration_test.rb
git commit -m "Add api_version config and config.register shorthand"
```

---

## Done

All five tasks complete. The full test suite should be green. The feature is ready for PR.

To create the PR from the `custom-format` worktree:

```bash
gh pr create --title "Add custom formatter support with ActionFigure::Formatter base module"
```
