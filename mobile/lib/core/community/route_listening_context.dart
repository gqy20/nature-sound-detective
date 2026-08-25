import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RouteListeningContext {
  const RouteListeningContext({
    required this.parkId,
    required this.parkName,
    required this.zoneId,
    required this.zoneName,
    required this.siteId,
    required this.routeId,
    required this.routeName,
    required this.stopIndex,
    this.safeObservationConfirmed = false,
  });

  factory RouteListeningContext.fromJson(Map<String, Object?> json) =>
      RouteListeningContext(
        parkId: json['park_id'] as String? ?? '',
        parkName: json['park_name'] as String? ?? '',
        zoneId: json['zone_id'] as String? ?? '',
        zoneName: json['zone_name'] as String? ?? '',
        siteId: json['site_id'] as String? ?? '',
        routeId: json['route_id'] as String? ?? '',
        routeName: json['route_name'] as String? ?? '',
        stopIndex: (json['stop_index'] as num?)?.toInt() ?? 0,
        safeObservationConfirmed:
            json['safe_observation_confirmed'] as bool? ?? false,
      );

  final String parkId;
  final String parkName;
  final String zoneId;
  final String zoneName;
  final String siteId;
  final String routeId;
  final String routeName;
  final int stopIndex;
  final bool safeObservationConfirmed;

  Map<String, Object?> toJson() => {
    'park_id': parkId,
    'park_name': parkName,
    'zone_id': zoneId,
    'zone_name': zoneName,
    'site_id': siteId,
    'route_id': routeId,
    'route_name': routeName,
    'stop_index': stopIndex,
    if (safeObservationConfirmed) 'safe_observation_confirmed': true,
  };
}

class RouteListeningContextStore {
  RouteListeningContextStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  static RouteListeningContext? _cached;

  RouteListeningContext? get cached => _cached;

  Future<File> _file() async {
    final base = await _directoryProvider();
    final directory = Directory(p.join(base.path, 'community_routes'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'active_listening_context.json'));
  }

  Future<RouteListeningContext?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is Map<Object?, Object?>) {
        final context = RouteListeningContext.fromJson(
          value.cast<String, Object?>(),
        );
        if (context.siteId.isNotEmpty) {
          _cached = context;
          return context;
        }
      }
    } catch (_) {
      // A missing platform store or damaged transient context is ignored.
    }
    return null;
  }

  Future<void> save(RouteListeningContext context) async {
    _cached = context;
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(context.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    _cached = null;
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Clearing optional route context must not block recording or import.
    }
  }
}
