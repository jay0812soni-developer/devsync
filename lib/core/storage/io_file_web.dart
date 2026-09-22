class IoFile {
  static Future<bool> exists(String path) async => false;
  static Future<int> length(String path) async => 0;
  static Future<String> checksum(String path) async => '';
  static Future<void> writeBytes(String path, List<int> bytes) async {}
  static Future<void> ensureDir(String path) async {}
  static Future<int> treeSize(String path) async => 0;
  static Future<String?> downloadsPath() async => null;
  static Future<String?> documentsPath() async => null;
}
