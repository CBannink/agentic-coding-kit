# Contracts and Handoffs

Omit empty headings. Use handoffs as indexes to current evidence.

## Dynamic Assignment

```markdown
# Assignment
## Mission
## Questions to answer
## Decision this unlocks
## Current contract
## Relevant repository knowledge
## Start here
## Stop when
## Current workspace state
## Evidence already available
## Return
```

Include the question, decision, and stop fields for discovery assignments;
omit them when they add no value. Every handoff returns to the main
orchestrator, which validates and curates it before constructing another
assignment. Agents never dispatch the next role and transcripts are never
forwarded as packets.

## Build Contract

```markdown
# Build Contract r1
## Request
## Outcome
## Current behavior and evidence
## Acceptance examples
## Preserve
## Relevant implementation context
## Proof plan
### Minimum implementation tests
### Fast checks
### Independent test focus
### Final verification
### Visual or browser evidence
## Assumptions and open facts
## Non-goals
```

## Scout Brief

Status `CLEAR | NEEDS_SCOPE | WIKI_DRIFT`; mission answered; exact wiki
sections; relevant flow; implementation surface; verification; material
unknowns and cheapest next checks.

## Coder Report

Status `DONE | CONTRACT_GAP | BLOCKED`; implemented behavior; changed paths;
tests; command/result/proof table; acceptance coverage; material concern; gap
evidence when applicable.

## Review Report

Verdict `PASS | REPAIR | RECONTRACT | VERIFY_MORE`; contract assessment;
evidence-backed severity findings; test assessment; missing evidence; relevant
strengths.

## Test Engineer Report

Outcome `PASS | CODE_DEFECT | TEST_DEFECT | CONTRACT_GAP | BLOCKED`; charter;
tests and test-only files changed; command/result/proof table; exact defect
evidence; limitations.

## Failure Brief

Failure; minimal reproduction; classification; evidence; hypotheses and
discriminating checks; likely owner; one next action.

## Sage Decision Memo

Question; current proposal; strongest case/countercase; hidden assumptions;
material alternatives; falsifying experiment; recommendation; confidence;
what changes it.
