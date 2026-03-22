# Custom Formatter Support — Design Spec

**Date:** 2026-03-22
**Status:** Approved

---

## Overview

Add first-class support for custom response formatters in ActionFigure. This includes a base `ActionFigure::Formatter` module that establishes the formatter interface, interface validation at registration time, a `config.register` shorthand, and an `api_version` macro for formatters that need it.

---

## Goals

- Make the formatter interface explicit and discoverable
- Catch missing methods at registration time, not at runtime
- Let users register and configure custom formatters in one place
- Provide `api_version` as an opt-in affordance for custom formatters
- Include `ActionFigure::Formatter` in the existing JSend and JSON:API formatters

---

## Components

### `ActionFigure::Formatter`

A module included in formatter modules. Provides:

- `NoContent` default — `{ status: :no_content }` — identical across all formats
- `REQUIRED_METHODS` constant — the six methods every formatter must implement (the seventh, `NoContent`, is provided as a default and therefore not required):
  `%i[Ok Created Accepted UnprocessableContent NotFound Forbidden]`

```ruby
module ActionFigure
  module Formatter
    REQUIRED_METHODS = %i[Ok Created Accepted UnprocessableContent NotFound Forbidden].freeze

    def NoContent
      { status: :no_content }
    end
  end
end
```

### Interface validation at `register_formatter`

`ActionFigure.register_formatter` validates all formatters before registering any — a batch with one invalid formatter raises without partially registering the others. Raises `ArgumentError` listing missing methods. `method_defined?` traverses the ancestor chain, so methods inherited via `include ActionFigure::Formatter` (e.g. `NoContent`) count as defined.

```ruby
def register_formatter(**formatters)
  # Validate all before registering any
  formatters.each do |name, mod|
    missing = Formatter::REQUIRED_METHODS.reject { |m| mod.method_defined?(m) }
    raise ArgumentError, "#{mod} is missing formatter methods: #{missing.join(', ')}" if missing.any?
  end
  # existing registration logic (second pass)
end
```

### `config.register` shorthand

`Configuration::Settings` gains a `register` method that delegates to `ActionFigure.register_formatter`, allowing formatter registration and format selection in one `configure` block:

```ruby
ActionFigure.configure do |config|
  config.register(custom: MyFormatter)
  config.format = :custom
end
```

Equivalent to, but more ergonomic than:

```ruby
ActionFigure.register_formatter(custom: MyFormatter)
ActionFigure.configure { |c| c.format = :custom }
```

`Settings#register` calls `ActionFigure.register_formatter` directly via the top-level constant. This is safe at runtime given load order (`formatter.rb` and `format_registry.rb` are both required before `configuration.rb` is used at runtime), but tests for `Settings#register` in isolation must ensure `ActionFigure::FormatRegistry` is loaded.

### `api_version` macro

An opt-in affordance for formatters that include an API version in their response envelope (e.g. Google JSON Style Guide).

**Class-level macro** — declared on the action class:

```ruby
class Users::Create
  include ActionFigure[:google]
  api_version "2.0"
end
```

**Global config** — applies to all actions using a formatter that reads it:

```ruby
ActionFigure.configure do |config|
  config.api_version = "2.0"
end
```

**Resolution order** — class-level takes precedence over global:

```ruby
# Inside a formatter:
self.class.api_version || ActionFigure.configuration.api_version
```

`api_version` is added to `Core::ClassMethods` as a dual-purpose setter/reader macro. Called with an argument it stores the value; called without an argument it returns it (defaulting to `nil`):

```ruby
def api_version(value = :_unset)
  value == :_unset ? @api_version : (@api_version = value)
end
```

The built-in JSend and JSON:API formatters ignore it — it exists for custom formatter authors.

`Configuration::Settings` adds `api_version` as a plain `attr_accessor` (defaulting to `nil`). The deliberate asymmetry with the class macro: the global setting uses `nil` to mean "not set" rather than an `_unset` sentinel. Setting `config.api_version = nil` explicitly clears it. The resolution chain `self.class.api_version || ActionFigure.configuration.api_version` treats both a missing class-level value and a `nil` global as absent — this is intentional.

### JSend and JSON:API updated

Both existing formatters include `ActionFigure::Formatter` and keep an explicit `NoContent` that calls `super`, so all seven methods remain visible in the source:

```ruby
module ActionFigure
  module Formatters
    module Jsend
      include ActionFigure::Formatter

      def NoContent
        super
      end

      # ... Ok, Created, Accepted, UnprocessableContent, NotFound, Forbidden
    end
  end
end
```

---

## Usage example — custom formatter

```ruby
module MyGoogleFormatter
  include ActionFigure::Formatter

  def Ok(resource:, meta: nil)
    body = { data: resource }
    body[:apiVersion] = self.class.api_version || ActionFigure.configuration.api_version
    body[:meta] = meta if meta
    { json: body, status: :ok }
  end

  def Created(resource:, meta: nil)
    body = { data: resource }
    body[:apiVersion] = self.class.api_version || ActionFigure.configuration.api_version
    body[:meta] = meta if meta
    { json: body, status: :created }
  end

  def Accepted(resource: nil)
    body = resource.nil? ? {} : { data: resource }
    { json: body, status: :accepted }
  end

  def NoContent
    super
  end

  def UnprocessableContent(errors:)
    { json: { error: { code: 422, message: "Unprocessable", errors: format_errors(errors) } }, status: :unprocessable_content }
  end

  def NotFound(errors:)
    { json: { error: { code: 404, message: "Not found", errors: format_errors(errors) } }, status: :not_found }
  end

  def Forbidden(errors:)
    { json: { error: { code: 403, message: "Forbidden", errors: format_errors(errors) } }, status: :forbidden }
  end

  private

  def format_errors(errors)
    errors.flat_map { |field, messages| messages.map { |msg| { domain: field, message: msg } } }
  end
end

ActionFigure.configure do |config|
  config.register(google: MyGoogleFormatter)
  config.format = :google
  config.api_version = "2.0"
end
```

---

## Files changed

| File | Change |
|---|---|
| `lib/action_figure/formatter.rb` | New — `ActionFigure::Formatter` module |
| `lib/action_figure/configuration.rb` | Add `api_version` to `Settings`; add `Settings#register` |
| `lib/action_figure/core.rb` | Add `api_version` class macro to `Core::ClassMethods` |
| `lib/action_figure/format_registry.rb` | Add interface validation in `register_formatter` |
| `lib/action_figure/formatters/jsend.rb` | Include `ActionFigure::Formatter`; add `def NoContent; super; end` |
| `lib/action_figure/formatters/json_api.rb` | Include `ActionFigure::Formatter`; add `def NoContent; super; end` |
| `lib/action_figure.rb` | Require `formatter.rb` **before** `formatters/jsend` and `formatters/json_api` so `ActionFigure::Formatter::REQUIRED_METHODS` exists when the built-in formatters are registered |
| `test/action_figure/formatter_test.rb` | New — tests for `ActionFigure::Formatter` |
| `test/action_figure/format_registry_test.rb` | Add validation tests |
| `test/action_figure/configuration_test.rb` | Add `api_version` and `register` tests |
| `test/action_figure/core_test.rb` | Add `api_version` macro tests |
| `test/action_figure/formatters/jsend_test.rb` | Update for `include ActionFigure::Formatter` |
| `test/action_figure/formatters/json_api_test.rb` | Update for `include ActionFigure::Formatter` |

---

## Out of scope

- Built-in Google JSON, bare, or other formatter implementations (separate work)
- URL/routing helpers for hypermedia formats (HAL, Siren, OData, JSON-LD)
- ActiveRecord serialization helpers
