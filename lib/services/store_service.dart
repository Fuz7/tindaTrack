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

/// The part of `stores/{id}` the Settings screen shows.
///
/// Equality compares only the editable fields — it is what tells the
/// Settings form whether it has unsaved changes.
class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.ownerName,
    required this.currency,
    this.lowStockThreshold = StoreDraft.defaultLowStockThreshold,
    this.ownerUid,
  });

  final String name;
  final String ownerName;

  /// ISO 4217 code, e.g. `PHP`.
  final String currency;

  /// Stock at or below this count is flagged as low — on Home, Inventory
  /// and Analytics alike. 1–100, as in the create flow.
  final int lowStockThreshold;

  /// Who created the store; anyone else signed in to it is a helper. Not
  /// editable, and null only on a store written without one.
  final String? ownerUid;

  @override
  bool operator ==(Object other) =>
      other is StoreProfile &&
      other.name == name &&
      other.ownerName == ownerName &&
      other.currency == currency &&
      other.lowStockThreshold == lowStockThreshold;

  @override
  int get hashCode => Object.hash(name, ownerName, currency, lowStockThreshold);
}

/// A helper allowed to work a store's till — one `storeMembers` document.
///
/// The owner adds a helper by email, since a helper's user id doesn't exist
/// to the owner until the helper signs in. [userId] is filled in when the
/// helper accepts on the Join a Tindahan screen.
class StaffMember {
  const StaffMember({required this.email, required this.name, this.userId});

  /// Lowercased, so it matches a Google account's email however it was typed.
  final String email;

  /// The name the helper's sales are recorded under.
  final String name;

  /// The helper's Firebase uid; null until they join.
  final String? userId;

  bool get hasJoined => userId != null;

  StaffMember copyWith({String? name}) =>
      StaffMember(email: email, name: name ?? this.name, userId: userId);

  @override
  bool operator ==(Object other) =>
      other is StaffMember &&
      other.email == email &&
      other.name == name &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(email, name, userId);
}

/// Whether the store is on Pro, and its helpers.
class StoreStaff {
  const StoreStaff({required this.isPro, required this.members});

  /// `stores/{id}.isPro`. Helpers are a Pro feature; there is no billing
  /// yet, so this is set by hand in the Firestore console.
  final bool isPro;
  final List<StaffMember> members;

  /// The helper signed in as [uid] / [email], if they are one.
  StaffMember? memberFor({required String uid, String? email}) {
    final key = email?.trim().toLowerCase();
    return members
        .where((m) => m.userId == uid || (key != null && m.email == key))
        .firstOrNull;
  }
}

/// A store that has authorized the signed-in user's email, as the Join a
/// Tindahan screen lists it.
class StoreInvite {
  const StoreInvite({
    required this.storeId,
    required this.storeName,
    required this.ownerName,
  });

  final String storeId;
  final String storeName;
  final String ownerName;
}

/// Reads which tindahan a user belongs to, creates one, and joins one as a
/// helper.
///
/// The pointer lives on the user document rather than in `SharedPreferences`
/// so the choice follows the owner across devices, which is the whole point of
/// the multi-device setup.
class StoreService {
  StoreService._();

  static const usersCollection = 'users';
  static const storesCollection = 'stores';
  static const activeStoreField = 'activeStoreId';

