import 'dart:convert';

enum SyncOpType { upsert, delete }

enum SyncOpState { pending, sending, acked, error }

/// Một thao tác trong outbox (H03). Mỗi thao tác có idempotencyKey ổn định khi retry.
class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.ownerId,
    required this.entity,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.idempotencyKey,
    this.state = SyncOpState.pending,
    this.attempts = 0,
    this.nextAttemptAt = 0,
    this.lastError,
    required this.createdAt,
  });

  final String id;
  final String ownerId;

  /// activity | goal | settings | attachment | track
  final String entity;
  final String entityId;
  final SyncOpType op;
  final Map<String, Object?> payload;
  final String idempotencyKey;
  final SyncOpState state;
  final int attempts;
  final int nextAttemptAt;
  final String? lastError;
  final int createdAt;

  SyncOperation copyWith({SyncOpState? state, int? attempts, int? nextAttemptAt, String? lastError}) => SyncOperation(
    id: id,
    ownerId: ownerId,
    entity: entity,
    entityId: entityId,
    op: op,
    payload: payload,
    idempotencyKey: idempotencyKey,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'owner_id': ownerId,
    'entity': entity,
    'entity_id': entityId,
    'op': op.name,
    'payload_json': jsonEncode(payload),
    'idempotency_key': idempotencyKey,
    'state': state.name,
    'attempts': attempts,
    'next_attempt_at': nextAttemptAt,
    'last_error': lastError,
    'created_at': createdAt,
  };

  factory SyncOperation.fromRow(Map<String, Object?> r) => SyncOperation(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    entity: r['entity'] as String,
    entityId: r['entity_id'] as String,
    op: SyncOpType.values.firstWhere((e) => e.name == r['op'], orElse: () => SyncOpType.upsert),
    payload: (jsonDecode(r['payload_json'] as String) as Map).cast<String, Object?>(),
    idempotencyKey: r['idempotency_key'] as String,
    state: SyncOpState.values.firstWhere((e) => e.name == r['state'], orElse: () => SyncOpState.pending),
    attempts: r['attempts'] as int? ?? 0,
    nextAttemptAt: r['next_attempt_at'] as int? ?? 0,
    lastError: r['last_error'] as String?,
    createdAt: r['created_at'] as int,
  );

  /// Backoff mũ có trần 30 phút.
  static int backoffMs(int attempts) {
    final base = 2000 * (1 << attempts.clamp(0, 10));
    return base > 30 * 60 * 1000 ? 30 * 60 * 1000 : base;
  }
}
