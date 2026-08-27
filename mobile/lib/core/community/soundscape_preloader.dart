import 'dart:async';

import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/community/community_service.dart';
import 'package:nature_sound_detective/core/logging/app_log.dart';

class SoundscapeBootstrapData {
  const SoundscapeBootstrapData({
    required this.areas,
    required this.posts,
    required this.parks,
  });

  final List<SoundscapeArea> areas;
  final List<CommunityPost> posts;
  final List<CommunityPark> parks;

  static Future<SoundscapeBootstrapData> fetch(CommunityService service) async {
    final values = await Future.wait([
      service.listAreas(),
      service.listPosts(),
      service.listParks(),
    ]);
    return SoundscapeBootstrapData(
      areas: values[0] as List<SoundscapeArea>,
      posts: values[1] as List<CommunityPost>,
      parks: values[2] as List<CommunityPark>,
    );
  }
}

class SoundscapePreloader {
  SoundscapePreloader({CommunityService? service})
    : service = service ?? HttpCommunityService(),
      _ownsService = service == null;

  final CommunityService service;
  final bool _ownsService;
  SoundscapeBootstrapData? _cached;
  Future<SoundscapeBootstrapData>? _pending;

  SoundscapeBootstrapData? get cached => _cached;

  Future<SoundscapeBootstrapData> load({bool force = false}) {
    if (!force) {
      final cached = _cached;
      if (cached != null) return Future.value(cached);
      final pending = _pending;
      if (pending != null) return pending;
    }
    final request = _fetch();
    _pending = request;
    return request.whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
  }

  Future<SoundscapeBootstrapData> _fetch() async {
    final timer = Stopwatch()..start();
    AppLog.info('community', 'soundscape_preload_started');
    try {
      final value = await SoundscapeBootstrapData.fetch(service);
      _cached = value;
      timer.stop();
      AppLog.info(
        'community',
        'soundscape_preload_completed',
        fields: {
          'duration_ms': timer.elapsedMilliseconds,
          'area_count': value.areas.length,
          'post_count': value.posts.length,
          'park_count': value.parks.length,
        },
      );
      return value;
    } catch (error, stackTrace) {
      timer.stop();
      AppLog.warning(
        'community',
        'soundscape_preload_failed',
        fields: {'duration_ms': timer.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void close() {
    if (_ownsService && service is HttpCommunityService) {
      (service as HttpCommunityService).close();
    }
  }
}