  /// Helpers, one document per store and email: `{storeId, email, name,
  /// userId}`. Top-level rather than under the store so a helper can find
  /// the stores that invited them with one query on their email.
  static const membersCollection = 'storeMembers';

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
        // Read the same way as [lowStockThresholdOf], so Settings shows
        // what the other tabs are using.
        lowStockThreshold: switch (data['lowStockThreshold']) {
          final num n => n.round(),
          _ => StoreDraft.defaultLowStockThreshold,
        },
        ownerUid: switch (data['ownerUid']) {
          final String uid when uid.isNotEmpty => uid,
          _ => null,
        },
      );
    });
  }

  /// Saves [profile] over the store's name, owner, currency and low-stock
  /// threshold.
  ///
  /// Firestore applies the write to its local cache at once, so [profileOf]
  /// and [lowStockThresholdOf] show it straight away — every tab's stock
  /// colors update without waiting; the returned future only completes when
  /// the server acknowledges, which offline may be much later.
  static Future<void> updateProfile(String storeId, StoreProfile profile) {
    return _db.collection(storesCollection).doc(storeId).update({
      'name': profile.name,
      'ownerName': profile.ownerName,
      'currency': profile.currency,
      'lowStockThreshold': profile.lowStockThreshold,
    });
  }

  /// Watches `stores/{id}.isPro` together with the store's `storeMembers`,
  /// emitting once both have arrived and on every change to either.
  static Stream<StoreStaff> staffOf(String storeId) {
    final pro = _db
        .collection(storesCollection)
        .doc(storeId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['isPro'] == true);
    final members = _db
        .collection(membersCollection)
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map(
          (query) => [
            for (final doc in query.docs)
              if (doc.data()['email'] case final String email)
                StaffMember(
                  email: email,
                  name: switch (doc.data()['name']) {
                    final String name => name,
                    _ => '',
                  },
                  userId: switch (doc.data()['userId']) {
                    final String uid when uid.isNotEmpty => uid,
                    _ => null,
                  },
                ),
          ]..sort((a, b) => a.email.compareTo(b.email)),
        );

    return Stream.multi((listener) {
      bool? isPro;
      List<StaffMember>? list;
      void emit() {
        if (isPro != null && list != null) {
          listener.add(StoreStaff(isPro: isPro!, members: list!));
        }
      }

      final subs = [
        pro.listen((value) {
          isPro = value;
          emit();
        }, onError: listener.addError),
        members.listen((value) {
          list = value;
          emit();
        }, onError: listener.addError),
      ];
      listener.onCancel = () => Future.wait([for (final s in subs) s.cancel()]);
    });
  }

  /// Turns Pro on for the store. There is no billing yet: confirming the
  /// upgrade is all it takes. Like [updateProfile], the local cache has it
  /// at once; the future waits on the server.
  static Future<void> upgradeToPro(String storeId) {
    return _db.collection(storesCollection).doc(storeId).update({
      'isPro': true,
      'proSince': FieldValue.serverTimestamp(),
    });
  }

  /// One document per store and helper email, so adding the same email twice
  /// overwrites rather than duplicates — and security rules can find a
  /// helper's invite by id.
  static String memberDocId(String storeId, String email) =>
      '${storeId}_${email.trim().toLowerCase()}';

  /// Authorizes [member]'s email on the store. Like [updateProfile], the
  /// local cache has it at once; the future waits on the server.
  static Future<void> addStaff(String storeId, StaffMember member) {
    final email = member.email.trim().toLowerCase();
    return _db
        .collection(membersCollection)
        .doc(memberDocId(storeId, email))
        .set({
          'storeId': storeId,
          'email': email,
          'name': member.name,
          'userId': member.userId,
          'addedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> renameStaff(String storeId, String email, String name) {
    return _db
        .collection(membersCollection)
        .doc(memberDocId(storeId, email))
        .update({'name': name});
  }

  static Future<void> removeStaff(String storeId, String email) {
    return _db
        .collection(membersCollection)
        .doc(memberDocId(storeId, email))
        .delete();
  }

  /// The Pro stores that have authorized [email], with their names looked
  /// up by store id. Reads the server: an invite list from a stale cache
  /// would offer stores that no longer want this helper.
  static Future<List<StoreInvite>> invitesFor(String email) async {
    final invites = await _db
        .collection(membersCollection)
        .where('email', isEqualTo: email.trim().toLowerCase())
        .get(const GetOptions(source: Source.server));

    final stores = await Future.wait([
      for (final invite in invites.docs)
        if (invite.data()['storeId'] case final String storeId)
          _db
              .collection(storesCollection)
              .doc(storeId)
              .get(const GetOptions(source: Source.server)),
    ]);

    return [
      for (final store in stores)
        if (store.data() case final data? when data['isPro'] == true)
          StoreInvite(
            storeId: store.id,
            storeName: switch (data['name']) {
              final String name => name,
              _ => 'Tindahan',
            },
            ownerName: switch (data['ownerName']) {
              final String name => name,
              _ => '',
            },
          ),
    ]..sort((a, b) => a.storeName.compareTo(b.storeName));
  }

  /// Joins [storeId] as a helper: writes the user's id onto their invite,
  /// and points `users/{uid}` at the store so [membershipOf] swaps to its
  /// dashboard. One batch, so neither half lands without the other.
  static Future<void> joinStore({
    required String uid,
    required String email,
    required String storeId,
  }) async {
    final batch = _db.batch()
      ..update(
        _db.collection(membersCollection).doc(memberDocId(storeId, email)),
        {'userId': uid, 'joinedAt': FieldValue.serverTimestamp()},
      )
      ..set(_db.collection(usersCollection).doc(uid), {
        activeStoreField: storeId,
      }, SetOptions(merge: true));
    await batch.commit();
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
        'isPro': false,
        'createdAt': FieldValue.serverTimestamp(),
      })
      // Merge so any other fields on the user document survive.
      ..set(userRef, {activeStoreField: storeRef.id}, SetOptions(merge: true));

    await batch.commit();
    return storeRef.id;
  }
}
