# ActionFigure

Fully-articulated controller actions.

ActionFigure replaces service objects and model callbacks with explicit, purpose-driven operation classes. Each action validates its input, executes its logic, and returns a render-ready hash — making your controllers one-liners and your models free of callbacks.

```ruby
# app/controllers/users_controller.rb
def create
  render Users::Create.call(params:, company: current_company)
end
```

## Installation

Add to your Gemfile:

```ruby
gem "action_figure"
```

Then run:

```bash
bundle install
```

## Quick Start

Define an action class with a validation schema, business rules, and a `call` method:

```ruby
# app/actions/users/create.rb
class Users::Create
  include ActionFigure[:jsend]

  params_schema do
    required(:name).filled(:string)
    required(:email).filled(:string)
  end

  rules do
    rule(:email) do
      key.failure("is invalid") unless values[:email].include?("@")
    end
  end

  def call(params:, company:)
    user = company.users.create!(params)
    Created(resource: user)
  end
end
```

Call it from your controller:

```ruby
result = Users::Create.call(params: { name: "Tad", email: "tad@example.com" }, company: current_company)
```

On success, the result is a render-ready hash:

```ruby
{
  json: { status: "success", data: { id: 1, name: "Tad", email: "tad@example.com" } },
  status: :created
}
```

On validation failure, the action short-circuits before `#call` executes:

```ruby
{
  json: { status: "fail", data: { email: ["is invalid"] } },
  status: :unprocessable_content
}
```

## Features

- **[Validation](docs/validation.md)** — Two-layer validation powered by dry-validation: structural schemas with type coercion, plus business rules. Includes cross-parameter helpers like `one_rule`, `all_rule`, and `implies_rule`.

- **[Response Formatters](docs/formatters.md)** — Two built-in formats: JSend and JSON:API. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes.

- **[Custom Formatters](docs/custom-formatters.md)** — Define your own response envelope by implementing the formatter interface. Registration validates your module at load time.

- **[Actions](docs/actions.md)** — Custom entry points (`entry_point :search`), dependency injection via keyword arguments, per-class API versioning, and no-params actions.

- **[Configuration](docs/configuration.md)** — Global defaults for response format, parameter strictness, and API version. All overridable per-class.

- **[Testing](docs/testing.md)** — Minitest assertions (`assert_Ok`, `assert_Created`, ...) and RSpec matchers (`be_Ok`, `be_Created`, ...) for expressive status checks.

## How It Works

1. `include ActionFigure[:jsend]` mixes in the validation pipeline and response helpers
2. `params_schema` defines the expected input shape with type coercion
3. `rules` adds business-rule validations that run after the schema passes
4. On failure, the formatter returns an error response — your `#call` method is never invoked
5. On success, validated params and any extra keyword arguments are passed to `#call`
6. Your `#call` method uses response helpers like `Ok(resource:)` to return a render-ready hash

## Design Philosophy

- **Purpose over convention** — each class does one thing and names it clearly
- **Explicit over implicit** — no magic method resolution, no inherited callbacks
- **Operations own their lifecycle** — validation, execution, and response formatting live together
- **Controllers become boring** — one-line `render` calls that delegate to action classes
- **Models stay thin** — business logic moves to purpose-built operations

## Requirements

- Ruby >= 3.2
- [dry-validation](https://dry-rb.org/gems/dry-validation/) ~> 1.10
- Rails is not required, but ActionFigure is designed for Rails controller patterns

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
