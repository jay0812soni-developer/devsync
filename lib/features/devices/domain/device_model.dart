class DeviceModel {
  final String id;
  final String name;
  final String platform;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String? lanIp;
  final int? lanPort;
  final bool isOnline;
  final bool isLanAvailable;
  final DateTime lastSeen;
  final bool isPaired;

  DeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    this.lanIp,
    this.lanPort,
    this.isOnline = false,
    this.isLanAvailable = false,
    required this.lastSeen,
    this.isPaired = false,
  });

  DeviceModel copyWith({
    String? name,
    String? platform,
    String? signingPublicKey,
    String? exchangePublicKey,
    String? lanIp,
    int? lanPort,
    bool? isOnline,
    bool? isLanAvailable,
    DateTime? lastSeen,
    bool? isPaired,
  }) {
    return DeviceModel(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      exchangePublicKey: exchangePublicKey ?? this.exchangePublicKey,
      lanIp: lanIp ?? this.lanIp,
      lanPort: lanPort ?? this.lanPort,
      isOnline: isOnline ?? this.isOnline,
      isLanAvailable: isLanAvailable ?? this.isLanAvailable,
      lastSeen: lastSeen ?? this.lastSeen,
      isPaired: isPaired ?? this.isPaired,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'signingPublicKey': signingPublicKey,
        'exchangePublicKey': exchangePublicKey,
        'lanIp': lanIp,
        'lanPort': lanPort,
        'isOnline': isOnline,
        'isLanAvailable': isLanAvailable,
        'lastSeen': lastSeen.toIso8601String(),
        'isPaired': isPaired,
      };

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Device',
      platform: json['platform'] as String? ?? 'unknown',
      signingPublicKey: json['signingPublicKey'] as String? ?? '',
      exchangePublicKey: json['exchangePublicKey'] as String? ?? '',
      lanIp: json['lanIp'] as String?,
      lanPort: json['lanPort'] as int?,
      isOnline: json['isOnline'] as bool? ?? false,
      isLanAvailable: json['isLanAvailable'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String) ?? DateTime.now()
          : DateTime.now(),
      isPaired: json['isPaired'] as bool? ?? false,
    );
  }
}
