# Lumo / Zala AI Agent Rules

## Project Context
Lumo is a Phase 0 MVP messaging platform inspired by Zalo.

Phase 0 is already complete:
- Auth register/login/refresh JWT/device
- 1-1 and group conversations
- Text/image messages
- Message recall within 24h
- WebSocket hub
- Presence
- Typing
- Multi-device sync
- Feed with reactions/comments/visibility
- Local media upload
- Call signaling
- Push-token registration endpoint

Current goal:
Move from Phase 0 MVP to Phase 1 Production-ready.

## AI Roles
- Claude: architect, planner, reviewer, security reviewer.
- Codex: implementer, tester, fixer.
- Human: product owner and final merger.

## Codex Rules
- Do not rebuild the app from scratch.
- Preserve existing architecture unless task requires change.
- Keep changes small and focused.
- One task per branch.
- Do not refactor unrelated code.
- Add or update tests for changed behavior.
- Never commit secrets.
- Never hardcode credentials.
- Always explain files changed.

## Security Rules
- Never trust client-provided userId.
- Validate all API inputs.
- Check auth and authorization on private APIs.
- Do not leak messages, conversations, feed posts, or media across users.
- Use rate limit for sensitive endpoints.
- Store secrets in env variables only.

## Required Checks
Run relevant checks before final response:
- go test ./...
- flutter test
- npm test if applicable
- lint/typecheck/build commands if present

## Git Rules
- Never commit directly to main.
- Codex branches: codex/<task-name>
- Claude review branches: claude/review-<task-name>
- One feature per branch.
- One PR per feature.

## Final Response Format
Return:
1. Summary
2. Files changed
3. Tests run
4. Risks / follow-ups