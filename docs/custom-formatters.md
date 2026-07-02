# Custom Formatters

## Overview

Beyond the built-in formats, ActionFigure lets you define your own response format. A formatter is a Ruby module that translates action outcomes (success, creation, validation failure, etc.) into the response shape your API expects. Once registered, a custom formatter works exactly like the built-in ones.

## The Formatter Interface

A formatter is a module that includes `ActionFigure::Formatter` and defines methods for each outcome type.

Including `ActionFigure::Formatter` gives you:

- A default `NoContent` implementation that returns `{ status: :no_content }`.
- Named error helpers for every registered error status (`NotFound`, `Conflict`, `Gone`, etc.), carried by a live registry module included into `ActionFigure::Formatter`. Each generated helper delegates to `error_response`.
- A contract enforced at registration time: your module **must** define all 4 required methods.

The required methods are:

| Method                 | Purpose                                                          |
|------------------------|------------------------------------------------------------------|
| `Ok`                   | Successful retrieval or generic success                          |
| `Created`              | Resource was created                                             |
| `Accepted`             | Request accepted for background processing                       |
| `error_response`       | Low-level failure renderer called by every named error helper    |

`NoContent` is provided by the base module and does not need to be defined, but you can override it if your format requires a different shape.

Named error helpers (`NotFound`, `Conflict`, `Gone`, `Locked`, `UnavailableForLegalReasons`, and any additional statuses you register) are generated from the error registry and all delegate to `error_response(errors:, status:)`. A formatter may still hand-define a specific named helper to override the generated one — a method defined on the formatter itself sits ahead of the generated helpers in the ancestor chain and wins.

`error_response` receives the keyword arguments `errors:` (an error hash) and `status:` (a Rack status symbol) and must return a hash.

## Building a Custom Formatter

Here is the built-in `Wrapped` formatter as a reference. It wraps every response in a uniform `{ data:, errors:, status: }` envelope:

```ruby
module WrappedFormatter
  include ActionFigure::Formatter

  def Ok(resource:, meta: nil)
    body = { data: resource, errors: nil, status: "success" }
    body[:meta] = meta if meta
    { json: body, status: :ok }
  end

  def Created(resource:, meta: nil)
    body = { data: resource, errors: nil, status: "success" }
    body[:meta] = meta if meta
    { json: body, status: :created }
  end

  def Accepted(resource: nil, meta: nil)
    body = { data: resource, errors: nil, status: "success" }
    body[:meta] = meta if meta
    { json: body, status: :accepted }
  end

  def error_response(errors:, status:)
    { json: { data: nil, errors: errors, status: "error" }, status: status }
  end
end
```

All 4 required methods are defined. Success methods accept `resource:` and optionally `meta:`. `error_response` accepts `errors:` and `status:` and is called by every generated named error helper. The `NoContent` method is inherited from the base `ActionFigure::Formatter` module and returns `{ status: :no_content }` with no JSON body -- override it if your format requires a different shape.

## Registering Your Formatter

There are two ways to register a custom formatter.

**Direct registration:**

```ruby
ActionFigure.register_formatter(wrapped: WrappedFormatter)
```

**Via the configuration block:**

```ruby
ActionFigure.configure do |config|
  config.register(wrapped: WrappedFormatter)
end
```

Both approaches accept keyword arguments where the key is a symbol naming the format and the value is the formatter module. You can register multiple formatters in a single call:

```ruby
ActionFigure.register_formatter(
  wrapped: WrappedFormatter,
  legacy_v1: LegacyV1Formatter
)
```

The name you choose (`:wrapped` in the examples above) is the symbol you will use everywhere else to reference this format.

## Interface Validation

Registration is not just bookkeeping -- ActionFigure validates every formatter module before accepting it. The validation checks that all methods listed in `ActionFigure::Formatter::REQUIRED_METHODS` are defined on the module:

```ruby
ActionFigure::Formatter::REQUIRED_METHODS
# => [:Ok, :Created, :Accepted, :error_response]
```

**Migration note (pre-0.7 formatters):** If you have a formatter written against the pre-0.7 eight-method contract that does not define `error_response`, registration will now **fail** — `REQUIRED_METHODS` requires `error_response`. Add an `error_response(errors:, status:)` method to your formatter before upgrading to 0.7.

If any required method is missing, registration raises an `ArgumentError` that lists exactly which methods are absent:

```ruby
module IncompleteFormatter
  include ActionFigure::Formatter

  def Ok(resource:, **)
    { status: :ok, json: resource }
  end
end

ActionFigure.register_formatter(incomplete: IncompleteFormatter)
# => ArgumentError: IncompleteFormatter is missing formatter methods: Created, Accepted, error_response
```

Validation is **atomic** when registering multiple formatters at once. If any single module in the batch fails validation, none of them are registered -- this ensures your registry always remains in a consistent state.

```ruby
# Neither formatter is registered because LegacyV1Formatter is invalid.
ActionFigure.register_formatter(
  wrapped: WrappedFormatter,
  legacy_v1: LegacyV1Formatter  # missing methods
)
# => ArgumentError (nothing was registered)
```

## Using Your Formatter

Once registered, use a custom formatter exactly like a built-in one.

**Per-action inclusion:**

```ruby
class Articles::PublishAction
  include ActionFigure[:wrapped]

  def call(id:)
    article = Article.find(id)
    article.publish!
    Ok(resource: article)
  end
end
```

**As the global default:**

```ruby
ActionFigure.configure do |config|
  config.register(wrapped: WrappedFormatter)
  config.format = :wrapped
end
```

```ruby
class Articles::PublishAction
  include ActionFigure # no format specified, global setting is used

  def call(id:)
    article = Article.find(id)
    article.publish!
    Ok(resource: article)
  end
end
```

Setting `config.format` makes every action use your formatter unless an individual action explicitly includes a different one. Per-action includes always take precedence over the global default.

## Registering Additional Error Statuses

ActionFigure ships with eight built-in error statuses (see [HTTP 4xx Status Codes](status-codes.md)). You can register additional ones with `ActionFigure.register_error`:

```ruby
ActionFigure.register_error(:BadGateway, :bad_gateway)
```

The first argument is the helper name (a Symbol or String) that will be available in action classes (`BadGateway(errors:)`). The second argument must be a valid Rack status symbol — `register_error` validates it against `Rack::Utils::SYMBOL_TO_STATUS_CODE` and raises `ArgumentError` immediately for a symbol no supported Rack version knows, so a typo fails at boot rather than on the first error rendered in production.

Registration is **add-only**: you cannot remove or override a built-in status. Names reserved by the formatter contract (`Ok`, `Created`, `Accepted`, `NoContent`, `error_response`) are rejected.

Registration can happen at any time. Generated helpers live on a single registry module included into `ActionFigure::Formatter`, so a newly registered status is immediately available to every formatter and every action class — including classes that ran `include ActionFigure[...]` before the registration — and `register_error` also patches any already-loaded Minitest assertions and RSpec matchers. An initializer is still the natural home for registrations, but nothing breaks if one runs late.
