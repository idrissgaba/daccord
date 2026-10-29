/// A keybind the user recorded on the Keybinds settings page: an action and
/// the chord that triggers it. Stored client-side with the other settings.
class CustomKeybind {
  const CustomKeybind({
    required this.action,
    this.keyId = 0,
    this.physicalKey = 0,
    this.keyLabel = '',
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  /// `HomeShortcut.name` of the action.
  final String action;

  /// `LogicalKeyboardKey.keyId` of the main key; 0 while nothing is recorded.
  final int keyId;

  /// `PhysicalKeyboardKey.usbHidUsage` of the main key, matched as a fallback:
  /// with Ctrl held some platforms report a different logical key than the
  /// one recorded, the physical key never changes.
  final int physicalKey;

  /// How the main key is shown (its label on the layout used to record it).
  final String keyLabel;

  /// Ctrl on Windows/Linux, ⌘ on macOS.
  final bool control;
  final bool shift;
  final bool alt;

  bool get isRecorded => keyId != 0;

  CustomKeybind copyWith({
    String? action,
    int? keyId,
    int? physicalKey,
    String? keyLabel,
    bool? control,
    bool? shift,
    bool? alt,
  }) => CustomKeybind(
    action: action ?? this.action,
    keyId: keyId ?? this.keyId,
    physicalKey: physicalKey ?? this.physicalKey,
    keyLabel: keyLabel ?? this.keyLabel,
    control: control ?? this.control,
    shift: shift ?? this.shift,
    alt: alt ?? this.alt,
  );

  Map<String, dynamic> toJson() => {
    'action': action,
    'keyId': keyId,
    'physicalKey': physicalKey,
    'keyLabel': keyLabel,
    'control': control,
    'shift': shift,
    'alt': alt,
  };

  static CustomKeybind fromJson(Map<dynamic, dynamic> json) => CustomKeybind(
    action: json['action']?.toString() ?? '',
    keyId: (json['keyId'] as num?)?.toInt() ?? 0,
    physicalKey: (json['physicalKey'] as num?)?.toInt() ?? 0,
    keyLabel: json['keyLabel']?.toString() ?? '',
    control: json['control'] == true,
    shift: json['shift'] == true,
    alt: json['alt'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomKeybind &&
      other.action == action &&
      other.keyId == keyId &&
      other.physicalKey == physicalKey &&
      other.keyLabel == keyLabel &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode =>
      Object.hash(action, keyId, physicalKey, keyLabel, control, shift, alt);
}
