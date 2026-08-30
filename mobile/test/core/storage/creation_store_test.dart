import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nature_sound_detective/core/models/creation.dart';
import 'package:nature_sound_detective/core/storage/creation_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('persists, orders, restores and deletes creation records', () async {
    final directory = await Directory.systemTemp.createTemp('creation_store_');
    addTearDown(() => directory.delete(recursive: true));
    final store = CreationStore(directoryProvider: () async => directory);
    final older = _record(directory, 'older', DateTime(2026, 1, 1));
    final newer = _record(directory, 'newer', DateTime(2026, 1, 2));

    await store.save(older);
    await store.save(newer);

    expect((await store.load('older'))?.wanTaskId, 'task-older');
    expect((await store.load('older'))?.visualMode, CreationVisualMode.bird);
    expect((await store.list()).map((record) => record.id), ['newer', 'older']);

    await store.delete(newer);
    expect(await store.load('newer'), isNull);
    expect(await store.load('older'), isNotNull);
  });

  test('refuses to delete a directory outside the creations root', () async {
    final directory = await Directory.systemTemp.createTemp('creation_guard_');
    addTearDown(() => directory.delete(recursive: true));
    final store = CreationStore(directoryProvider: () async => directory);
    final unsafe = _record(directory, 'unsafe', DateTime(2026));
    final outside = Directory(p.join(directory.path, 'outside'))..createSync();

    expect(
      () => store.delete(
        CreationRecord(
          id: unsafe.id,
          subject: unsafe.subject,
          location: unsafe.location,
          createdAt: unsafe.createdAt,
          updatedAt: unsafe.updatedAt,
          stage: unsafe.stage,
          message: unsafe.message,
          directoryPath: outside.path,
          sourceAudioPath: unsafe.sourceAudioPath,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('persists and clears the active creation pointer', () async {
    final directory = await Directory.systemTemp.createTemp('active_creation_');
    addTearDown(() => directory.delete(recursive: true));
    final store = ActiveCreationStore(directoryProvider: () async => directory);

    expect(await store.load(), isNull);
    await store.save('record-42');
    expect(await store.load(), 'record-42');
    await store.clear();
    expect(await store.load(), isNull);
  });
}

CreationRecord _record(Directory root, String id, DateTime createdAt) {
  final path = p.join(root.path, 'creations', id);
  return CreationRecord(
    id: id,
    subject: '白头鹎',
    location: '杭州',
    createdAt: createdAt,
    updatedAt: createdAt,
    stage: CreationStage.waitingForVideo,
    message: '等待视频',
    directoryPath: path,
    sourceAudioPath: p.join(path, 'nature_original.wav'),
    visualMode: CreationVisualMode.bird,
    wanTaskId: 'task-$id',
  );
}
