# frozen_string_literal: true

require_relative "action_figure/version"
require_relative "action_figure/configuration"
require_relative "action_figure/format_registry"

# ActionFigure provides explicit, purpose-driven operation classes for Rails controller actions.
module ActionFigure
  extend Configuration
  extend FormatRegistry
end
