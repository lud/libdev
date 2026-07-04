[
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
    schedule: "daily",
    timezone: "Etc/UTC",
    max_pull_requests: 2
  ],
  cliff: [
    commit_parsers: [
      [message: "^deps:", skip: false, group: "<!-- 7 -->📦 Dependencies"]
    ]
  ]
]
