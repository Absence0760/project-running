import 'generated/db_rows.dart';

/// A gear rotation paired with the ids of the gear it contains. The
/// membership ids ride alongside the rotation so a settings UI can group
/// the gear list and pre-check the assignment toggles without a per-row
/// round trip. Mirrors the web's `GearRotationWithMembers`.
class GearRotationWithMembers {
  const GearRotationWithMembers({
    required this.rotation,
    required this.gearIds,
  });

  final GearRotationRow rotation;
  final List<String> gearIds;

  String get id => rotation.id;
  String get name => rotation.name;
}
