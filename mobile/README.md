# Zalo-clone Mobile (Flutter)

Đây là package Flutter. Trước khi `flutter run`, cần khởi tạo các thư mục
platform (iOS/Android/Web/Desktop) — file này chưa được commit để giữ scaffold gọn.

## Khởi tạo platform folders

```bash
cd mobile
flutter create --org com.zaloclone --project-name zalo_clone \
  --platforms=ios,android,web,macos,linux,windows .
```

Lệnh `flutter create .` sẽ giữ nguyên `lib/`, `pubspec.yaml` hiện tại và chỉ
thêm `ios/`, `android/`, `web/`, ... cần thiết.

## Cài deps & chạy

```bash
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8080
```

Trên Android emulator dùng `http://10.0.2.2:8080` (host của máy bạn).

## Cấu trúc lib/

```
lib/
├── main.dart                  # entry, dựng Provider tree
├── config.dart                # API_BASE / WS_BASE
├── models/                    # AppUser, Conversation, Message
├── services/
│   ├── api_client.dart        # REST client (JSON envelope)
│   └── ws_client.dart         # WebSocket client (auto-reconnect)
├── providers/
│   └── auth_provider.dart     # đăng nhập + bootstrap session từ SharedPreferences
└── screens/
    ├── login_screen.dart
    ├── conversations_screen.dart
    └── chat_screen.dart
```
