[
  github_workflows: [
    elixir_checks: false,
    dependencies: true,
  ],
  dependencies: [
    allow_prod_env: [
      :credo,
      :dialyxir,
      :doctor,
      :ex_check,
      :ex_doc,
      :mix_audit,
      :sobelow
    ]
  ],
  dependabot: [
    schedule: "weekly",
    timezone: "Etc/UTC"
  ]
]
