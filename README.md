# Libdev

This is a meta-package for Elixir library authors to simplify the management of
development libraries when working on multiple projects.

This package includes the following packages:

<!-- rdmx libdev:readme_deps -->

* [credo](https://hex.pm/packages/credo)
* [dialyxir](https://hex.pm/packages/dialyxir)
* [ex_doc](https://hex.pm/packages/ex_doc)
* [mix_audit](https://hex.pm/packages/mix_audit)
* [sobelow](https://hex.pm/packages/sobelow)

<!-- rdmx /libdev:readme_deps -->

## Installation

To pull all the included packages, install the dependency for `:dev` and `:test`
environments:

```elixir
def deps do
  [
    {:libdev, ">= 0.0.0", only: [:dev, :test], runtime: false}
  ]
end
```

## Dependabot

This meta package relies on daily dependabot updates and is published to [Hex](https://hex.pm/) weekly, on Sundays, when its dependencies have been updated during the week.

You should also setup
[Dependabot](https://docs.github.com/en/code-security/getting-started/dependabot-quickstart-guide)
for your repository in order to get updates from libdev.
