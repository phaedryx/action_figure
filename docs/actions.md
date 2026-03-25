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
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, company:, **)
    user = company.users.create!(params)
    resource = UserBlueprint.render_as_hash(user)
    Created(resource:)
  end
end
```

Wire it into a controller by passing `params:` and any additional context:

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params: params.require(:user), company: current_company)
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

  def search(params:, company:, **)
    orders = company.orders
    orders = orders.where(id: params[:order_id])                 if params[:order_id]
    orders = orders.where(tracking_number: params[:tracking_number]) if params[:tracking_number]
    orders = orders.where(status: params[:status])               if params[:status]
    resource = OrderBlueprint.render_as_hash(orders)
    Ok(resource:)
  end
end
```

Call it from a controller using the declared name:

```ruby
class OrdersController < ApplicationController
  def index
    render Orders::SearchAction.search(params: params.permit!, company: current_company)
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

Actions that don't need validated input simply omit `params_schema`. Instead of accepting `params:`, they receive only the keyword arguments you pass from the controller.

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  def call(user_id:, current_user:)
    user = User.find(user_id)
    user.destroy!
    NoContent()
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.call(user_id: params[:id], current_user: current_user)
  end
end
```

Because no `params_schema` is defined, the validation pipeline is skipped entirely. If you accidentally pass `params:` to an action that has no schema, ActionFigure raises immediately:

```
ArgumentError: params: passed but no params_schema defined
```

---

## Dependency Injection

Non-`params:` keyword arguments pass through to the instance method untouched. This is how you inject context from the controller -- the current user, the tenant, a logger, or any other collaborator -- without any special DSL.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, company:, current_user:, **)
    user = company.users.create!(params.merge(invited_by: current_user))
    resource = UserBlueprint.render_as_hash(user)
    Created(resource:)
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(
      params: params.require(:user),
      company: current_company,
      current_user: current_user
    )
  end
end
```

The double-splat (`**`) in the method signature is a good habit -- it lets you add new injected dependencies at the call site without changing every action that doesn't need them.

---

## Authorization

Authorization gems work naturally with action classes. Inject the current user from the controller and call the authorization check during orchestration.

### Pundit

Call the [Pundit](https://github.com/varvet/pundit) policy directly inside the action:

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  def call(user_id:, current_user:)
    user = User.find(user_id)
    unless UserPolicy.new(current_user, user).destroy?
      return Forbidden(errors: { base: ["not authorized to delete this user"] })
    end
    user.destroy!
    NoContent()
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.call(user_id: params[:id], current_user: current_user)
  end
end
```

### CanCanCan

With [CanCanCan](https://github.com/CanCanCommunity/cancancan), build the ability from the current user:

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  def call(user_id:, current_user:)
    user = User.find(user_id)
    if Ability.new(current_user).can?(:destroy, user)
      user.destroy!
      NoContent()
    else
      Forbidden(errors: { base: ["not authorized to delete this user"] })
    end
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.call(user_id: params[:id], current_user: current_user)
  end
end
```

In both cases, authorization failures return a `Forbidden` response through the same formatter pipeline as everything else -- no exceptions, no controller rescue needed.

---

## Index Actions

A simple index action needs no params and no schema:

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  def call(company:, **)
    users = company.users.order(:name)
    resource = UserBlueprint.render_as_hash(users)
    Ok(resource:)
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

### Cursor Pagination

For paginated lists, accept cursor params and delegate the query logic to a service object. The action orchestrates -- the service does the heavy lifting:

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  params_schema do
    optional(:cursor).filled(:integer)
    optional(:limit).filled(:integer)
  end

  def call(params:, company:, **)
    page = UserQuery.page(company.users, cursor: params[:cursor], limit: params[:limit] || 20)
    resource = UserBlueprint.render_as_hash(page.records)
    Ok(resource:, meta: { next_cursor: page.next_cursor })
  end
end
```

```ruby
class UsersController < ApplicationController
  def index
    render Users::IndexAction.call(params:, company: current_company)
  end
end
```

The action checks params, delegates to `UserQuery` for the actual query, and formats the response. `UserQuery` is a plain Ruby class that knows how to paginate -- the action doesn't need to.

The same pattern works with pagination gems. Here's the same action using [activerecord_cursor_paginate](https://github.com/fatkodima/activerecord_cursor_paginate):

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  params_schema do
    optional(:cursor).filled(:string)
    optional(:limit).filled(:integer)
  end

  def call(params:, company:, **)
    page = company.users
      .cursor_paginate(after: params[:cursor], limit: params[:limit] || 20, order: :name)
      .fetch
    resource = UserBlueprint.render_as_hash(page.records)
    Ok(resource:, meta: { next_cursor: page.next_cursor, has_next: page.has_next? })
  end
end
```

Or with [pagy](https://github.com/ddnexus/pagy):

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]
  include Pagy::Backend

  def call(request:, company:, **)
    pagy, users = pagy(:keyset, company.users.order(:name), request:)
    resource = UserBlueprint.render_as_hash(users)
    Ok(resource:, meta: { next: pagy.next })
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
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, **)
    user = User.create!(params)
    resource = UserBlueprint.render_as_hash(user)
    Created(resource:)
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
    index_action.rb
    create_action.rb
    destroy_action.rb
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
    index_action.rb
    create_action.rb
    destroy_action.rb
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
