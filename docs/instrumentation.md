# Instrumentation

## Overview

ActionFigure can instrument action execution via `ActiveSupport::Notifications`. When enabled, every `.call` (or custom entry point) emits a `process.action_figure` event with the action class name, outcome status, and timing.

Instrumentation is **off by default** and requires both ActiveSupport and an explicit opt-in.

---

## Enabling Instrumentation

```ruby
ActionFigure.configure do |c|
  c.instrumentation = true
end
```

Because instrumentation is resolved at include-time (when a class calls `include ActionFigure[:jsend]`), this setting must be configured before your action classes are loaded -- typically in an initializer.

---

## Event Name

```
process.action_figure
```

---

## Payload

| Key | Type | Description |
|-----|------|-------------|
| `action` | String | The action class name, e.g. `"Users::CreateAction"` |
| `status` | Symbol | The outcome status, e.g. `:ok`, `:created`, `:unprocessable_content` |

Timing (duration, start, end) is provided automatically by `ActiveSupport::Notifications`.

---

## Subscribing to Events

```ruby
ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
  Rails.logger.info(
    "#{event.payload[:action]} => #{event.payload[:status]} (#{event.duration.round(1)}ms)"
  )
end
```

Output:

```
Users::CreateAction => :created (12.3ms)
Orders::SearchAction => :ok (45.7ms)
Users::CreateAction => :unprocessable_content (1.1ms)
```

---

## What Gets Instrumented

The event wraps the entire action lifecycle -- validation, the `#call` method, and the formatted response. Both successful and failed outcomes are captured:

- Validation failures (e.g. missing required params) produce events with status `:unprocessable_content`
- Successful calls produce events with whatever status the action returns (`:ok`, `:created`, etc.)
- Custom entry points (declared with `entry_point`) are instrumented identically to `.call`

---

## Examples

### Logging slow actions

```ruby
ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
  if event.duration > 500
    Rails.logger.warn("[SLOW] #{event.payload[:action]} took #{event.duration.round}ms")
  end
end
```

### Tracking metrics

```ruby
ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
  StatsD.distribution(
    "action_figure.duration",
    event.duration,
    tags: {
      action: event.payload[:action],
      status: event.payload[:status]
    }
  )
end
```

### Counting failures

```ruby
ActiveSupport::Notifications.subscribe("process.action_figure") do |event|
  unless event.payload[:status] == :ok || event.payload[:status] == :created
    ErrorTracker.increment("action_figure.failure", action: event.payload[:action])
  end
end
```

---

## How It Works

Instrumentation is resolved once at include-time, not on every call. When a class includes an ActionFigure format module (e.g. `include ActionFigure[:jsend]`), the `included` hook checks whether `ActiveSupport::Notifications` is defined and `instrumentation` is enabled in the configuration. If both conditions are met, it extends the class with `ActionFigure::Core::Instrumentation`, which overrides the base `instrument` method to wrap execution in an `ActiveSupport::Notifications.instrument` block. Otherwise, the base method passes through directly with zero overhead.
