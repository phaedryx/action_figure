# Actions

## Overview

An ActionFigure action class is a single-purpose operation. Each class encapsulates one thing your application does -- creating a user, searching orders, processing a refund. This guide covers how to declare action classes, customize their entry points, inject dependencies, and wire them into your controllers.

---

## Naming Your Action Method

ActionFigure auto-discovers your action method by name. Define one public instance method on your action class and ActionFigure registers it as the entry point -- no macro required:

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def create(params:, company:, **)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

Wire it into a controller using the discovered method name:

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.create(params:, company: current_company)
  end
end
```

### How it works

ActionFigure uses a `method_added` hook to watch for public instance methods defined on the class. The first public method defined becomes the registered entry point and a matching class-level method is created for it. The full validation pipeline (`params_schema` and `rules`) still runs through the discovered entry point before your method is invoked.

Do not define **`initialize`** on action classes: ActionFigure calls **`new`** with no arguments each time work runs. A custom initializer raises **`InitializationNotSupportedError`** (even if `initialize` is private or you used **`entry_point`**). Prefer keyword arguments on the entry method or class-level collaborators for dependencies instead.

Overview of discovery (**`entry_point`** sidesteps ambiguity by wiring the singleton up front):

```mermaid
flowchart TD
  A[include mixes Core + formatter] --> B["method_added fires for each new method"]
  B --> C{"`entry_point` macro already declared?"}
  C -->|"yes"| D[Skip auto-discovery;\nsingleton was defined by the macro]
  C -->|"no"| E{"Public instance method owned by\nthis action class?"}
  E -->|"no"| B
  E -->|"yes"| F{"First discovered entry?"}
  F -->|"yes"| G["Remember name;\ndefine .name(**kwargs) -> validated_call"]
  F -->|"no"| H["Raise IndeterminateEntryPointError"]
```

### Disambiguation with `entry_point`

If a class ends up with more than one public instance method, ActionFigure cannot determine which one to use and raises an `IndeterminateEntryPointError`:

```
ActionFigure::IndeterminateEntryPointError: Multiple public methods defined in Orders::SearchAction:
:search and :format_results. Either make one private or declare
`entry_point :search` to disambiguate.
```

Use the `entry_point` macro to resolve this:

```ruby
class Orders::SearchAction
  include ActionFigure[:jsend]

  entry_point :search

  params_schema do
    optional(:order_id).filled(:string)
    optional(:tracking_number).filled(:string)
    optional(:status).filled(:string)
  end

  def search(params:, company:)
    orders = company.orders
    orders = orders.where(id: params[:order_id]) if params[:order_id]
    orders = orders.where(tracking_number: params[:tracking_number]) if params[:tracking_number]
    orders = orders.where(status: params[:status]) if params[:status]
    resource = orders.as_json(only: %i[id tracking_number status])
    Ok(resource:)
  end

  private

  def build_scope(company)
    company.orders.active
  end
end
```

Only one entry point per class is allowed. A second `entry_point` declaration raises an `ArgumentError`:

```
ArgumentError: entry_point already defined as 'search' — each action class may declare only one entry point
```

---

## Actions Without a Schema

Actions that omit `params_schema` skip the validation pipeline entirely. Any `params:` passed through are delivered to your method as-is — no coercion, no stripping, no validation.

This is useful when validation is handled upstream (e.g., Rack middleware like `committee` validating against an OpenAPI spec) or when the action simply doesn't need params:

```ruby
class HealthCheckAction
  include ActionFigure[:jsend]

  def check
    Ok(resource: { status: "healthy", time: Time.current })
  end
end
```

```ruby
class HealthController < ApplicationController
  def show
    render HealthCheckAction.check
  end
end
```

---

## Context Injection

Non-`params:` keyword arguments pass through to the instance method untouched. This is how you inject context from the controller -- the current user, the tenant, a logger, or any other collaborator -- without any special DSL.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def create(params:, company:, current_user:)
    user = company.users.create(params[:user].merge(invited_by: current_user))
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.create(
      params:,
      company: current_company,
      current_user: current_user
    )
  end
end
```

---

## CRUD Examples

### Index

