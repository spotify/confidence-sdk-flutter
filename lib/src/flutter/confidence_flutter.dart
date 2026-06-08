import '../confidence.dart';
import '../confidence_value.dart';
import '../resolve_client.dart';
import 'device_context.dart';
import 'flutter_storage.dart';
import 'visitor_id.dart';

class ConfidenceFlutter {
  ConfidenceFlutter._();

  static Future<Confidence> create({
    required String clientSecret,
    ConfidenceRegion region = ConfidenceRegion.global,
    Map<String, ConfidenceValue> initialContext = const {},
  }) async {
    final storage = await FlutterStorage.create();
    final visitorIdManager = VisitorIdManager();
    final deviceContextProvider = DeviceContextProvider();

    final visitorContext = await visitorIdManager.asContext();
    final deviceContext = await deviceContextProvider.getDeviceContext();

    // Merge: device context < visitor ID < user-provided context
    final mergedContext = <String, ConfidenceValue>{
      ...deviceContext,
      ...visitorContext,
      ...initialContext,
    };

    return Confidence.builder(clientSecret: clientSecret)
        .region(region)
        .storage(storage)
        .initialContext(mergedContext)
        .build();
  }
}
