# Test firestore.rules (FB03)

Mỗi collection trong `docs/firestore-schema.md` có ca **được phép** và **bị chặn**, chạy trên Firestore Emulator.

```bash
cd firestore-tests
npm install
npm run test:emulator     # khởi động emulator, chạy test, dừng emulator
```

- Cần Java 11+ (firebase-tools 13 ghim trong `devDependencies`; firebase-tools 14+ đòi Java 21).
- Test gọi **REST API** của emulator (token giả không ký, như `@firebase/rules-unit-testing`) thay cho SDK web: SDK dùng gRPC/HTTP2
  và bị treo trên máy có phần mềm bảo mật chặn HTTP/2 tới localhost.
- Đã có emulator chạy sẵn (`firebase emulators:start --only firestore --project demo-stride`)? Chạy thẳng `npm test`.
- Windows: `emulators:exec` đôi khi để lại tiến trình `java` giữ cổng 8080 — dừng nó trước lần chạy sau.
- Sửa `firestore.rules` → thêm ca test tương ứng (TM70 yêu cầu mỗi quyền mới có test).
