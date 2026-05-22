/// How the app operates: playing its own files or acting as a passive
/// visualiser / control surface for an external player.
enum OperatingMode {
  own('Own'),
  background('Background');

  final String label;
  const OperatingMode(this.label);

  String get storageKey => name;

  static OperatingMode fromStorageKey(String? key) {
    return OperatingMode.values.firstWhere(
      (m) => m.name == key,
      orElse: () => OperatingMode.own,
    );
  }
}
