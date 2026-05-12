# Lumo — IM platform (Go + Flutter)

> Tên thương hiệu: **Lumo** — nhánh khác của kiến trúc trong PDF
> *"Kiến trúc hệ thống nền tảng IM kiểu Zalo (Go + Flutter)"*.
> Backend Go monolith mô-đun hoá, mobile Flutter, sẵn sàng tách microservices.

---

## Tính năng đã có

### Core IM
- 🔐 Đăng ký / Đăng nhập (bcrypt + JWT access + refresh, token-type guard)
- 👥 Danh bạ: gửi lời mời, chấp nhận
- 💬 Hội thoại 1-1 (get-or-create) + nhóm
- ⏪ Thu hồi tin nhắn trong 24h (broadcast realtime)
- ✓✓ Read receipt + unread count
- 🟢 Presence (online/offline + last_seen + Redis TTL cache)
- ⌨️ Typing indicator server-validated
- 🔄 Multi-device sync qua WebSocket Hub

### Mở rộng
- 📔 **Nhật ký (Feed)**: bài viết, ảnh, reaction, comment, visibility public/friends/private
- 📎 **Media upload**: multipart, lưu disk, serve `/static/...`, whitelist extension, max 20 MiB
- 📱 **Push-token register** cho FCM/APNs (worker đẩy tin chưa làm — placeholder)

### Mobile
- 🎨 Theme **Indigo + Violet + Coral** (khác hẳn Zalo) — Material 3
- 🧭 Bottom navigation 4 tab: **Tin nhắn / Danh bạ / Nhật ký / Cá nhân**
- ✨ Login frosted-glass với gradient + blob decoration
- 💎 Chat bubble gradient cho tin của mình + day separator + typing dots animation
- 🟣 Avatar gradient ring + presence dot

---

## Cấu trúc thư mục

```
zalo-clone/
├── backend/                    # Go monolith
│   ├── cmd/server/
│   ├── internal/
│   │   ├── auth/               # register, login, refresh JWT
│   │   ├── user/               # profile + push-token
│   │   ├── contact/            # kết bạn
│   │   ├── conversation/       # direct & group + mark-read broadcast
│   │   ├── message/            # gửi, list, thu hồi
│   │   ├── feed/               # Nhật ký (post, react, comment) — NEW
│   │   ├── media/              # multipart upload + static serve — NEW
│   │   ├── ws/                 # Hub: presence, typing, broadcast
│   │   ├── middleware/         # JWT
│   │   ├── router/             # mount route
│   │   ├── db/                 # pgxpool + redis
│   │   ├── httpx/              # JSON envelope
│   │   └── config/             # env loader
│   ├── migrations/             # 001_init.sql (toàn schema)
│   ├── uploads/                # local media storage (volume)
│   ├── scripts/                # migrate.sh
│   └── Dockerfile
├── mobile/                     # Flutter
│   └── lib/
│       ├── main.dart
│       ├── theme.dart          # Indigo/Violet + Coral — NEW
│       ├── models/             # user, conversation, message, post
│       ├── services/           # api_client + ws_client
│       ├── providers/          # AuthProvider
│       ├── widgets/            # avatar, bubble, gradient_button, typing_dots — NEW
│       └── screens/
│           ├── login_screen.dart            # frosted-glass + gradient
│           ├── home_shell.dart              # bottom nav 4 tab — NEW
│           ├── conversations_screen.dart    # search, gradient avatar
│           ├── chat_screen.dart             # bubble gradient, typing dots
│           ├── contacts_screen.dart         # NEW
│           ├── feed_screen.dart             # NEW
│           └── profile_screen.dart          # NEW
├── docs/
└── docker-compose.yml          # Postgres + Redis + NATS + backend + uploads volume
```

---

## Cách chạy

### Cách A — Docker (đơn giản nhất)

```bash
cd zalo-clone
docker compose up --build
```

- API: `http://localhost:8080`
- Static media: `http://localhost:8080/static/...`
- Postgres: `localhost:5432` (zalo/zalo/zalo)
- Redis: `localhost:6379`
- Migration `backend/migrations/*.sql` được Postgres tự chạy lần đầu khởi tạo volume.

### Cách B — Chạy Go local

```bash
docker compose up -d postgres redis
cd backend
cp .env.example .env
go mod tidy
go run ./cmd/server
```

Healthcheck: `curl http://localhost:8080/healthz`

