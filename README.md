# ActionFigure

Fully-articulated controller actions.

---
> #### Table of Contents
> [Quick Start](#quick-start)<br>
> [How It Works](#how-it-works)<br>
> [Features](#features)<br>
> [Design Philosophy](#design-philosophy)<br>
> [Requirements](#requirements)<br>
> [License](#license)
---

ActionFigure replaces general service objects with explicit, purpose-driven operation classes. Each action validates its input, executes its logic, and returns a render-ready hash — making your controller action methods one-liners.

```ruby
# app/controllers/users_controller.rb
def create
  render Users::CreateAction.call(params:, company: current_company)
end
```

## Quick Start

Add to your Gemfile and `bundle install`:

```ruby
gem "action_figure"
```

Define an action class with a validation schema, rules and a `call` method:

```ruby
# app/actions/users/create_action.rb
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end
  end

  rules do
    rule(user: :email) do
      key.failure("is invalid") unless values[:user][:email].include?("@")
    end
  end

  def call(params:, company:)
    user = company.users.create!(params[:user])
    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

Call it from your controller:

```ruby
# params: { user: { name: "Tad", email: "tad@example.com" } }
render Users::CreateAction.call(params:, company: current_company)
```

On success, the result is a render-ready hash (JSend formatted in this case):

```ruby
{
  json: { status: "success", data: { id: 1, name: "Tad", email: "tad@example.com" } },
  status: :created
}
```

On validation failure, the action short-circuits before `#call` executes (also JSend formatted):

```ruby
{
  json: { status: "fail", data: { email: ["is invalid"] } },
  status: :unprocessable_content
}
```

ActionFigure doesn't prescribe a serializer — pass any hash to `resource:` and it goes straight into the response envelope.

## How It Works

Every action class has three responsibilities:

1. **Check params** — `params_schema` validates structure and types, `rules` enforces validation rules. If either fails, the formatter returns an error response and `#call` is never invoked.
2. **Orchestrate** — `#call` coordinates the work: creating records, calling service objects, enqueuing jobs, or anything else your operation requires. The action is the entry point, not necessarily where all the logic lives.
3. **Return a formatted response** — response helpers like `Created(resource:)` and `NotFound(errors:)` return render-ready hashes that go straight to `render` in your controller.

## Features

| Feature | Description |
|---------|-------------|
| [Validation](docs/validation.md) | Two-layer validation powered by dry-validation: structural schemas with type coercion, plus validation rules. Includes cross-parameter helpers like `one_rule`, `all_rule`, and `implies_rule`. |
| [Response Formatters](docs/formatters.md) | Four built-in formats: Default, JSend, JSON:API, and Wrapped. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes. |
| [Custom Formatters](docs/custom-formatters.md) | Define your own response envelope by implementing the formatter interface. Registration validates your module at load time. |
| [Actions](docs/actions.md) | Custom entry points (`entry_point :search`), context injection via keyword arguments, per-class API versioning, and no-params actions. |
| [Configuration](docs/configuration.md) | Global defaults for response format, parameter strictness, and API version. All overridable per-class. |
| [Notifications](docs/activesupport-notifications.md) | Opt-in `ActiveSupport::Notifications` events for every action call. Emits action class, outcome status, and duration on the `process.action_figure` event. |
| [Testing](docs/testing.md) | Minitest assertions (`assert_Ok`, `assert_Created`, ...) and RSpec matchers (`be_Ok`, `be_Created`, ...) for expressive status checks. |
| [Integration Patterns](docs/integration-patterns.md) | Recipes for serializers (Blueprinter, Alba, Oj Serializers), authorization (Pundit, CanCanCan), and pagination (cursor, Pagy). |

## Design Philosophy

- **Purpose over convention** — each class does one thing and names it clearly
- **Explicit over implicit** — no magic method resolution, no inherited callbacks
- **Operations own their lifecycle** — validation, execution, and response formatting live together
- **Controllers become boring** — one-line `render` calls that delegate to action classes
- **Models and Controllers stay thin** — business logic moves to purpose-built operations

## Requirements

- Ruby >= 3.2
- [dry-validation](https://dry-rb.org/gems/dry-validation/) ~> 1.10
- Rails is not required, but ActionFigure is designed for Rails controller patterns

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
