# ActionFigure

Fully-articulated controller actions.

---
> #### Table of Contents
> [Installation](#installation)<br>
> [How It Works](#how-it-works)<br>
> [Features](#features)<br>
> [Design Philosophy](#design-philosophy)<br>
> [Examples](#examples)<br>
> [Requirements](#requirements)<br>
> [License](#license)
---

**ActionFigure** makes your controller actions more usable and understandable. It turns this:

```ruby
class ProjectsController < ApplicationController
  def create
    permitted = params.require(:project).permit(
      :name, :description, settings: [:visibility, :notify_on_mention]
    )

    if permitted[:name].blank?
      render json: { status: "fail", data: { name: ["is required"] } },
             status: :unprocessable_entity
      return
    end

    if permitted.dig(:settings, :visibility).present? &&
       !%w[public private].include?(permitted[:settings][:visibility])
      render json: { status: "fail", data: { settings: { visibility: ["must be public or private"] } } },
             status: :unprocessable_entity
      return
    end

    unless current_user.member_of?(current_workspace)
      render json: { status: "fail", data: { base: ["must be a workspace member"] } },
             status: :forbidden
      return
    end

    if current_workspace.projects.exists?(name: permitted[:name])
      render json: { status: "fail", data: { name: ["already exists in this workspace"] } },
             status: :conflict
      return
    end

    project = CreateProject.run(permitted, workspace: current_workspace, creator: current_user)

    if project.errors.any?
      render json: { status: "fail", data: project.errors.messages },
             status: :unprocessable_entity
      return
    end

    render json: { status: "success", data: ProjectBlueprint.render_as_hash(project) }
  end
end
```

into this:

```ruby
class ProjectsController < ApplicationController
  def create
    render Projects::CreateAction.create(params:, current_user:, current_workspace:)
  end
end
```

```ruby
class Projects::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:project).hash do
      required(:name).filled(:string)
      optional(:description).filled(:string)
      optional(:settings).hash do
        optional(:visibility).filled(:string, included_in?: %w[public private])
        optional(:notify_on_mention).filled(:bool)
      end
    end
  end

  def create(params:, current_user:, current_workspace:)
    unless current_user.member_of?(current_workspace)
      return Forbidden(errors: { base: ["must be a workspace member"] })
    end

    if current_workspace.projects.exists?(name: params[:project][:name])
      return Conflict(errors: { name: ["already exists in this workspace"] })
    end

    project = CreateProject.run(params[:project], workspace: current_workspace, creator: current_user)
    return UnprocessableContent(errors: project.errors.messages) if project.errors.any?

    Created(resource: ProjectBlueprint.render_as_hash(project))
  end
end
```

- The shape and types of your params are obvious
- The structure is clear
- The tests are easy (and 10x faster)
- The responses are uniform and render-ready

(Did you notice which of the render responses was incorrect before?)

## Installation

Add to your Gemfile and `bundle install`:

```ruby
gem "action_figure"
```

## How It Works

Every action class has three responsibilities:

1. **Check params** (optional) — when a `params_schema` is defined, it validates structure and types; `rules` enforces validation rules. If either fails, the formatter returns an error response and your action method is never invoked. Actions without a schema receive `params:` as-is.
2. **Orchestrate** — your action method coordinates the work: creating records, coordinating collaborators, enqueuing jobs, or anything else the action requires. The action is the entry point, not necessarily where all the logic lives.
3. **Return a formatted response** — response helpers like `Created(resource:)` and `NotFound(errors:)` return render-ready hashes that go straight to `render` in your controller.

## Features

| Feature | Description |
|---------|-------------|
| [Validation](docs/validation.md) | Two-layer validation powered by dry-validation: structural schemas with type coercion, plus validation rules. Includes cross-parameter helpers like `exclusive_rule`, `any_rule`, `one_rule`, and `all_rule`. |
| [Response Formatters](docs/response-formatters.md) | Four built-in formats: Default, JSend, JSON:API, and Wrapped. Each provides response helpers (`Ok`, `Created`, `NotFound`, etc.) that return render-ready hashes. |
| [Status Codes](docs/status-codes.md) | Which 4xx codes are domain concerns (handled by action classes) vs perimeter concerns (handled by middleware, router, or infrastructure). |
| [Custom Formatters](docs/custom-formatters.md) | Define your own response envelope by implementing the formatter interface. Registration validates your module at load time. |
| [Actions](docs/actions.md) | Automatic entry point discovery, context injection via keyword arguments, per-class API versioning, and `entry_point` for disambiguation. |
| [Configuration](docs/configuration.md) | Global defaults for response format, parameter strictness, and API version. All overridable per-class. |
| [Notifications](docs/activesupport-notifications.md) | Opt-in `ActiveSupport::Notifications` events for every action call. Emits action class, outcome status, and duration on the `process.action_figure` event. |
| [Testing](docs/testing.md) | Minitest assertions (`assert_Ok`, `assert_Created`, ...) and RSpec matchers (`be_Ok`, `be_Created`, ...) for expressive status checks. |
| [Integration Patterns](docs/integration-patterns.md) | Recipes for serializers (Blueprinter, Alba, Oj Serializers), authorization (Pundit, CanCanCan), and pagination (cursor, Pagy). |

## Design Philosophy

ActionFigure is scoped to controller actions — it validates params, runs your logic, and returns a hash you pass directly to `render`.

- **Purpose over convention** — each class does one thing and names it clearly
- **Explicit over implicit** — no magic method resolution, no inherited callbacks
- **Actions own their lifecycle** — validation, execution, and response formatting live together
- **Controllers become boring** — one-line `render` calls that delegate to action classes
- **Separate domain tests from perimeter tests** — keep your controller tests for perimeter checks, but now your domain logic lives in plain method calls. Faster tests, clearer failures.

## Examples

### Validation Rules

Cross-parameter helpers make multi-field constraints declarative:

```ruby
class Search::LookupAction
  include ActionFigure[:jsend]

  params_schema do
    optional(:user_id).filled(:integer)
    optional(:email).filled(:string)
  end

  rules do
    exclusive_rule(:user_id, :email, "provide one, not both")
  end

  def lookup(params:)
    user = params[:user_id] ? User.find_by(id: params[:user_id]) : User.find_by(email: params[:email])

    Ok(resource: user.as_json)
  end
end
```

### Response Formatters

Choose a response envelope by name. The same helpers return different shapes:

```ruby
# Default
Created(resource: user)
# => { json: { data: user }, status: :created }

# JSend
Created(resource: user)
# => { json: { status: "success", data: user }, status: :created }

# JSON:API
Created(resource: user)
# => { json: { data: { type: "users", id: "1", attributes: user } }, status: :created }

# Wrapped
Created(resource: user)
# => { json: { data: user, errors: nil, status: "success" }, status: :created }
```

### Testing

Action classes are plain method calls — no request setup needed:

```ruby
class Search::LookupActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_finds_by_email
    result = Search::LookupAction.lookup(
      params: { email: "tad@example.com" }
    )

    assert_Ok(result)
  end

  def test_rejects_both_user_id_and_email
    result = Search::LookupAction.lookup(
      params: { user_id: 1, email: "tad@example.com" }
    )

    assert_UnprocessableContent(result)
    assert_includes result[:json][:data][:user_id], "provide one, not both"
  end
end
```

### Actions Without a Schema

Not every action needs parameter validation:

```ruby
class HealthCheckAction
  # Uses the globally-configured format
  include ActionFigure

  def check(current_user:)
    Ok(resource: { status: "healthy", user: current_user.name })
  end
end
```

## Requirements

- Ruby >= 3.2
- [dry-validation](https://dry-rb.org/gems/dry-validation/) ~> 1.10 — ActionFigure uses dry-validation for schema validation. However, there's no dependency injection container, monads, or functional pipeline. Just a focused layer for controller actions.
- Rails is not required, but ActionFigure is designed for Rails controller patterns

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
