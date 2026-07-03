# frozen_string_literal: true

require "rack/utils"

module ActionFigure
  module Formatters
    # Implements RFC 9457 (Problem Details for HTTP APIs) response helpers.
    # Errors render as application/problem+json documents. Success responses
    # mirror the same type/title vocabulary.
    #
    # Defaults for type and title are derived mechanically from class names and
    # status symbols — deliberately unattractive. Pass type: and title: kwargs
    # to provide stable, documented values your clients can rely on.
    module Rfc9457
      include ActionFigure::Formatter

      def Ok(resource:, meta: nil, as: nil, type: nil, title: nil)
        build_success(resource: resource, meta: meta, as: as,
                      type: type, title: title, status: :ok)
      end

      def Created(resource:, meta: nil, as: nil, type: nil, title: nil)
        build_success(resource: resource, meta: meta, as: as,
                      type: type, title: title, status: :created)
      end

      def Accepted(resource: nil, meta: nil, as: nil, type: nil, title: nil)
        build_success(resource: resource, meta: meta, as: as,
                      type: type, title: title, status: :accepted)
      end

      def UnprocessableContent(errors: nil, type: "unprocessable-content-error", **extras)
        error_response(status: :unprocessable_content, errors: errors, type: type, **extras)
      end

      # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
      def error_response(status:, errors: nil, type: nil, title: nil, detail: nil, instance: nil, **extras)
        name  = action_name_for_error
        word  = status_word(status)
        body  = {}
        body[:type]     = type  || derive_type(name, "#{word}-error")
        body[:title]    = title || rack_status_title(status)
        body[:status]   = ActionFigure.status_code_for(status)
        body[:detail]   = detail   if detail
        body[:instance] = instance if instance
        body[:errors]   = errors   unless errors.nil?
        extras.each { |k, v| body[k] = v }
        { json: body, status: status, content_type: "application/problem+json" }
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize

      PRIMITIVE_CLASSES = [Hash, Array, String, Numeric, Integer, Float, Symbol,
                           TrueClass, FalseClass, NilClass].freeze

      private

      # rubocop:disable Metrics/ParameterLists
      def build_success(resource:, meta:, as:, type:, title:, status:)
        name, key = resource_info(resource, as)
        word   = status_word(status)
        body   = {}
        body[:type]  = type  || derive_type(name, word)
        body[:title] = title || derive_title(name, word)
        body[key]    = resource unless resource.nil? && status == :accepted
        body[:meta]  = meta if meta
        { json: body, status: status }
      end
      # rubocop:enable Metrics/ParameterLists

      # Returns [name, key] where name drives type/title derivation and key
      # is the JSON member. Primitives and anonymous classes use name "resource"
      # and key :data; model-like objects use their dasherized class name for both.
      def resource_info(resource, as_kwarg)
        if as_kwarg
          name = dasherize_class_name(as_kwarg.to_s)
          return [name, as_kwarg.to_sym]
        end

        klass = resource.class
        return ["resource", :data] if primitive_class?(klass) || klass.name.nil?

        name = dasherize_class_name(klass.name)
        [name, name.gsub("-", "_").to_sym]
      end

      # Returns the action class's dasherized name (Action suffix stripped)
      # for use as the error type prefix.
      def action_name_for_error
        klass_name = self.class.name
        return "action" if klass_name.nil?

        dasherize_class_name(klass_name)
      end

      # Converts a Ruby class name string to a dasherized, Action-stripped slug.
      # Examples:
      #   "User"                 -> "user"
      #   "Admin::UserProfile"   -> "admin-user-profile"
      #   "Projects::CreateAction" -> "projects-create"
      def dasherize_class_name(name)
        name
          .sub(/Action\z/, "")   # strip trailing "Action"
          .gsub("::", "-")       # namespace separator -> dash
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2') # e.g. XMLParser -> XML-Parser
          .gsub(/([a-z\d])([A-Z])/, '\1-\2') # camelCase -> camel-Case
          .downcase
          .squeeze("-")          # collapse any double-dashes from empty namespace parts
          .sub(/\A-/, "")        # remove leading dash if Action was the only segment
          .sub(/-\z/, "")        # remove trailing dash
      end

      # Status word derived from the Rack status symbol (underscores -> dashes).
      # Examples: :ok -> "ok", :not_found -> "not-found", :created -> "created"
      def status_word(status_symbol)
        status_symbol.to_s.tr("_", "-")
      end

      def derive_type(name, word)
        "#{name}-#{word}"
      end

      # Builds a human title from a dasherized name and a status word.
      # Examples: ("user", "created") -> "User created"
      #           ("admin-user-profile", "created") -> "Admin user profile created"
      def derive_title(name, word)
        phrase = "#{name.gsub("-", " ")} #{word.tr("-", " ")}"
        phrase[0].upcase + phrase[1..]
      end

      def rack_status_title(status_symbol)
        code = ActionFigure.status_code_for(status_symbol)
        Rack::Utils::HTTP_STATUS_CODES[code] || status_symbol.to_s.tr("_", " ").capitalize
      end

      def primitive_class?(klass)
        PRIMITIVE_CLASSES.any? { |p| klass <= p }
      end
    end
  end
end
