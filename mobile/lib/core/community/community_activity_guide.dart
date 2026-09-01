import 'package:nature_sound_detective/core/community/community_models.dart';

class CommunityActivityPoint {
  const CommunityActivityPoint({
    required this.id,
    required this.label,
    required this.recordCount,
    required this.lastObservedAt,
    this.parkId,
    this.siteId,
  });

  final String id;
  final String label;
  final int recordCount;
  final DateTime lastObservedAt;
  final String? parkId;
  final String? siteId;
}

class CommunityActivityHint {
  const CommunityActivityHint({
    required this.speciesName,
    required this.matchingRecordCount,
    required this.points,
  });

  final String speciesName;
  final int matchingRecordCount;
  final List<CommunityActivityPoint> points;
}

class CommunityActivityGuide {
  const CommunityActivityGuide({
    required this.postsLoader,
    required this.parksLoader,
    required this.sitesLoader,
  });

  final Future<List<CommunityPost>> Function() postsLoader;
  final Future<List<CommunityPark>> Function() parksLoader;
  final Future<List<CommunitySite>> Function() sitesLoader;

  Future<CommunityActivityHint?> load(
    String speciesName, {
    String? preferredParkId,
  }) async {
    final normalizedSpecies = _normalize(speciesName);
    if (normalizedSpecies.isEmpty) return null;
    final posts = (await postsLoader())
        .where((post) => !post.isDemo && _matches(post, normalizedSpecies))
        .toList(growable: false);
    if (posts.isEmpty) return null;

    final references = await Future.wait<Object>([
      parksLoader(),
      sitesLoader(),
    ]);
    final parks = references[0] as List<CommunityPark>;
    final sites = references[1] as List<CommunitySite>;
    final parksById = {for (final park in parks) park.id: park};
    final sitesById = {for (final site in sites) site.id: site};
    final groups = <String, List<CommunityPost>>{};
    for (final post in posts) {
      final key = switch (post.siteId) {
        final String value when value.isNotEmpty => 'site:$value',
        _ => switch (post.parkId) {
          final String value when value.isNotEmpty => 'park:$value',
          _ => 'area:${post.areaId.isEmpty ? post.areaName : post.areaId}',
        },
      };
      groups.putIfAbsent(key, () => []).add(post);
    }

    final points =
        groups.entries
            .map((entry) {
              final values = entry.value
                ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
              final sample = values.first;
              final site = sample.siteId == null
                  ? null
                  : sitesById[sample.siteId];
              final park = sample.parkId == null
                  ? null
                  : parksById[sample.parkId];
              final label = site != null
                  ? '${site.parkName} · ${site.zoneName}'
                  : park?.name ?? '${sample.areaName}公开记录';
              return CommunityActivityPoint(
                id: entry.key,
                label: label,
                recordCount: values.length,
                lastObservedAt: values.first.observedAt,
                parkId: site?.parkId ?? sample.parkId,
                siteId: site?.id ?? sample.siteId,
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aPreferred = a.parkId == preferredParkId ? 1 : 0;
            final bPreferred = b.parkId == preferredParkId ? 1 : 0;
            final preferredOrder = bPreferred.compareTo(aPreferred);
            if (preferredOrder != 0) return preferredOrder;
            final countOrder = b.recordCount.compareTo(a.recordCount);
            if (countOrder != 0) return countOrder;
            return b.lastObservedAt.compareTo(a.lastObservedAt);
          });

    return CommunityActivityHint(
      speciesName: speciesName,
      matchingRecordCount: posts.length,
      points: points.take(3).toList(growable: false),
    );
  }

  static bool _matches(CommunityPost post, String normalizedSpecies) {
    final names = <String>[
      post.subject,
      ...post.candidateNames,
      ...post.responseSummary.keys,
    ];
    return names.any((name) => _normalize(name).contains(normalizedSpecies));
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s·・，,。.!！?？_-]+'), '');
}
