class AppConstants {
  AppConstants._();

  static const String appName = 'DevSync';
  static const String appVersion = '1.0.0';

  // Network Ports
  static const int defaultLanPort = 42042;
  static const int defaultDiscoveryPort = 42043;

  // Storage Folders
  static const String rootFolder = 'DevSync';
  static const String codeFolder = 'Code';
  static const String documentsFolder = 'Documents';
  static const String imagesFolder = 'Images';
  static const String mediaFolder = 'Media';
  static const String archivesFolder = 'Archives';

  // Default Backend Relay (Can be overridden in app settings)
  static const String defaultRelayUrl = 'https://devsync-relay.vercel.app';

  // Hive Box Names
  static const String boxSettings = 'devsync_settings';
  static const String boxPeers = 'devsync_peers';
  static const String boxMessages = 'devsync_messages';
  static const String boxTransfers = 'devsync_transfers';
}
