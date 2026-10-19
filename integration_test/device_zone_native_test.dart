import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android supplies an admitted native IANA zone', (tester) async {
    await tester.pumpWidget(const SizedBox());
    const gateway = AndroidDeviceZone();
    final zone = await gateway.read();
    expect(zone.status, DeviceZoneStatus.available);
    expect(zone.zoneId, isNotNull);
    expect(DeviceZoneObservation.fromId(zone.zoneId).zoneId, zone.zoneId);
    // No fixture database, host setting changes, inferred offset or fallback.
    // ignore: avoid_print
    print('device_zone_native status=${zone.status.name} zone=${zone.zoneId}');
    final subscription = gateway.changes.listen((_) {});
    await tester.pump();
    expect((await gateway.read()).zoneId, zone.zoneId);
    await subscription.cancel();
  });
}
