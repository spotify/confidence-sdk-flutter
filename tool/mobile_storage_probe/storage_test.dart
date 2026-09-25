import 'dart:io';

import 'package:confidence_openfeature_provider/src/storage/legacy_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads native paths and unprefixed identity without mutation', (
    tester,
  ) async {
    const native = MethodChannel('confidence.storage-probe');
    final expected = (await native.invokeMapMethod<String, String>('seed'))!;
    final storage = await LegacyStorage.locate();

    expect(await storage.flags.resolveSymbolicLinks(), expected['flags']);
    expect(await storage.apply.resolveSymbolicLinks(), expected['apply']);
    expect(await storage.events.resolveSymbolicLinks(), expected['events']);
    expect(await storage.flags.readAsString(), 'legacy-flags');
    expect(await storage.apply.readAsString(), 'legacy-apply');
    final names = <String, String>{};
    await for (final entity in storage.events.list()) {
      if (entity is File) {
        names[entity.uri.pathSegments.last] = await entity.readAsString();
      }
    }
    expect(names, {
      if (Platform.isAndroid) 'batch.ready': 'sealed-event',
      if (Platform.isIOS) 'batch.READY': 'sealed-event',
      'unfinished': 'unfinished-event',
    });
    expect(await storage.readVisitorId(), 'native-visitor');

    // An uncached read must observe native updates, not a stale Flutter cache.
    await native.invokeMethod<void>('changeIdentity');
    expect(await storage.readVisitorId(), 'updated-native-visitor');
    await native.invokeMethod<void>('removeIdentity');
    expect(await storage.readVisitorId(), isNull);
    expect(await storage.readVisitorId(), isNull); // no generated replacement
    expect(await storage.flags.readAsString(), 'legacy-flags');
    expect(await storage.apply.readAsString(), 'legacy-apply');
  });
}