### Flutter

```bash
cd mobile
flutter create --org com.lumo --project-name lumo .   # tạo platform folders lần đầu
flutter pub get

# iOS sim / desktop / web
flutter run --dart-define=API_BASE=http://localhost:8080

# Android emulator (10.0.2.2 = host)
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

## Running tests locally

Backend:

```bash
cd backend
go vet ./...
go build ./...
go test ./... -race -count=1 -timeout=120s
```

Mobile:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

CI:

- `.github/workflows/backend.yml` runs Go vet, build, and tests on every push and pull request.
- `.github/workflows/mobile.yml` runs Flutter dependency install, analyze, and tests on every push and pull request.

Known failures:

- On a clean checkout of `main`, backend vet/build/test currently fail because `backend/internal/router` references device/logout methods that are not implemented on `auth.Handler` yet (`ListDevices`, `LogoutAllDevices`, `LogoutDevice`, `LogoutCurrent`). This is tracked outside Task 001 because auth/device handling is out of scope for the CI baseline.
- On a clean checkout of `main`, `flutter analyze` currently reports existing lint issues in `mobile/lib/screens/call_screen.dart`, `mobile/lib/screens/devices_screen.dart`, and `mobile/lib/screens/feed_screen.dart`. Screen/UI changes are out of scope for Task 001.

---

## API tóm tắt

Tất cả trả JSON envelope: `{"data": ...}` hoặc `{"error": "..."}`.

### Public

| Method | Path | Body |
|---|---|---|
| POST | `/api/v1/auth/register` | `{phone, password, display_name}` |
| POST | `/api/v1/auth/login` | `{phone, password, device_id, device_name, platform}` → `{user, access_token, refresh_token, device_id}` |
| POST | `/api/v1/auth/refresh` | `{refresh_token}` → cùng shape login |
| GET  | `/static/*` | Phục vụ file đã upload |

### Cần `Authorization: Bearer <access_token>`

#### User & contact
| Method | Path | Mô tả |
|---|---|---|
| GET  | `/api/v1/me` | Profile của tôi |
| PUT  | `/api/v1/me` | Cập nhật display_name / avatar_url / bio |
| PUT  | `/api/v1/me/push-token` | `{push_token, platform}` — lưu vào device hiện tại |
| GET  | `/api/v1/me/devices` | Danh sách thiết bị đăng nhập |
| DELETE | `/api/v1/me/devices/{deviceID}` | Đăng xuất một thiết bị |
| DELETE | `/api/v1/me/devices` | Đăng xuất tất cả thiết bị |
| GET  | `/api/v1/users/search?phone=...` | Tìm user |
| POST | `/api/v1/auth/logout` | Đăng xuất device hiện tại |
| GET  | `/api/v1/contacts` | Danh bạ |
| POST | `/api/v1/contacts/request` | `{user_id}` |
| POST | `/api/v1/contacts/accept` | `{user_id}` |

#### Conversation & message
| Method | Path | Mô tả |
|---|---|---|
| GET  | `/api/v1/conversations` | Danh sách hội thoại |
| POST | `/api/v1/conversations/direct` | `{peer_id}` (get-or-create) |
| POST | `/api/v1/conversations/group`  | `{title, member_ids}` |
| POST | `/api/v1/conversations/{id}/read` | Mark read |
| GET  | `/api/v1/conversations/{id}/messages?limit=30&before=RFC3339` | Lịch sử |
| POST | `/api/v1/conversations/{id}/messages` | `{type, body, media_url, reply_to_id}` |
| POST | `/api/v1/messages/{msgID}/recall` | Thu hồi (24h, người gửi) |

#### Feed (Nhật ký)
| Method | Path | Mô tả |
|---|---|---|
| GET  | `/api/v1/feed?limit=20&before=RFC3339` | Timeline (mình + bạn bè + public) |
| POST | `/api/v1/feed` | `{body, media: [url], visibility: public\|friends\|private}` |
| GET  | `/api/v1/feed/{id}` | Chi tiết post |
| POST | `/api/v1/feed/{id}/react` | `{reaction: "love"\|""}` (chuỗi rỗng = bỏ react) |
| GET  | `/api/v1/feed/{id}/comments` | Danh sách bình luận |
| POST | `/api/v1/feed/{id}/comments` | `{body}` |

#### Media
| Method | Path | Mô tả |
|---|---|---|
| POST | `/api/v1/upload` | multipart, field `file` — trả `{url, path, size, mime_type}` |

#### Realtime
| Method | Path | Mô tả |
|---|---|---|
| GET | `/api/v1/ws?token=<access_token>` | WebSocket: `message.new`, `message.recalled`, `read.receipt`, `presence.update`, `typing`, `pong` |

---

## WebSocket events (server → client)

| Type | Payload |
|---|---|
| `message.new` | `Message` object |
| `message.recalled` | `{id, conversation_id}` |
| `read.receipt` | `{conversation_id, user_id, read_at}` |
| `presence.update` | `{user_id, online}` |
| `typing` | `{conversation_id, user_id, device_id, is_typing}` |
| `pong` | `{}` (reply cho client `ping`) |

Client → server: `typing` `{conversation_id, is_typing}`, `ping`.

---

## Đối chiếu với PDF kiến trúc

| Khối PDF | Implementation hiện tại | Tách microservice |
|---|---|---|
| API Gateway | chi router + JWT middleware + CORS | Nginx/Envoy + Kong |
| Auth Service | `internal/auth` + Argon2id + refresh rotation + audit log | tách process, gRPC nội bộ |
| User Service | `internal/user` + push-token | tách process |
| Contact Service | `internal/contact` | tách process |
| Conversation Service | `internal/conversation` + mark-read broadcast | tách process |
| Message Gateway (WS) | `internal/ws` Hub + presence Redis | scale ngang qua Redis pub/sub |
| Message Service | `internal/message` (24h recall, soft delete) | shard theo `conversation_id` |
| Push Service | `PUT /me/push-token` (lưu DB) | worker consume NATS, gọi FCM/APNs |
| Media Service | `internal/media` (local disk + static) | swap qua S3/MinIO presigned URL |
| Social Feed | `internal/feed` + schema reaction/comment | tách process |
| Infra | Postgres + Redis + NATS (compose) | thêm Object Storage + CDN + Prometheus |

---

## Roadmap tiếp theo

- [x] Phase 1.1 slice: Argon2id cho password mới, refresh-token rotation/revoke, auth audit log, device management UI, rate limit auth, security headers.
- [ ] OTP SMS thật + reset password OTP (cần Twilio/eSMS/VN provider)
- [ ] Captcha thật cho auth khi vượt ngưỡng risk
- [ ] Push worker FCM/APNs thực (đọc topic NATS `message.new`, lọc `!hub.Online(uid)`)
- [ ] VoIP/video call (Agora/LiveKit) — bảng `calls` đã có
- [ ] Group admin: kick member, đổi avatar/title
- [ ] Mini app / Channel / Wallet (theo PDF Module mở rộng)
- [ ] Tách WebSocket Gateway: cluster qua Redis pub/sub
- [ ] Tests: integration với testcontainers-go + Flutter widget tests
- [ ] Upload progress + image preview trong chat composer

---

## Test nhanh bằng curl

```bash
# 1. Đăng ký 2 user
for name in Alice Bob; do
  curl -s -X POST http://localhost:8080/api/v1/auth/register \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"090$RANDOM\",\"password\":\"secret123\",\"display_name\":\"$name\"}"
done

# 2. Đăng nhập Alice
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"phone":"0900000001","password":"secret123","device_name":"curl","platform":"cli"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['access_token'])")

# 3. Upload ảnh
curl -X POST http://localhost:8080/api/v1/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F file=@/path/to/photo.jpg

# 4. Đăng feed
curl -X POST http://localhost:8080/api/v1/feed \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"body":"Hello Lumo!","visibility":"friends","media":["/static/..."]}'

# 5. Timeline
curl http://localhost:8080/api/v1/feed -H "Authorization: Bearer $TOKEN"
```

---

## Palette UI

| Token | Mã | Mục đích |
|---|---|---|
| Indigo 500 | `#6366F1` | Primary, bubble mine, link |
| Violet 500 | `#8B5CF6` | Gradient end, accent |
| Coral / Pink | `#F472B6` | FAB, unread badge, like icon |
| Mint | `#34D399` | Presence dot online |
| BgLight | `#FAF7FF` | Scaffold |
| TextPrimary | `#1E1B2E` | Body text |
| TextSecondary | `#6B6883` | Caption, hint |

Gradient chính: `Indigo → Violet`. Login backdrop: `Indigo → Violet → Coral`.
