import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true khi `Firebase.initializeApp()` thành công (có google-services.json đúng package). Override trong main().
/// false → tính năng cần tài khoản/đám mây ẩn đi, app vẫn chạy offline với dữ liệu cục bộ.
final firebaseReadyProvider = Provider<bool>((ref) => false);

/// Chỉ đọc khi [firebaseReadyProvider] là true. Override trong test bằng bản fake.
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// uid hiện tại hoặc null (khách / chưa đăng nhập / Firebase chưa sẵn sàng).
final currentUidProvider = Provider<String?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return ref.watch(firebaseAuthProvider).currentUser?.uid;
});
