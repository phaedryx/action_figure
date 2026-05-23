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

## When configuration applies (load order)

**Default formatter.** With bare `include ActionFigure`, Ruby calls **`ActionFigure.[]`** (no argument) during that line — it mixes in whichever formatter **`ActionFigure.configuration.format`** selects **in that moment**. Later calls to **`ActionFigure.configure`** (changing **`format`**) do **not** swap formatters inside classes that already finished `include`. Run **`configure`** in an initializer (or equivalent) **before** your action classes load, or skip the ambiguity altogether with **`include ActionFigure[:jsonapi]`** (or another registered name).

**Notifications.** **`activesupport_notifications`** is consulted when the mixin’s **`included`** hook runs for your action class. If you turn **`c.activesupport_notifications = true`** only after constants have already loaded their `include` line, existing classes stay without the notifier extension; newly loaded classes get it.

**Per-class knobs** such as **`include ActionFigure[:wrapped]`**, **`entry_point :search`**, and **`api_version "2.0"`** remain whatever you wrote in each class regardless of subsequent global **`configure`** calls.

## Settings Reference

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `format` | Symbol | `:default` | Formatter for bare **`include ActionFigure`**. Locked in when that line runs — see **When configuration applies (load order)** above. |
| `whiny_extra_params` | Boolean | `false` | When `true`, returns an error response for undeclared params instead of silently stripping them. |
| `activesupport_notifications` | Boolean | `false` | When `true` and ActiveSupport is defined, emits **`process.action_figure`** for classes whose mixin runs **after** the flag was set — see load order note above. |
| `api_version` | String or nil | `nil` | Global API version tag, readable via `ActionFigure.configuration.api_version`. |

## Thread safety and global state

`ActionFigure.configure` assigns to a **process-wide singleton** (`ActionFigure.configuration`). For production, set globals **once during boot**. In **multi-threaded** code or parallel test workers, flipping settings concurrently can interfere across threads — snapshot and restore in `ensure` (as the gem’s tests do with `whiny_extra_params`) or avoid mutating globals after boot.

---

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

  # Turn on ActiveSupport::Notifications events for every action call
  c.activesupport_notifications = true

  # Register a custom formatter
  c.register(our_format: MyApp::OurFormatter)

  # Use the custom formatter by default
  c.format = :our_format
end
```