A simple index action needs no params and no schema:

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  def index(company:)
    users = company.users.order(:name)
    Ok(resource: users.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def index
    render Users::IndexAction.index(company: current_company)
  end
end
```

### Show

```ruby
class Users::ShowAction
  include ActionFigure[:jsend]

  params_schema do
    required(:id).filled(:integer)
  end

  def show(params:, company:)
    user = company.users.find_by(id: params[:id])
    return NotFound(errors: { base: ["user not found"] }) unless user

    Ok(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def show
    render Users::ShowAction.show(params:, company: current_company)
  end
end
```

### Create

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end
  end

  def create(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) unless user.persisted?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.create(params:, company: current_company)
  end
end
```

### Update

```ruby
class Users::UpdateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:id).filled(:integer)
    required(:user).hash do
      optional(:name).filled(:string)
      optional(:email).filled(:string)
    end
  end

  def update(params:, company:)
    user = company.users.find_by(id: params[:id])
    return NotFound(errors: { base: ["user not found"] }) unless user

    user.update(params[:user])
    return UnprocessableContent(errors: user.errors.messages) unless user.errors.empty?

    Ok(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def update
    render Users::UpdateAction.update(params:, company: current_company)
  end
end
```

### Destroy

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  params_schema do
    required(:id).filled(:integer)
  end

  def destroy(params:, company:)
    user = company.users.find_by(id: params[:id])
    return NotFound(errors: { base: ["user not found"] }) unless user

    user.destroy!
    NoContent()
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.destroy(params:, company: current_company)
  end
end
```

For authorization, serialization, and pagination patterns, see [Integration Patterns](integration-patterns.md).

---

## Other Examples

Actions aren't limited to CRUD. The pattern works anywhere you need to validate input, orchestrate work, and return a formatted response. In each case the action delegates to a service object and translates the result:

```ruby
class Users::BulkInviteAction
  include ActionFigure[:jsend]

  params_schema do
    required(:emails).value(:array, min_size?: 1).each(:str?)
  end

  def invite(params:, company:)
    result = BulkInviteService.call(emails: params[:emails], company: company)
    return UnprocessableContent(errors: result.errors) if result.failures?

    Created(resource: result.invitations)
  end
end
```

```ruby
class Users::InvitesController < ApplicationController
  def create
    render Users::BulkInviteAction.invite(params:, company: current_company)
  end
end
```

Use `Accepted` when the real work happens asynchronously:

```ruby
class Reports::GenerateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:report).hash do
      required(:type).filled(:string)
      optional(:start_date).filled(:date)
      optional(:end_date).filled(:date)
    end
  end

  def generate(params:, current_user:)
    result = ReportService.enqueue(params: params[:report], requested_by: current_user)
    return UnprocessableContent(errors: result.errors) if result.failed?

    Accepted(resource: { id: result.report_id, status: "queued" })
  end
end
```

```ruby
class ReportsController < ApplicationController
  def create
    render Reports::GenerateAction.generate(params:, current_user: current_user)
  end
end
```

File imports work the same way — receive the file, hand it off, translate the outcome:

```ruby
class Products::ImportAction
  include ActionFigure[:jsend]

  def import(file:, company:)
    result = ProductImportService.call(file: file, company: company)
    return UnprocessableContent(errors: result.errors) if result.failed?

    Ok(resource: { imported: result.imported_count, skipped: result.skipped_count })
  end
end
```

```ruby
class Products::ImportsController < ApplicationController
  def create
    render Products::ImportAction.import(file: params[:file], company: current_company)
  end
end
```

---

## API Versioning

The `api_version` class macro attaches version metadata to an action class.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  api_version "2.0"

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def create(params:)
    user = User.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

### Reading the version

Call `api_version` with no arguments to read the stored value:

```ruby
Users::CreateAction.api_version  #=> "2.0"
```

Inside an action instance, access it through the class:

```ruby
def create(params:, **)
  if self.class.api_version == "2.0"
    # v2 behavior
  end
end
```

### Defaults

If no `api_version` is declared on a class, it returns `nil` by default. A global version is available through configuration:

```ruby
ActionFigure.configure do |config|
  config.api_version = "1.0"
end
```

The global value reads from **`ActionFigure.configuration.api_version`**. It never acts as an automatic fallback for **`api_version` on the class**: the two strings are intentionally separate. Use **`config.api_version`** for **infra-wide defaults** — release dashboards, outbound headers assembled in middleware, initializer documentation — without forcing each action constant to duplicate the same value. Put **`api_version "2.0"`** on classes when that action participates in explicit version branching. Versions are independent per class and **not inherited** by subclasses (state lives in class-level instance variables).

---

## File Conventions

Name action classes `ResourceName::VerbAction`. There are two common ways to organize them:

**Standalone directory** — action classes live in `app/actions/`:

```
app/actions/
  users/
    create_action.rb
    destroy_action.rb
    index_action.rb
    show_action.rb
    update_action.rb
  orders/
    search_action.rb
    cancel_action.rb
```

**Alongside controllers** — action classes live next to the controllers that use them:

```
app/controllers/
  users_controller.rb
  users/
    create_action.rb
    destroy_action.rb
    index_action.rb
    show_action.rb
    update_action.rb
  orders_controller.rb
  orders/
    search_action.rb
    cancel_action.rb
```

Both work with Rails autoloading. The second option keeps related code together — when you open a controller, its actions are right there.

---

## Design Constraints

Action classes are intentionally flat. The class-level state that powers `params_schema`, `rules`, and `entry_point` is stored in **class-level instance variables** and is **not inherited** by subclasses. If you subclass an action, the child class starts with a blank slate -- no schema, no rules, no custom entry point.

This is by design. Each action class should be a self-contained, independently readable unit. If you find yourself wanting to share behavior across actions, extract shared logic into plain Ruby modules or service objects and compose them explicitly.
