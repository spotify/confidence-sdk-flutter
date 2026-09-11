import 'package:confidence_flutter_sdk/src/flutter/visitor_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('imports the existing native ID exactly, including UUID case', () async {
    const native = '48BFBE9E-C583-4CF3-9417-779F8BEA1A01';
    final manager = VisitorIdManager(nativeIdReader: () async => native);
    expect(await manager.getOrCreate(), native);
    expect(
        (await SharedPreferences.getInstance())
            .getString('confidence.visitor_id'),
        native);
    expect(
        await VisitorIdManager(nativeIdReader: () async => 'changed-native')
            .getOrCreate(),
        native);
  });

  test('an existing Dart ID wins without reading native preferences', () async {
    SharedPreferences.setMockInitialValues(
        {'confidence.visitor_id': 'current'});
    final manager = VisitorIdManager(nativeIdReader: () async {
      fail('Native preferences must not override the current identity');
    });
    expect(await manager.getOrCreate(), 'current');
  });

  test('fresh installs generate one persistent ID across concurrent factories',
      () async {
    final ids = await Future.wait(List.generate(
        20,
        (_) =>
            VisitorIdManager(nativeIdReader: () async => null).getOrCreate()));
    expect(ids.toSet(), hasLength(1));
    expect(ids.first, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(
        await VisitorIdManager(nativeIdReader: () async => null).getOrCreate(),
        ids.first);
  });

  test('empty Dart preference imports native ID; unrelated preferences survive',
      () async {
    SharedPreferences.setMockInitialValues(
        {'confidence.visitor_id': '', 'app-user': 'keep'});
    expect(
        await VisitorIdManager(nativeIdReader: () async => 'native')
            .getOrCreate(),
        'native');
    expect(
        (await SharedPreferences.getInstance()).getString('app-user'), 'keep');
  });

  test('a failed native read does not silently rotate identity and can retry',
      () async {
    var fails = true;
    final manager = VisitorIdManager(nativeIdReader: () async {
      if (fails) throw StateError('temporarily unavailable');
      return 'original';
    });
    await expectLater(manager.getOrCreate(), throwsStateError);
    expect(
        (await SharedPreferences.getInstance())
            .getString('confidence.visitor_id'),
        null);
    fails = false;
    expect(await manager.getOrCreate(), 'original');
  });
}
