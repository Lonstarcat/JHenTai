import 'dart:convert';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/service/log.dart';

import '../service/jh_service.dart';
import '../utils/serial_config_writer.dart';

UserSetting userSetting = UserSetting();

class UserSetting
    with JHLifeCircleBeanWithConfigStorage
    implements JHLifeCircleBean {
  final Future<int> Function(String)? writeConfig;
  final Future<bool> Function()? deleteConfig;
  final SerialConfigWriter _writer = SerialConfigWriter();
  UserSetting({this.writeConfig, this.deleteConfig});

  int profileGeneration = 0;
  bool avatarLookupAttempted = false;
  final RxBool avatarNeedsVerification = false.obs;
  int? avatarOwnerMemberId;
  final Rxn<Uint8List> avatarBytes = Rxn<Uint8List>();
  RxnString userName = RxnString();
  RxnInt ipbMemberId = RxnInt();
  RxnString ipbPassHash = RxnString();
  RxnString avatarImgUrl = RxnString();
  RxnString nickName = RxnString();
  RxnInt defaultFavoriteIndex = RxnInt();
  RxnInt defaultTagSetNo = RxnInt();

  bool hasLoggedIn() => ipbMemberId.value != null;

  @override
  ConfigEnum get configEnum => ConfigEnum.userSetting;

  @override
  void applyBeanConfig(String configString) {
    Map map = jsonDecode(configString);

    profileGeneration++;
    userName.value = map['userName'];
    ipbMemberId.value = map['ipbMemberId'];
    ipbPassHash.value = map['ipbPassHash'];
    avatarImgUrl.value = map['avatarImgUrl'];
    nickName.value = map['nickName'];
    defaultFavoriteIndex.value = map['defaultFavoriteIndex'];
    defaultTagSetNo.value = map['defaultTagSetNo'];
    avatarLookupAttempted = map['avatarLookupAttempted'] == true;
    avatarNeedsVerification.value = map['avatarNeedsVerification'] == true;
    avatarOwnerMemberId = map['avatarOwnerMemberId'];
    avatarBytes.value = null;
    final encoded = map['avatarBytes'];
    if (hasLoggedIn() &&
        avatarOwnerMemberId == ipbMemberId.value &&
        encoded is String &&
        encoded.length <= 1400000) {
      try {
        avatarBytes.value = base64Decode(encoded);
      } on FormatException {
        // A damaged optional cache must not prevent loading the account.
      }
    }
  }

  @override
  String toConfigString() {
    return jsonEncode({
      'userName': userName.value,
      'ipbMemberId': ipbMemberId.value,
      'ipbPassHash': ipbPassHash.value,
      'avatarImgUrl': avatarImgUrl.value,
      'avatarOwnerMemberId': avatarOwnerMemberId,
      'avatarLookupAttempted': avatarLookupAttempted,
      'avatarNeedsVerification': avatarNeedsVerification.value,
      'avatarBytes':
          avatarBytes.value == null ? null : base64Encode(avatarBytes.value!),
      'nickName': nickName.value,
      'defaultFavoriteIndex': defaultFavoriteIndex.value,
      'defaultTagSetNo': defaultTagSetNo.value,
    });
  }

  @override
  Future<void> doInitBean() async {}

  @override
  void doAfterBeanReady() {}

  Future<void> saveUserInfo({
    required String userName,
    required int ipbMemberId,
    required String ipbPassHash,
    String? avatarImgUrl,
    String? nickName,
  }) async {
    log.debug('Save authenticated user session');
    invalidateProfileSession();
    avatarLookupAttempted = false;
    this.userName.value = userName;
    this.ipbPassHash.value = ipbPassHash;
    this.ipbMemberId.value = ipbMemberId;
    this.avatarImgUrl.value = avatarImgUrl;
    this.nickName.value = nickName;
    await saveBeanConfig();
  }

  Future<void> saveForumProfile({
    required int memberId,
    required int generation,
    required String userName,
    String? avatarImgUrl,
    required String nickName,
    Uint8List? bytes,
    bool needsVerification = false,
  }) async {
    if (!ownsProfileSession(memberId, generation)) {
      return;
    }
    this.userName.value = userName;
    this.avatarImgUrl.value = avatarImgUrl ?? this.avatarImgUrl.value;
    this.nickName.value = nickName;
    // Never erase a valid same-session bitmap because an optional refresh failed.
    avatarBytes.value =
        bytes ?? (avatarOwnerMemberId == memberId ? avatarBytes.value : null);
    avatarOwnerMemberId = memberId;
    avatarNeedsVerification.value = needsVerification;
    await saveBeanConfig();
  }

  bool ownsProfileSession(int memberId, int generation) =>
      hasLoggedIn() &&
      ipbMemberId.value == memberId &&
      profileGeneration == generation;

  void invalidateProfileSession() {
    profileGeneration++;
    avatarOwnerMemberId = null;
    avatarNeedsVerification.value = false;
    avatarImgUrl.value = null;
    avatarBytes.value = null;
  }

  @override
  Future<int> saveBeanConfig() => _writer
      .run(() => writeConfig?.call(toConfigString()) ?? super.saveBeanConfig());

  Future<void> saveDefaultFavoriteIndex(int? index) async {
    log.debug('saveDefaultFavoriteIndex: $index');
    this.defaultFavoriteIndex.value = index;
    await saveBeanConfig();
  }

  Future<void> saveDefaultTagSetNo(int? number) async {
    log.debug('saveDefaultTagSet: $number');
    this.defaultTagSetNo.value = number;
    await saveBeanConfig();
  }

  @override
  Future<bool> clearBeanConfig() async {
    // Invalidate synchronously, before waiting for any in-flight persistence.
    invalidateProfileSession();
    avatarLookupAttempted = false;
    userName.value = null;
    ipbMemberId.value = null;
    ipbPassHash.value = null;
    avatarImgUrl.value = null;
    nickName.value = null;
    defaultFavoriteIndex.value = null;
    defaultTagSetNo.value = null;
    return _writer.run(() => deleteConfig?.call() ?? super.clearBeanConfig());
  }
}
