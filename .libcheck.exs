[
  github_workflows: [
    elixir_checks: false
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
  ],
  cliff: [
    commit_parsers: [
      [message: "^deps:", skip: false, group: "<!-- 7 -->📦 Dependencies"]
    ]
  ]
]
