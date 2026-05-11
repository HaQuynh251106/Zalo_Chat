# Phase 1 Production-ready Roadmap

## Goal
Make Lumo safe enough for real users.

## Capacity Target
~1,000 real users initially, then up to ~10k MAU.

## Priority 1: CI/CD + Testing
- GitHub Actions
- Go integration tests
- Flutter widget tests
- Migration tool
- Staging environment

## Priority 2: Auth Security
- OTP via SMS
- Reset password via OTP
- Rate limit auth endpoints
- Refresh token rotation
- Revoke list
- Device management UI
- Argon2id password hashing
- HTTPS/HSTS/CSP/security headers
- Auth audit log

## Priority 3: Chat Completion
- Reply message UI
- Forward message
- Message reactions
- Voice message
- Stickers/GIF
- Pin message
- Message search
- Scroll-up pagination
- Mute conversation
- Block user
- Delete for me

## Priority 4: Group Advanced
- Admin/member roles
- Kick member
- Transfer owner
- Invite link
- QR invite
- Approval mode
- Group avatar/name/description

## Priority 5: Real Push
- Push worker
- NATS message.new topic
- FCM/APNs
- Badge count
- Notification preferences
- In-app notification center

## Priority 6: Production Media
- S3/MinIO
- CDN
- Thumbnail worker
- Video transcoding
- Pre-signed upload URL
- BlurHash
- File whitelist
- Virus scan

## Priority 7: Observability
- Prometheus metrics
- Loki logs
- Tempo traces
- Dashboard
- Alerts