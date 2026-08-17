# ADR 0000 — Record Architecture Decisions

Date: 2026-08-17
Status: Accepted

---

## Context

Architecture decisions made during the design and build of Yagye are often not obvious from the code alone. Why we chose PostgreSQL over a distributed database, why IDs are time-sortable, why the ledger is double-entry — these have context, trade-offs, and alternatives that the code cannot express. Without a record, that context lives only in the heads of the original authors and is lost as the team grows or time passes.

---

## Decision

We will record significant architecture decisions in `docs/decisions/` using the format introduced by Michael Nygard: short text files with a **Context → Decision → Consequences** structure.

**What qualifies as an ADR:**
- Technology or library choices with meaningful trade-offs
- Structural decisions that constrain future work (data model shape, module boundaries, ID schemes)
- Decisions that reverse or supersede an earlier choice
- Anything a new engineer would need to understand to avoid re-litigating the decision

**What does not qualify:**
- Implementation details that are obvious from the code
- Decisions with no real alternatives (e.g. "we use Elixir because the project is in Elixir")
- Routine library upgrades

**Format:** each ADR is a Markdown file named `NNNN-short-title.md`, numbered sequentially starting from 0000. Numbers are never reused. Status is one of `Accepted`, `Superseded by ADR-NNNN`, or `Deprecated`.

**Process:**
1. Identify a decision that meets the criteria above
2. Write a draft in `docs/decisions/` on a feature or chore branch
3. Merge via PR — the PR discussion is the decision review

---

## Consequences

- New engineers can understand *why* the system is shaped the way it is, not just *what* it does.
- The cost of recording is low: a few paragraphs per decision.
- Decisions that are later found wrong are marked `Superseded` and a new ADR records the replacement. Old ADRs are never deleted — understanding why a previous approach was abandoned is as valuable as understanding the current one.
