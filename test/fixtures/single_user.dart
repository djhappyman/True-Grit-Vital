import 'package:true_grit_vital/data/record_store.dart';

extension SingleUserFixture on RecordStore {
  Future<AdultProfile> configureOwnProfile({
    required String commandId,
    required String name,
    required bool adultConfirmed,
    String? reportName,
    String? relationship,
    String? notes,
  }) async => editProfile(
    commandId: commandId,
    personId: meId,
    expectedRevision: (await profileById(meId))!.revision,
    name: name,
    adultConfirmed: adultConfirmed,
    reportName: reportName,
    notes: notes,
  );
}
