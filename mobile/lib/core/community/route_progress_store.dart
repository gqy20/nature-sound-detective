import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExplorationRouteProgress {
  const ExplorationRouteProgress({
    required this.routeId,
    this.completedSiteIds = const {},
    this.startedAt,
    this.completedAt,
  });

  factory ExplorationRouteProgress.fromJson(Map<String, Object?> json) =>
      ExplorationRouteProgress(
        routeId: json['route_id'] as String? ?? '',
        completedSiteIds:
            (json['completed_site_ids'] as List<Object?>? ?? const [])
                .whereType<String>()
                .toSet(),
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
        completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      );

  final String routeId;
  final Set<String> completedSiteIds;
  final DateTime? startedAt;
  final DateTime? completedAt;

  Map<String, Object?> toJson() => {
    'route_id': routeId,
    'completed_site_ids': completedSiteIds.toList(growable: false),
    if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
  };
}

abstract interface class RouteProgressStore {
  Future<ExplorationRouteProgress> load(String routeId);
  Future<void> save(ExplorationRouteProgress progress);
}

class FileRouteProgressStore implements RouteProgressStore {
  FileRouteProgressStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file(String routeId) async {
    final base = await _directoryProvider();
    final directory = Directory(p.join(base.path, 'community_routes'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, '$routeId.json'));
  }

  @override
  Future<ExplorationRouteProgress> load(String routeId) async {
    final file = await _file(routeId);
    if (!await file.exists()) return ExplorationRouteProgress(routeId: routeId);
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<Object?, Object?>) {
        final progress = ExplorationRouteProgress.fromJson(
          value.cast<String, Object?>(),
        );
        if (progress.routeId == routeId) return progress;
      }
    } on FormatException {
      // Damaged local progress is reset; no community or ecological data is lost.
    }
    return ExplorationRouteProgress(routeId: routeId);
  }

  @override
  Future<void> save(ExplorationRouteProgress progress) async {
    final file = await _file(progress.routeId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(progress.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
