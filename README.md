# ActionFigure

Fully-articulated controller actions.

---
> #### Table of Contents
> [Installation](#installation)<br>
> [Quick Start](#quick-start)<br>
> [How It Works](#how-it-works)<br>
> [Features](#features)<br>
> [Design Philosophy](#design-philosophy)<br>
> [Requirements](#requirements)<br>
> [License](#license)
---

**ActionFigure** replaces gnarly controller method logic with explicit, purpose-driven operation classes. Each action validates its input, executes its logic, and returns a render-ready hash — making your controller action methods one-liners and behavior easily testable.

## Installation

Add to your Gemfile and `bundle install`:

```ruby
gem "action_figure"
```

## Quick Start

**1. Start with what the action should do.**

```ruby
# spec/actions/users/create_action_spec.rb
RSpec.describe Users::CreateAction do
  it "creates a user with valid parameters" do
    company = Company.create!(name: "Acme")

    # Note: Extra keyword arguments like company: are injected as context alongside params:
    result = Users::CreateAction.call(
      params: { user: { name: "Tad", email: "tad@example.com" } },
      company: company
    )

    # Results are render-ready hashes (JSend formatted in this case)
    # => { json: { status: "success", data: { name: "Tad", ... } }, status: :created }
    expect(result).to be_Created
    expect(result[:json][:data]).to include("name" => "Tad", "email" => "tad@example.com")
    expect(User.find_by(email: "tad@example.com")).to be_persisted
  end

  it "fails when name is missing" do
    company = Company.create!(name: "Acme")
    result = Users::CreateAction.call(
      params: { user: { email: "tad@example.com" } },
      company: company
    )

    # Validation failures short-circuit before #call executes
    # => { json: { status: "fail", data: { user: { name: ["is missing"] } } },
    #      status: :unprocessable_content }
    expect(result).to be_UnprocessableContent
    expect(result[:json][:data][:user][:name]).to include("is missing")
    expect(User.find_by(email: "tad@example.com")).not_to be_persisted
  end
end
```

**2. Define the action class.**

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

  def call(params:, company:)
    user = company.users.create!(params[:user])
    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

**3. Call it from your controller.**

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
  end
end
```

## How It Works

Every action class has three responsibilities:

1. **Check params** — `params_schema` validates structure and types, `rules` enforces validation rules. If either fails, the formatter returns an error response and `#call` is never invoked.
2. **Orchestrate** — `#call` coordinates the work: creating records, calling service objects, enqueuing jobs, or anything else your operation requires. The action is the entry point, not necessarily where all the logic lives.
3. **Return a formatted response** — response helpers like `Created(resource:)` and `NotFound(errors:)` return render-ready hashes that go straight to `render` in your controller.

## Features

| Feature | Description |
|---------|-------------|
| [Validation](docs/validation.md) | Two-layer validation powered by dry-validation: structural schemas with type coercion, plus validation rules. Includes cross-parameter helpers like `one_rule`, `all_rule`, and `implies_rule`. |
| [Response Formatters](docs/response-formatters.md) | Four built-in formats: Default, JSend, JSON:API, and Wrapped. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes. |
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
