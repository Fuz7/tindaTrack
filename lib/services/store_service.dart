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

/// Everything the "Create New Tindahan" flow collects before anything is
/// written. Optional fields are null rather than empty so the stored document
/// doesn't carry blank strings that every reader then has to second-guess.
class StoreDraft {
  const StoreDraft({
    required this.name,
    required this.ownerName,
    this.phone,
    this.currency = 'PHP',
    this.address,
    this.lowStockThreshold = defaultLowStockThreshold,
  });

  final String name;
  final String ownerName;
  final String? phone;

  /// ISO 4217 code, e.g. `PHP`.
  final String currency;
  final String? address;

  static const defaultLowStockThreshold = 5;

  /// Stock at or below this count is flagged as low.
  final int lowStockThreshold;

  /// The currencies a store can pick, ISO code to display label.
  static const currencies = {
    'PHP': '₱ PHP (Philippine Peso)',
    'USD': r'$ USD (US Dollar)',
  };
}

/// The part of `stores/{id}` the Settings screen edits.
class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.ownerName,
    required this.currency,
  });

  final String name;
  final String ownerName;

  /// ISO 4217 code, e.g. `PHP`.
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is StoreProfile &&
      other.name == name &&
      other.ownerName == ownerName &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(name, ownerName, currency);
}

/// A helper allowed to work the store's till, and the name their sales are
/// recorded under.
class StaffMember {
  const StaffMember({required this.email, required this.name});

  /// Lowercased, so it matches a Google account's email however it was typed.
  final String email;
  final String name;

  StaffMember copyWith({String? name}) =>
      StaffMember(email: email, name: name ?? this.name);

  Map<String, dynamic> toMap() => {'email': email, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is StaffMember && other.email == email && other.name == name;

  @override
  int get hashCode => Object.hash(email, name);
}

/// The store's plan and its allowed-emails list.
class StoreStaff {
  const StoreStaff({required this.isPro, required this.members});

  /// Staff accounts are a Pro feature. There is no billing yet, so this is
  /// `stores/{id}.plan == 'pro'`, set by hand in the Firestore console.
  final bool isPro;
  final List<StaffMember> members;

  /// The helper signed in as [email], if they are one.
  StaffMember? memberFor(String? email) {
    if (email == null) return null;
    final key = email.trim().toLowerCase();
    return members.where((m) => m.email == key).firstOrNull;
  }
}

/// Reads which tindahan a user belongs to, and creates one. Joining an
/// existing store belongs to the Join flow, which does not exist yet.
///
/// The pointer lives on the user document rather than in `SharedPreferences`
/// so the choice follows the owner across devices, which is the whole point of
/// the multi-device setup.
class StoreService {
  StoreService._();

  static const usersCollection = 'users';
  static const storesCollection = 'stores';
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

  /// Watches the store's `lowStockThreshold`, falling back to the create
  /// flow's default of 5 while it loads or if the field is missing.
  static Stream<int> lowStockThresholdOf(String storeId) {
    return _db.collection(storesCollection).doc(storeId).snapshots().map((
      snapshot,
    ) {
      final raw = snapshot.data()?['lowStockThreshold'];
      return raw is num ? raw.round() : StoreDraft.defaultLowStockThreshold;
    });
  }

  /// Watches the store's editable profile. Emits null while the document
  /// hasn't arrived; missing fields read as blank, and currency as `PHP`.
  static Stream<StoreProfile?> profileOf(String storeId) {
    return _db.collection(storesCollection).doc(storeId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) return null;
      String text(String key) {
        final raw = data[key];
        return raw is String ? raw : '';
      }

      final currency = text('currency');
      return StoreProfile(
        name: text('name'),
        ownerName: text('ownerName'),
        currency: currency.isEmpty ? 'PHP' : currency,
      );
    });
  }

  /// Saves [profile] over the store's name, owner and currency.
  ///
  /// Firestore applies the write to its local cache at once, so [profileOf]
  /// shows it straight away; the returned future only completes when the
  /// server acknowledges, which offline may be much later.
  static Future<void> updateProfile(String storeId, StoreProfile profile) {
    return _db.collection(storesCollection).doc(storeId).update({
      'name': profile.name,
      'ownerName': profile.ownerName,
      'currency': profile.currency,
    });
  }

  /// Watches the store's plan and allowed-emails list (`staff`, an array of
  /// `{email, name}` maps). Entries without an email are skipped.
  static Stream<StoreStaff> staffOf(String storeId) {
    return _db.collection(storesCollection).doc(storeId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final raw = data['staff'];
      return StoreStaff(
        isPro: data['plan'] == 'pro',
        members: [
          if (raw is List)
            for (final entry in raw)
              if (entry is Map && entry['email'] is String)
                StaffMember(
                  email: (entry['email'] as String).trim().toLowerCase(),
                  name: entry['name'] is String ? entry['name'] as String : '',
                ),
        ],
      );
    });
  }

  /// Replaces the store's allowed-emails list. Like [updateProfile], the
  /// local cache has it at once; the future waits on the server.
  static Future<void> updateStaff(String storeId, List<StaffMember> staff) {
    return _db.collection(storesCollection).doc(storeId).update({
      'staff': [for (final member in staff) member.toMap()],
    });
  }

  /// Creates `stores/{id}` from [draft] and points `users/{uid}` at it, as one
  /// batch — a store nobody points at, or a pointer to a store that was never
  /// written, are both states [membershipOf] would have to paper over.
  ///
  /// The UI need not be told about the new store: the local write lands on
  /// [membershipOf]'s listener immediately and the store gate swaps itself to
  /// the dashboard. The returned future completes when the server acknowledges,
  /// and throws if it refuses (e.g. security rules).
  static Future<String> createStore(String uid, StoreDraft draft) async {
    final storeRef = _db.collection(storesCollection).doc();
    final userRef = _db.collection(usersCollection).doc(uid);

    final batch = _db.batch()
      ..set(storeRef, {
        'name': draft.name,
        'ownerName': draft.ownerName,
        'phone': draft.phone,
        'currency': draft.currency,
        'address': draft.address,
        'lowStockThreshold': draft.lowStockThreshold,
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      })
      // Merge so any other fields on the user document survive.
      ..set(userRef, {activeStoreField: storeRef.id}, SetOptions(merge: true));

    await batch.commit();
    return storeRef.id;
  }
}
