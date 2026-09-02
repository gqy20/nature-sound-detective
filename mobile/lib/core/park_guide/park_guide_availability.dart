import 'package:nature_sound_detective/core/community/community_models.dart';
import 'package:nature_sound_detective/core/park_guide/park_recommendation.dart';

/// Keeps the current pilot park catalog usable while richer, reviewed routes
/// are added incrementally by the backend.
class ParkGuideAvailability {
  const ParkGuideAvailability();

  ParkGuideData ensureBaselineRoute(ParkGuideData data) {
    if (data.sites.isEmpty || data.routes.any(_isBaselineCompatible)) {
      return data;
    }
    final site = data.sites.first;
    final baseline = ExplorationRoute(
      id: '${data.park.id}-family-baseline',
      parkId: data.park.id,
      name: '亲子轻量倾听路线',
      durationMinutes: 15,
      distanceKm: .4,
      ageMin: 0,
      tags: <String>{
        '亲子轻量',
        '短路线',
        ...data.park.habitatTags,
        ...site.habitatTags,
      }.toList(growable: false),
      stops: [
        ExplorationRouteStop(
          siteId: site.id,
          minutes: 8,
          mission: '由家长全程陪同，在公开步道完成一次安静倾听。',
        ),
      ],
      disclaimer: '这是为当前试点提供的基础可用方案；低龄儿童需由家长全程陪同，可随时结束行程。',
    );
    return ParkGuideData(
      park: data.park,
      sites: data.sites,
      routes: [...data.routes, baseline],
      snapshot: data.snapshot,
      brief: data.brief,
      loadWarnings: data.loadWarnings,
    );
  }

  static bool _isBaselineCompatible(ExplorationRoute route) =>
      route.ageMin == 0 && route.durationMinutes <= 20;
}
