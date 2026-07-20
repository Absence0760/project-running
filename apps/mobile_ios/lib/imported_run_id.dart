import 'package:uuid/uuid.dart';

/// Fixed UUID namespace for deriving an imported run's local `id` from its
/// stable `external_id`.
///
/// A re-import of an activity that already carries an `external_id` MUST map
/// to the same local id. `LocalRunStore.save` dedupes only by `id`, so a fresh
/// random id per import saved a re-import as a NEW local run (double-counting
/// locally) and then pushed the new id into the `(user_id, external_id)`
/// upsert — Postgres ran `UPDATE runs SET id = <new> WHERE (user_id,
/// external_id) = …`, rewriting the server row's primary key: orphaning the
/// original row, or throwing an uncaught FK violation that aborts the whole
/// batch and permanently wedges the sync queue (#361). Deriving the id
/// deterministically from `external_id` closes both: the local dedupe finds
/// the prior copy, and the upsert leaves the primary key untouched.
const _importedRunIdNamespace = '7b9c4d1e-2f3a-4b5c-8d6e-9f0a1b2c3d4e';

/// Deterministic v5 UUID from a run's stable `external_id`. Two imports of the
/// same activity produce identical ids, so both the local id-dedupe and the
/// server `(user_id, external_id)` upsert stay idempotent.
String stableRunIdFromExternalId(String externalId) =>
    const Uuid().v5(_importedRunIdNamespace, externalId);
