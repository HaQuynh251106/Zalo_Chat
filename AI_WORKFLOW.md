# Lumo AI Workflow

## Current State
Phase 0 MVP is complete.

## Target
Phase 1 Production-ready.

## Standard Flow
1. Human creates task in docs/ai-tasks.
2. Claude creates implementation plan.
3. Codex implements on codex/<task>.
4. Codex runs tests.
5. Claude reviews diff.
6. Codex fixes blocking issues.
7. Human reviews and merges.

## Do Not
- Do not ask Codex to "build Zalo".
- Do not allow Claude and Codex to edit the same branch simultaneously.
- Do not mix auth, chat, media, push, and observability in one PR.
- Do not migrate to microservices during Phase 1 unless explicitly planned.

## Phase 1 Priority Order
1. CI/CD and tests
2. Auth security hardening
3. Refresh token rotation
4. Device management
5. Chat missing features
6. Group management
7. Push notification worker
8. Media production storage
9. Observability
10. Web/Desktop polish