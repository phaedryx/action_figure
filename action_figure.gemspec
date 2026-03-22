# frozen_string_literal: true

require_relative "lib/action_figure/version"

Gem::Specification.new do |spec|
  spec.name = "action_figure"
  spec.version = ActionFigure::VERSION
  spec.authors = ["Tad Thorley"]

  spec.summary = "Fully-articulated controller actions"
  spec.description = "Replaces service objects with explicit, purpose-driven classes for Rails controller actions"
  spec.homepage = "https://github.com/phaedryx/action_figure"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dry-validation", "~> 1.10"
end
