// lib/utils/version_utils.dart
class VersionUtils {
  /// Compares two version strings in format MM.mm.xx (e.g., "1.2.11")
  /// Returns:
  /// - negative if version1 < version2
  /// - zero if version1 == version2
  /// - positive if version1 > version2
  static int compareVersions(String version1, String version2) {
    final parts1 = version1
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final parts2 = version2
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    // Ensure both have the same number of parts (pad with zeros if needed)
    while (parts1.length < parts2.length) {
      parts1.add(0);
    }
    while (parts2.length < parts1.length) {
      parts2.add(0);
    }

    for (int i = 0; i < parts1.length; i++) {
      if (parts1[i] < parts2[i]) return -1;
      if (parts1[i] > parts2[i]) return 1;
    }
    return 0;
  }

  /// Checks if currentVersion is less than requiredVersion
  static bool isVersionLessThan(String currentVersion, String requiredVersion) {
    return compareVersions(currentVersion, requiredVersion) < 0;
  }

  /// Extracts the marketing version from a version string like "1.2.11+49"
  /// Returns "1.2.11"
  static String extractMarketingVersion(String fullVersion) {
    return fullVersion.split('+').first;
  }
}
