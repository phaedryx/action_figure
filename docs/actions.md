# Actions

## Overview

An ActionFigure action class is a single-purpose operation. Each class encapsulates one thing your application does -- creating a user, searching orders, processing a refund. This guide covers how to declare action classes, customize their entry points, inject dependencies, and wire them into your controllers.

---

## The Default: `call`

Every action class gets a `.call` class method when it includes ActionFigure. It instantiates the class, runs the validation pipeline (if `params:` is provided), and delegates to the instance-level `#call` method.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def call(params:, company:, **)
    user = company.users.create!(params[:user])
    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

Wire it into a controller by passing `params:` and any additional context:

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
  end
end
```

---

## Custom Entry Points

Some actions have a name that reads better than `.call`. The `entry_point` macro declares an alternative class-level method name:

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
end
```

Call it from a controller using the declared name:

```ruby
class OrdersController < ApplicationController
  def index
    render Orders::SearchAction.search(params:, company: current_company)
  end
end
```

### How it works

- The instance method must match the declared entry point name (`:search` declares `.search` and expects `#search`). If an entry point is defined, any instance-level `#call` method is ignored by the class-level entry point.
- The full validation pipeline still runs through the custom entry point -- `params_schema` and `rules` are applied before your method is invoked.
- Calling `.call` on a class that declares a custom entry point raises a `NoMethodError` with a helpful message:

  ```
  NoMethodError: undefined method 'call' for Orders::SearchAction (use 'search' instead)
  ```

- Only one entry point per class is allowed. A second `entry_point` declaration raises an `ArgumentError`:

  ```
  ArgumentError: entry_point already defined as 'search' — each action class may declare only one entry point
  ```

---

## No-Params Actions

Actions that don't need validated input simply omit `params_schema`. The validation pipeline is skipped entirely.

```ruby
class HealthCheckAction
  include ActionFigure[:jsend]

  def call
    Ok(resource: { status: "healthy", time: Time.current })
  end
end
```

```ruby
class HealthController < ApplicationController
  def show
    render HealthCheckAction.call
  end
end
```

If you accidentally pass `params:` to an action that has no schema, ActionFigure raises immediately:

```
ArgumentError: params: passed but no params_schema defined
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

  def call(params:, company:, current_user:)
    user = company.users.create!(params[:user].merge(invited_by: current_user))
    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(
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

  def call(company:)
    users = company.users.order(:name)
    Ok(resource: users.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def index
    render Users::IndexAction.call(company: current_company)
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

  def call(params:, company:)
    user = company.users.find_by(id: params[:id])
    return NotFound(errors: { base: ["user not found"] }) unless user

    Ok(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def show
    render Users::ShowAction.call(params:, company: current_company)
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

  def call(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) unless user.persisted?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:, company: current_company)
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

  def call(params:, company:)
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
    render Users::UpdateAction.call(params:, company: current_company)
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

  def call(params:, company:)
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
    render Users::DestroyAction.call(params:, company: current_company)
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

  def call(params:, company:)
    result = BulkInviteService.call(emails: params[:emails], company: company)
    return UnprocessableContent(errors: result.errors) if result.failures?

    Created(resource: result.invitations)
  end
end
```

```ruby
class Users::InvitesController < ApplicationController
  def create
    render Users::BulkInviteAction.call(params:, company: current_company)
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

  def call(params:, current_user:)
    result = ReportService.enqueue(params: params[:report], requested_by: current_user)
    return UnprocessableContent(errors: result.errors) if result.failed?

    Accepted(resource: { id: result.report_id, status: "queued" })
  end
end
```

```ruby
class ReportsController < ApplicationController
  def create
    render Reports::GenerateAction.call(params:, current_user: current_user)
  end
end
```

File imports work the same way — receive the file, hand it off, translate the outcome:

```ruby
class Products::ImportAction
  include ActionFigure[:jsend]

  def call(file:, company:)
    result = ProductImportService.call(file: file, company: company)
    return UnprocessableContent(errors: result.errors) if result.failed?

    Ok(resource: { imported: result.imported_count, skipped: result.skipped_count })
  end
end
```

```ruby
class Products::ImportsController < ApplicationController
  def create
    render Products::ImportAction.call(file: params[:file], company: current_company)
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

  def call(params:)
    user = User.create!(params[:user])
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
def call(params:, **)
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

The global version is accessible via `ActionFigure.configuration.api_version` but is not used as an automatic fallback for class-level `api_version`. Version values are independent per class -- they are not inherited by subclasses because version state is stored in class-level instance variables.

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
