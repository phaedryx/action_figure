# Custom Formatters

## Overview

Beyond the built-in JSend and JSON:API formats, ActionFigure lets you define your own response format. A formatter is a Ruby module that translates action outcomes (success, creation, validation failure, etc.) into the response shape your API expects. Once registered, a custom formatter works exactly like the built-in ones.

## The Formatter Interface

A formatter is a module that includes `ActionFigure::Formatter` and defines methods for each outcome type.

Including `ActionFigure::Formatter` gives you:

- A default `NoContent` implementation that returns `{ status: :no_content }`.
- A contract enforced at registration time: your module **must** define all 6 required methods.

The required methods are:

| Method                 | Purpose                                      |
|------------------------|----------------------------------------------|
| `Ok`                   | Successful retrieval or generic success       |
| `Created`              | Resource was created                          |
| `Accepted`             | Request accepted for background processing    |
| `UnprocessableContent` | Validation or business-rule failure            |
| `NotFound`             | Resource not found                            |
| `Forbidden`            | Authorization failure                         |

`NoContent` is provided by the base module and does not need to be defined, but you can override it if your format requires a different shape.

Each method receives keyword arguments and must return a hash. The exact keywords depend on the outcome -- success methods typically receive `resource:` (and optionally `meta:`), while failure methods receive `errors:` or `resource:` with error details.

## Building a Custom Formatter

Here is a complete example of an "Envelope" formatter that wraps every response in a uniform `{ data:, error:, status: }` structure:

```ruby
module EnvelopeFormatter
  include ActionFigure::Formatter

  def Ok(resource:, **)
    {
      status: :ok,
      json: { data: resource, error: nil, status: "ok" }
    }
  end

  def Created(resource:, **)
    {
      status: :created,
      json: { data: resource, error: nil, status: "created" }
    }
  end

  def Accepted(**)
    {
      status: :accepted,
      json: { data: nil, error: nil, status: "accepted" }
    }
  end

  def UnprocessableContent(errors:)
    {
      status: :unprocessable_content,
      json: { data: nil, error: errors, status: "unprocessable_content" }
    }
  end

  def NotFound(errors:)
    {
      status: :not_found,
      json: { data: nil, error: errors, status: "not_found" }
    }
  end

  def Forbidden(errors:)
    {
      status: :forbidden,
      json: { data: nil, error: errors, status: "forbidden" }
    }
  end

  # Override the default NoContent if you want the same envelope shape.
  def NoContent
    result = super
    result.merge(json: { data: nil, error: nil, status: "no_content" })
  end
end
```

All 6 required methods are defined, plus an optional `NoContent` override that calls `super` to preserve the base status and layers on the envelope structure.

## Registering Your Formatter

There are two ways to register a custom formatter.

**Direct registration:**

```ruby
ActionFigure.register_formatter(envelope: EnvelopeFormatter)
```

**Via the configuration block:**

```ruby
ActionFigure.configure do |config|
  config.register(envelope: EnvelopeFormatter)
end
```

Both approaches accept keyword arguments where the key is a symbol naming the format and the value is the formatter module. You can register multiple formatters in a single call:

```ruby
ActionFigure.register_formatter(
  envelope: EnvelopeFormatter,
  legacy_v1: LegacyV1Formatter
)
```

The name you choose (`:envelope` in the examples above) is the symbol you will use everywhere else to reference this format.

## Interface Validation

Registration is not just bookkeeping -- ActionFigure validates every formatter module before accepting it. The validation checks that all methods listed in `ActionFigure::Formatter::REQUIRED_METHODS` are defined on the module:

```ruby
ActionFigure::Formatter::REQUIRED_METHODS
# => [:Ok, :Created, :Accepted, :UnprocessableContent, :NotFound, :Forbidden]
```

If any required method is missing, registration raises an `ArgumentError` that lists exactly which methods are absent:

```ruby
module IncompleteFormatter
  include ActionFigure::Formatter

  def Ok(resource:, **)
    { status: :ok, json: resource }
  end
end

ActionFigure.register_formatter(incomplete: IncompleteFormatter)
# => ArgumentError: IncompleteFormatter is missing formatter methods: Created, Accepted,
#    UnprocessableContent, NotFound, Forbidden
```

Validation is **atomic** when registering multiple formatters at once. If any single module in the batch fails validation, none of them are registered. This prevents the registry from ending up in a partially-updated state:

```ruby
# Neither formatter is registered because LegacyV1Formatter is invalid.
ActionFigure.register_formatter(
  envelope: EnvelopeFormatter,
  legacy_v1: LegacyV1Formatter  # missing methods
)
# => ArgumentError (nothing was registered)
```

## Using Your Formatter

Once registered, use a custom formatter exactly like a built-in one.

**Per-action inclusion:**

```ruby
class Articles::Publish
  include ActionFigure[:envelope]

  def call(params:)
    article = Article.find(params[:id])
    article.publish!
    Ok(resource: article)
  end
end
```

**As the global default:**

```ruby
ActionFigure.configure do |config|
  config.register(envelope: EnvelopeFormatter)
  config.format = :envelope
end
```

Setting `config.format` makes every action use your formatter unless an individual action explicitly includes a different one. Per-action includes always take precedence over the global default.
