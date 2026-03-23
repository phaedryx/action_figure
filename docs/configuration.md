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
| `format` | Symbol | `:jsend` | Default formatter name. Applies to any class that uses bare `include ActionFigure`. |
| `whiny_extra_params` | Boolean | `false` | When `true`, returns an error response for undeclared params instead of silently stripping them. |
| `api_version` | String or nil | `nil` | Global API version exposed to all action classes. |

## Registering Formatters via Config

You can register custom formatters inside the configure block with `register`:

```ruby
ActionFigure.configure do |c|
  c.register(custom_api: MyApp::CustomApiFormatter)
end
```

This delegates to `ActionFigure.register_formatter`, making the `:custom_api` format available application-wide. Once registered, set it as the default or use it per-class:

```ruby
c.format = :custom_api
```

## Per-Class Overrides

**Format** -- Pass the desired format when including the module:

```ruby
class CreateOrder
  include ActionFigure[:jsonapi]
end
```

This overrides the global `format` for that single class, regardless of what `ActionFigure.configure` specifies.

**API version** -- Declare a version inside the class body:

```ruby
class CreateOrder
  include ActionFigure

  api_version "2.0"
end
```

This overrides the global `api_version` for that class only.

## Rails Initializer Example

A typical `config/initializers/action_figure.rb`:

```ruby
ActionFigure.configure do |c|
  # Use JSON:API formatting by default
  c.format = :jsonapi

  # Raise when unexpected params are passed (recommended for development)
  c.whiny_extra_params = Rails.env.local?

  # Tag all actions with the current API version
  c.api_version = "1.0"

  # Register a custom formatter for internal admin endpoints
  c.register(admin: MyApp::AdminFormatter)
end
```
