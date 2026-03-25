# Configuration

## Overview

ActionFigure exposes global defaults through `ActionFigure.configure`. Every setting can be overridden on a per-class basis, so the global configuration acts as a baseline for your application.

## Configuration Block

```ruby
ActionFigure.configure do |c|
  c.format = :jsend
  c.whiny_extra_params = true
end
```

The block yields an `ActionFigure::Configuration::Settings` instance. Call any combination of setters inside.

## Settings Reference

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `format` | Symbol | `:default` | Default formatter name. Applies to any class that uses bare `include ActionFigure`. |
| `whiny_extra_params` | Boolean | `false` | When `true`, returns an error response for undeclared params instead of silently stripping them. |
| `instrumentation` | Boolean | `false` | When `true`, enables `ActiveSupport::Notifications` events for action classes defined after the change. Requires ActiveSupport. |
| `api_version` | String or nil | `nil` | Global API version tag, readable via `ActionFigure.configuration.api_version`. |

## Registering Formatters via Config

You can register custom formatters inside the configure block with `register`:

```ruby
ActionFigure.configure do |c|
  c.register(custom_format: MyApp::CustomApiFormatter)
end
```

This delegates to `ActionFigure.register_formatter`, making the `:custom_format` format available application-wide. Once registered, set it as the default or use it per-class:

```ruby
c.format = :custom_format
```

## Per-Class Overrides

**Format** -- Pass the desired format when including the module:

```ruby
class Orders::CreateAction
  include ActionFigure[:jsonapi]
end
```

This overrides the global `format` for that single class, regardless of what `ActionFigure.configure` specifies.

**API version** -- Declare a version inside the class body:

```ruby
class Orders::CreateAction
  include ActionFigure

  api_version "2.0"
end
```

This sets the API version for that class. Class-level versions are independent of the global `api_version` setting.

## Rails Initializer Example

An example `config/initializers/action_figure.rb`:

```ruby
ActionFigure.configure do |c|
  # Reject unexpected params with an error response (recommended for development)
  c.whiny_extra_params = Rails.env.local?

  # Tag all actions with the current API version
  c.api_version = "1.0"

  # Turn on ActiveSupport::Notifications instrumentation events for every action call
  c.instrumentation = true

  # Register a custom formatter
  c.register(our_format: MyApp::OurFormatter)

  # Use the custom formatter by default
  c.format = :our_format
end
```
