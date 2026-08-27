import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _viewType = 'com.xykw.nature_sound/amap_soundscape';

@visibleForTesting
bool? debugNativeAmapSupported;

bool get nativeAmapSupported =>
    debugNativeAmapSupported ?? (!kIsWeb && Platform.isAndroid);

class AmapNativeFeature {
  const AmapNativeFeature({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.postCount = 0,
    this.waitingCount = 0,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int postCount;
  final int waitingCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'post_count': postCount,
    'waiting_count': waitingCount,
  };
}

class AmapPrivacyBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.xykw.nature_sound/amap_privacy',
  );

  static Future<bool> isAvailable() async {
    if (!nativeAmapSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> hasConsent() async {
    if (!nativeAmapSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasConsent') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> accept() async {
    if (!nativeAmapSupported) return;
    await _channel.invokeMethod<void>('accept');
  }

  static Future<void> revoke() async {
    if (!nativeAmapSupported) return;
    await _channel.invokeMethod<void>('revoke');
  }

  static Future<void> openPrivacyPolicy() async {
    if (!nativeAmapSupported) return;
    await _channel.invokeMethod<void>('openPrivacyPolicy');
  }
}

class AmapNativeController {
  AmapNativeController(this._channel);

  final MethodChannel _channel;

  Future<void> zoomIn() => _channel.invokeMethod<void>('zoomIn');
  Future<void> zoomOut() => _channel.invokeMethod<void>('zoomOut');
  Future<void> reset() => _channel.invokeMethod<void>('reset');
}

class NativeAmapView extends StatefulWidget {
  const NativeAmapView({
    super.key,
    required this.areas,
    required this.parks,
    required this.onCreated,
    required this.onReady,
    required this.onFeatureTap,
    required this.onError,
  });

  final List<AmapNativeFeature> areas;
  final List<AmapNativeFeature> parks;
  final ValueChanged<AmapNativeController> onCreated;
  final ValueChanged<String?> onReady;
  final void Function(String type, String id) onFeatureTap;
  final ValueChanged<String> onError;

  @override
  State<NativeAmapView> createState() => _NativeAmapViewState();
}

class _NativeAmapViewState extends State<NativeAmapView> {
  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ready':
          final arguments =
              (call.arguments as Map<Object?, Object?>?) ?? const {};
          widget.onReady(arguments['approval_number'] as String?);
        case 'featureTap':
          final arguments =
              (call.arguments as Map<Object?, Object?>?) ?? const {};
          final type = arguments['type'] as String?;
          final featureId = arguments['id'] as String?;
          if (type != null && featureId != null) {
            widget.onFeatureTap(type, featureId);
          }
        case 'error':
          final arguments =
              (call.arguments as Map<Object?, Object?>?) ?? const {};
          widget.onError(arguments['message'] as String? ?? '地图加载失败');
      }
    });
    widget.onCreated(AmapNativeController(channel));
  }

  @override
  Widget build(BuildContext context) => AndroidView(
    key: const Key('native-amap-view'),
    viewType: _viewType,
    onPlatformViewCreated: _onPlatformViewCreated,
    creationParamsCodec: const StandardMessageCodec(),
    creationParams: {
      'areas': widget.areas
          .map((item) => item.toJson())
          .toList(growable: false),
      'parks': widget.parks
          .map((item) => item.toJson())
          .toList(growable: false),
    },
  );
}
