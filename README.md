# ActionFigure

Fully-articulated controller actions.

ActionFigure replaces general service objects with explicit, purpose-driven operation classes. Each action validates its input, executes its logic, and returns a render-ready hash — making your controllers one-liners.

```ruby
# app/controllers/users_controller.rb
def create
  render Users::CreateAction.call(params:, company: current_company)
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

Define an action class with a validation schema, rules and a `call` method:

```ruby
# app/actions/users/create_action.rb
class Users::CreateAction
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
    resource = UserBlueprint.render_as_hash(user)
    Created(resource:)
  end
end
```

Call it from your controller:

```ruby
# params: { name: "Tad", email: "tad@example.com" }
render Users::CreateAction.call(params:, company: current_company)
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

## Serialization

ActionFigure doesn't prescribe a serializer — pass any hash to `resource:` and it goes straight into the response envelope. Here are the most common options:

**[Blueprinter](https://github.com/procore/blueprinter)**

```ruby
def call(params:, company:)
  user = company.users.create!(params)
  resource = UserBlueprint.render_as_hash(user)
  Created(resource:)
end
```

**[Alba](https://github.com/okuramasafumi/alba)**

```ruby
def call(params:, company:)
  user = company.users.create!(params)
  resource = UserResource.new(user).to_h
  Created(resource:)
end
```

**[jsonapi-serializer](https://github.com/jsonapi-serializer/jsonapi-serializer)**

```ruby
def call(params:, company:)
  user = company.users.create!(params)
  resource = UserSerializer.new(user).serializable_hash
  Created(resource:)
end
```

## Features

- **[Validation](docs/validation.md)** — Two-layer validation powered by dry-validation: structural schemas with type coercion, plus validation rules. Includes cross-parameter helpers like `one_rule`, `all_rule`, and `implies_rule`.

- **[Response Formatters](docs/formatters.md)** — Four built-in formats: Default, JSend, JSON:API, and Wrapped. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes.

- **[Custom Formatters](docs/custom-formatters.md)** — Define your own response envelope by implementing the formatter interface. Registration validates your module at load time.

- **[Actions](docs/actions.md)** — Custom entry points (`entry_point :search`), dependency injection via keyword arguments, per-class API versioning, and no-params actions.

- **[Configuration](docs/configuration.md)** — Global defaults for response format, parameter strictness, and API version. All overridable per-class.

- **[Testing](docs/testing.md)** — Minitest assertions (`assert_Ok`, `assert_Created`, ...) and RSpec matchers (`be_Ok`, `be_Created`, ...) for expressive status checks.

## How It Works

Every action class has three responsibilities:

1. **Check params** — `params_schema` validates structure and types, `rules` enforces validation rules. If either fails, the formatter returns an error response and `#call` is never invoked.
2. **Orchestrate** — `#call` coordinates the work: creating records, calling service objects, enqueuing jobs, or anything else your operation requires. The action is the entry point, not necessarily where all the logic lives.
3. **Return a formatted response** — response helpers like `Created(resource:)` and `NotFound(errors:)` return render-ready hashes that go straight to `render` in your controller.

## API Versioning

Action classes are plain Ruby — they aren't coupled to a specific controller or route. The same action works across API versions without duplication:

```ruby
class V1::UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
  end
end

class V2::UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
  end
end
```

Your business logic lives in one place. Versioned controllers share it freely. When a v2 endpoint needs different behavior, write a new action — the rest keep sharing.

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
