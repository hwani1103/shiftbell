import 'package:cloud_firestore/cloud_firestore.dart';

/// A frozen local intent. Revisions distinguish A -> B -> A as well as retries.
class FriendShareWrite {
  const FriendShareWrite({
    required this.session,
    required this.revision,
    required this.generation,
    required this.stop,
    required this.explicitStart,
    this.payload,
  });

  final String session;
  final int revision;
  final int generation;
  final bool stop;
  final bool explicitStart;
  final Map<String, dynamic>? payload;
}

class FriendShareSuperseded implements Exception {}

/// Pure transition calculation; Firestore runs it against a transactional read.
/// Null means this exact operation has already committed.
Map<String, dynamic>? planFriendShareWrite(
  Map<String, dynamic>? current,
  FriendShareWrite operation,
) {
  final v2 = current?['protocolVersion'] == 2;
  final oldGeneration =
      current?['generation'] is int ? current!['generation'] as int : 0;
  final sameSession = v2 && current!['session'] == operation.session;
  final oldRevision = v2 ? current!['revision'] as int : 0;

  if (sameSession && operation.revision < oldRevision) {
    throw FriendShareSuperseded();
  }
  if (!operation.stop && sameSession && current['revoked'] == true) {
    throw FriendShareSuperseded();
  }
  if (!operation.stop &&
      !sameSession &&
      (v2 || current?['revoked'] == true) &&
      !operation.explicitStart) {
    // Lost local state must never silently resume a revoked/newer session.
    throw FriendShareSuperseded();
  }
  if (sameSession &&
      operation.revision == oldRevision &&
      current['revoked'] == operation.stop) {
    return null;
  }

  final generation = sameSession
      ? oldGeneration
      : (oldGeneration >= operation.generation
          ? oldGeneration + 1
          : operation.generation);
  return <String, dynamic>{
    if (!operation.stop) ...operation.payload!,
    'protocolVersion': 2,
    'session': operation.session,
    'generation': generation < 1 ? 1 : generation,
    'revision': operation.revision,
    'revoked': operation.stop,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

abstract class FriendShareTransport {
  Future<void> write(String ownerId, FriendShareWrite operation,
      Future<bool> Function() isCurrent);
}

class FirestoreFriendShareTransport implements FriendShareTransport {
  @override
  Future<void> write(String ownerId, FriendShareWrite operation,
      Future<bool> Function() isCurrent) {
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('friend_schedules').doc(ownerId);
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      // Transactions can retry after a newer local intent has been saved.
      if (!await isCurrent()) throw FriendShareSuperseded();
      final next = planFriendShareWrite(snapshot.data(), operation);
      if (next != null) transaction.set(ref, next);
    });
  }
}
