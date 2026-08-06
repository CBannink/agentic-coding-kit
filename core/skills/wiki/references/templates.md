# Wiki Page Templates

Hard ceilings cover the complete rendered files: `index.md` 250 words,
`repository-map.md` 400, `engineering.md` 500, and `coding.md`, `reviewing.md`,
`testing.md`, and `security.md` 400 each. They are ceilings, not targets.

`index.md` is generated last. It is a minimal task router with a source-authority
notice, exact task-to-section links, and optional workspace links; it does not
duplicate content.

`repository-map.md` begins with a repository-purpose summary of at most 100
words, then maps top-level ownership, real entry points,
canonical/generated/vendor/build/fixture boundaries, nearest tests, and common
change routes without enumerating every file.

`engineering.md` combines architecture and operational engineering: dependency
and ownership direction, state ownership, external boundaries, invariants,
commands, generation, verification, and representative flows:

```text
entry -> orchestration/service -> boundary/client
-> persistence/output -> nearest test
```

`coding.md` has at most ten concise, evidenced repository-specific practices
covering applicable syntax/branching, validation/errors, organization, naming,
API reuse, state/configuration, and generated boundaries. Omit unsupported
rules. `reviewing.md` records review invariants, realistic risks, evidence
expectations, and maintainability concerns without repeating coding rules.
`testing.md` records actual locations, types, naming, fixtures/mocks/assertions,
when tests are expected, focused/full commands, and representative patterns.
`security.md` is always present and contains only demonstrated trust boundaries,
controls, sensitive assets, and security-relevant tests; stay brief when little
is found.

Optional integration, host, workspace, area, and consented PR-history pages
exist only when independent retrieval value is demonstrated.
