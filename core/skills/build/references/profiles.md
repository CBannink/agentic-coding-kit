# Internal Build Profiles

Infer independent dimensions; never require a public mode catalog.

```yaml
intent: feature | fix | refactor | maintenance
surfaces: [ui, api, data, config, cli, docs]
assurance: [regression, migration, browser, security, compatibility]
```

- Feature: map integration points, observable states, failure behavior, and
  consumer compatibility.
- Fix: reproduce exactly when practical, isolate root cause, add a durable
  regression test when useful, and inspect nearby variants.
- Refactor: characterize behavior, map interfaces/consumers, prevent semantic
  drift, and migrate all call sites.
- Migration assurance: map producers/consumers, old/new compatibility, rollout,
  rollback, idempotency, and partial failure.
- UI: map routes/components/design system, states/viewports, browser evidence,
  focus/keyboard/responsive behavior.
- Configuration: map consumers, defaults/precedence, parser/schema behavior,
  environment inputs, invalid/missing values, and docs/examples.
- API: map public contract, consumers, validation/error shape, authorization,
  compatibility, and contract tests.
- Data: map schema, transaction/consistency boundaries, idempotency, rollback,
  partial failure, and representative fixtures.
