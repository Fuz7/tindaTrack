import 'package:cloud_firestore/cloud_firestore.dart';

/// Which tindahan (if any) the signed-in user is currently working in.
///
/// [unknown] is not "no store" — it means the answer is still in flight. The
/// distinction matters because Firestore answers a `snapshots()` listen from
/// its offline cache first: on a fresh install that cached answer is "no such
/// document", which is indistinguishable from a genuinely store-less user.
/// Treating it as [none] would drop a returning owner onto the onboarding
/// screen and invite them to create a second store.
enum StoreMembershipStatus { unknown, none, joined }

/// The user's current store membership, as resolved by [StoreService].
class StoreMembership {
  const StoreMembership._(this.status, this.storeId);

  const StoreMembership.unknown() : this._(StoreMembershipStatus.unknown, null);
  const StoreMembership.none() : this._(StoreMembershipStatus.none, null);
  const StoreMembership.joined(String storeId)
    : this._(StoreMembershipStatus.joined, storeId);

  final StoreMembershipStatus status;

  /// The active tindahan's document id. Non-null exactly when [status] is
  /// [StoreMembershipStatus.joined].
  final String? storeId;

  bool get isResolved => status != StoreMembershipStatus.unknown;
  bool get hasStore => status == StoreMembershipStatus.joined;

  @override
  String toString() => 'StoreMembership(${status.name}, $storeId)';
}

/// Reads which tindahan a user belongs to. Read-only for now — creating and
/// joining stores belongs to the Create/Join screens, which do not exist yet.
///
/// The pointer lives on the user document rather than in `SharedPreferences`
/// so the choice follows the owner across devices, which is the whole point of
/// the multi-device setup.
class StoreService {
  StoreService._();

  static const usersCollection = 'users';
  static const activeStoreField = 'activeStoreId';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Watches `users/{uid}.activeStoreId`.
  ///
  /// Emits [StoreMembershipStatus.unknown] only while a cache-only miss is
  /// outstanding; every other case resolves to [none] or [joined]. A document
  /// that exists but carries no usable id counts as [none] — a half-written
  /// user record should send the owner back through onboarding, not strand
  /// them pointing at a store that isn't there.
  ///
  /// `includeMetadataChanges` is load-bearing: when the server confirms the
  /// document is missing, only `isFromCache` flips — the data is unchanged, so
  /// without it Firestore never emits again and the gate stays [unknown]
  /// forever.
  static Stream<StoreMembership> membershipOf(String uid) {
    return _db
        .collection(usersCollection)
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (!snapshot.exists) {
            return snapshot.metadata.isFromCache
                ? const StoreMembership.unknown()
                : const StoreMembership.none();
          }

          // Firestore hands back `dynamic`; anything that isn't a non-empty
          // string is not a document id, whatever it claims to be.
          final raw = snapshot.data()?[activeStoreField];
          if (raw is! String || raw.isEmpty) {
            return const StoreMembership.none();
          }

          return StoreMembership.joined(raw);
        });
  }
}
