# ActionFigure

Fully-articulated controller actions.

---
> #### Table of Contents
> [Installation](#installation)<br>
> [How It Works](#how-it-works)<br>
> [Features](#features)<br>
> [Quick Start](#quick-start)<br>
> [Design Philosophy](#design-philosophy)<br>
> [Requirements](#requirements)<br>
> [License](#license)
---

**ActionFigure** extracts controller actions into classes that validate params, orchestrate work, and return render-ready responses. Your controller becomes:

```ruby
class OrdersController < ApplicationController
  def create
    render Orders::CreateAction.call(params:, current_user:)
  end
end
```

The action class owns everything that used to be scattered across the controller method, strong params, model callbacks, and ad-hoc response building:

```ruby
class Orders::CreateAction
  include ActionFigure[:wrapped]

  params_schema do
    required(:item_id).filled(:integer)
    required(:quantity).filled(:integer)
    optional(:coupon_code).filled(:string)
    optional(:gift_message).filled(:string)
    optional(:gift_recipient_email).filled(:string)
  end

  rules do
    all_rule(:gift_message, :gift_recipient_email,
             "gift fields must be provided together or not at all")
  end

  def call(params:, current_user:)
    if current_user.unpaid_balance?
      return Forbidden(errors: { base: ["unpaid balance on account"] })
    end

    item = Item.find_by(id: params[:item_id])
    return NotFound(errors: { item_id: ["item not found"] }) unless item

    order = current_user.orders.create(
      item: item,
      quantity: params[:quantity],
      coupon_code: params[:coupon_code]
    )
    return UnprocessableContent(errors: order.errors.messages) if order.errors.any?

    resource = OrderBlueprint.render_as_hash(order, view: :confirmation)
    Created(resource:)
  end
end
```

Param validation, cross-field rules, authorization, error handling, and response formatting — all in one place, all testable without a request:

```ruby
class Orders::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_an_order
    user = User.create!(name: "Tad")
    item = Item.create!(name: "Widget", price: 29.00)

    result = Orders::CreateAction.call(
      params: { item_id: item.id, quantity: 2 },
      current_user: user
    )

    assert_Created(result)
    assert_equal item.id, result[:json][:data]["item_id"]
  end

  def test_forbidden_with_unpaid_balance
    user = User.create!(name: "Tad", balance: -1)

    result = Orders::CreateAction.call(
      params: { item_id: 1, quantity: 1 },
      current_user: user
    )

    assert_Forbidden(result)
    assert_includes result[:json][:errors][:base], "unpaid balance on account"
  end

  def test_not_found_when_item_missing
    user = User.create!(name: "Tad")

    result = Orders::CreateAction.call(
      params: { item_id: 999, quantity: 1 },
      current_user: user
    )

    assert_NotFound(result)
    assert_includes result[:json][:errors][:item_id], "item not found"
  end

  def test_rejects_partial_gift_fields
    user = User.create!(name: "Tad")
    item = Item.create!(name: "Widget", price: 29.00)

    result = Orders::CreateAction.call(
      params: { item_id: item.id, quantity: 1, gift_message: "Enjoy!" },
      current_user: user
    )

    assert_UnprocessableContent(result)
    assert_includes result[:json][:errors][:gift_message],
                    "gift fields must be provided together or not at all"
  end
end
```

This isn't for everybody. If your controllers are already thin, or you validate through OpenAPI middleware like [committee](https://github.com/interagent/committee), you probably don't need this. ActionFigure is for teams whose controller actions have grown into tangled mixes of param wrangling, authorization checks, error handling, and response building.

## Installation

Add to your Gemfile and `bundle install`:

```ruby
gem "action_figure"
```

## How It Works

Every action class has three responsibilities:

1. **Check params** (optional) — when a `params_schema` is defined, it validates structure and types; `rules` enforces validation rules. If either fails, the formatter returns an error response and `#call` is never invoked. Actions without a schema receive `params:` as-is.
2. **Orchestrate** — `#call` coordinates the work: creating records, calling service objects, enqueuing jobs, or anything else the action requires. The action is the entry point, not necessarily where all the logic lives.
3. **Return a formatted response** — response helpers like `Created(resource:)` and `NotFound(errors:)` return render-ready hashes that go straight to `render` in your controller.

## Features

| Feature | Description |
|---------|-------------|
| [Validation](docs/validation.md) | Two-layer validation powered by dry-validation: structural schemas with type coercion, plus validation rules. Includes cross-parameter helpers like `exclusive_rule`, `any_rule`, `one_rule`, and `all_rule`. |
| [Response Formatters](docs/response-formatters.md) | Four built-in formats: Default, JSend, JSON:API, and Wrapped. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes. |
| [Custom Formatters](docs/custom-formatters.md) | Define your own response envelope by implementing the formatter interface. Registration validates your module at load time. |
| [Actions](docs/actions.md) | Custom entry points (`entry_point :search`), context injection via keyword arguments, per-class API versioning, and no-params actions. |
| [Configuration](docs/configuration.md) | Global defaults for response format, parameter strictness, and API version. All overridable per-class. |
| [Notifications](docs/activesupport-notifications.md) | Opt-in `ActiveSupport::Notifications` events for every action call. Emits action class, outcome status, and duration on the `process.action_figure` event. |
| [Testing](docs/testing.md) | Minitest assertions (`assert_Ok`, `assert_Created`, ...) and RSpec matchers (`be_Ok`, `be_Created`, ...) for expressive status checks. |
| [Integration Patterns](docs/integration-patterns.md) | Recipes for serializers (Blueprinter, Alba, Oj Serializers), authorization (Pundit, CanCanCan), and pagination (cursor, Pagy). |

## Quick Start

**1. Define the action class.**

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
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

**2. Call it from your controller.**

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
  end
end
```

**3. Test it directly.**

```ruby
class Users::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_a_user
    company = Company.create!(name: "Acme")

    result = Users::CreateAction.call(
      params: { user: { name: "Tad", email: "tad@example.com" } },
      company: company
    )

    assert_Created(result)
    assert_equal "Tad", result[:json][:data]["name"]
  end

  def test_fails_when_name_is_missing
    company = Company.create!(name: "Acme")

    result = Users::CreateAction.call(
      params: { user: { email: "tad@example.com" } },
      company: company
    )

    assert_UnprocessableContent(result)
    assert_includes result[:json][:data][:user][:name], "is missing"
  end
end
```

## Design Philosophy

Unlike general-purpose service object libraries, ActionFigure is scoped to controller actions — it validates params, runs your logic, and returns a hash you pass directly to `render`.

- **Purpose over convention** — each class does one thing and names it clearly
- **Explicit over implicit** — no magic method resolution, no inherited callbacks
- **Actions own their lifecycle** — validation, execution, and response formatting live together
- **Controllers become boring** — one-line `render` calls that delegate to action classes
- **Models and Controllers stay thin** — business logic moves to purpose-built action classes

## Requirements

- Ruby >= 3.2
- [dry-validation](https://dry-rb.org/gems/dry-validation/) ~> 1.10 — ActionFigure uses dry-validation for schema validation because it's the best tool for the job. There's no dependency injection container, no monads, no functional pipeline. Just a focused layer for controller actions.
- Rails is not required, but ActionFigure is designed for Rails controller patterns

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
