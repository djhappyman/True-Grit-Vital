/// Honest availability of routes owned by dependent work packages.
///
/// A null path means the capability is not present in this build, so Settings
/// renders no row and no enabled-looking dead control. The lead wires real
/// routes after integrating the owning work package and overrides the provider.
final class SettingsCapabilities {
  const SettingsCapabilities({
    this.reportsPath,
    this.exportsPath,
    this.backupPath,
    this.restorePath,
  });

  const SettingsCapabilities.none() : this();

  final String? reportsPath;
  final String? exportsPath;
  final String? backupPath;
  final String? restorePath;

  bool get hasReports => _isRoute(reportsPath);
  bool get hasExports => _isRoute(exportsPath);
  bool get hasBackup => _isRoute(backupPath);
  bool get hasRestore => _isRoute(restorePath);
  bool get hasDataSection =>
      hasReports || hasExports || hasBackup || hasRestore;

  SettingsCapabilities copyWith({
    String? reportsPath,
    String? exportsPath,
    String? backupPath,
    String? restorePath,
  }) => SettingsCapabilities(
    reportsPath: reportsPath ?? this.reportsPath,
    exportsPath: exportsPath ?? this.exportsPath,
    backupPath: backupPath ?? this.backupPath,
    restorePath: restorePath ?? this.restorePath,
  );

  /// Only an in-app absolute route is accepted; a blank or external value is
  /// treated as unavailable rather than becoming a broken or unsafe link.
  static bool _isRoute(String? path) =>
      path != null && path.startsWith('/') && !path.startsWith('//');
}
