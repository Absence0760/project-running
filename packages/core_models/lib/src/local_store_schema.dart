/// On-disk schema versioning for the mobile file stores
/// (`LocalRunStore`, `LocalRouteStore`, `LocalGearStore`, `LocalGymStore`,
/// `LocalFoodStore`).
///
/// Every record (and sidecar) a store persists is stamped with
/// [kLocalStoreVersionKey] = [kLocalStoreSchemaVersion]. On read, a store
/// resolves the stored version via [localStoreRecordVersion] and routes
/// through its own forward-migration branch — so when a record's JSON shape
/// changes incompatibly we bump [kLocalStoreSchemaVersion], add an upgrade
/// branch keyed on the version we read back, and old files migrate forward
/// transparently instead of being silently dropped by a stricter parser.
///
/// A record with no `_v` key predates versioning and is treated as version
/// [kLocalStoreLegacyVersion] (0).
library;

/// Current on-disk schema version. Bump on an incompatible record-shape
/// change and add the matching read-side migration branch in each affected
/// store.
const int kLocalStoreSchemaVersion = 1;

/// JSON key the schema version is stamped under. Underscore-prefixed so it
/// never collides with a domain field.
const String kLocalStoreVersionKey = '_v';

/// Version assigned to a record written before versioning shipped (no `_v`).
const int kLocalStoreLegacyVersion = 0;

/// The schema version stamped into [json], or [kLocalStoreLegacyVersion]
/// when the key is absent (a pre-versioning record).
int localStoreRecordVersion(Map<String, dynamic> json) {
  final raw = json[kLocalStoreVersionKey];
  return raw is num ? raw.toInt() : kLocalStoreLegacyVersion;
}
