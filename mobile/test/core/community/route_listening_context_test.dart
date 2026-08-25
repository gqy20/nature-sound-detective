import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/community/route_listening_context.dart';
import 'package:nature_sound_detective/core/models/audio_quality.dart';
import 'package:nature_sound_detective/core/storage/exploration_record.dart';

void main() {
  const context = RouteListeningContext(
    parkId: 'taiziwan-park',
    parkName: '太子湾公园',
    zoneId: 'stream-trail',
    zoneName: '溪流步道',
    siteId: 'taiziwan-park:stream-trail',
    routeId: 'taiziwan-family-short',
    routeName: '城市公园亲子短路线',
    stopIndex: 1,
    safeObservationConfirmed: true,
  );

  test('persists and clears the active route listening context', () async {
    final directory = await Directory.systemTemp.createTemp('route-context-');
    addTearDown(() => directory.delete(recursive: true));
    final store = RouteListeningContextStore(
      directoryProvider: () async => directory,
    );

    expect(await store.load(), isNull);
    await store.save(context);
    final restored = await store.load();
    expect(restored?.siteId, context.siteId);
    expect(restored?.stopIndex, 1);
    expect(restored?.safeObservationConfirmed, isTrue);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('round-trips route context inside an exploration record', () {
    final record = ExplorationRecord(
      id: 'record-1',
      createdAt: DateTime.utc(2026, 8, 25),
      location: '太子湾公园',
      audioPath: '/tmp/record.wav',
      duration: const Duration(seconds: 12),
      audioQuality: const AudioQuality(usable: true),
      detections: const [],
      routeContext: context,
    );

    final restored = ExplorationRecord.fromJson(record.toJson());
    expect(restored.routeContext?.parkId, 'taiziwan-park');
    expect(restored.routeContext?.zoneId, 'stream-trail');
    expect(restored.routeContext?.routeId, 'taiziwan-family-short');
  });
}
