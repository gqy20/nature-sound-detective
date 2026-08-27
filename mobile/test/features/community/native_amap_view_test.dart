import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/features/community/native_amap_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serializes only public aggregate map feature data', () {
    const feature = AmapNativeFeature(
      id: 'xihu',
      name: '西湖区',
      latitude: 30.259,
      longitude: 120.1302,
      postCount: 7,
      waitingCount: 2,
    );

    expect(feature.toJson(), {
      'id': 'xihu',
      'name': '西湖区',
      'latitude': 30.259,
      'longitude': 120.1302,
      'post_count': 7,
      'waiting_count': 2,
    });
    expect(feature.toJson(), isNot(contains('device_id')));
    expect(feature.toJson(), isNot(contains('recording_location')));
  });

  test('checks native map availability before requesting consent', () async {
    debugNativeAmapSupported = true;
    const channel = MethodChannel('com.xykw.nature_sound/amap_privacy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isAvailable') return false;
          fail(
            'Consent should not be queried when the debug key is unavailable',
          );
        });
    addTearDown(() {
      debugNativeAmapSupported = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await AmapPrivacyBridge.isAvailable(), isFalse);
  });
}
