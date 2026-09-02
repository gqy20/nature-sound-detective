import 'package:nature_sound_detective/core/community/community_models.dart';

class CommunitySoundscapeFocus {
  const CommunitySoundscapeFocus({
    required this.sourceSpeciesName,
    required this.habitatTags,
    this.parkId,
    this.siteId,
    this.areaId,
  });

  final String sourceSpeciesName;
  final String? parkId;
  final String? siteId;
  final String? areaId;
  final List<String> habitatTags;
}

class CommunityActivityPoint {
  const CommunityActivityPoint({
    required this.id,
    required this.label,
    required this.recordCount,
    required this.sourceSpeciesRecordCount,
    required this.soundTypes,
    required this.habitatTags,
    required this.lastObservedAt,
    this.parkId,
    this.siteId,
    this.areaId,
  });

  final String id;
  final String label;
  final int recordCount;
  final int sourceSpeciesRecordCount;
  final List<String> soundTypes;
  final List<String> habitatTags;
  final DateTime lastObservedAt;
  final String? parkId;
  final String? siteId;
  final String? areaId;
}

class CommunityActivityHint {
  const CommunityActivityHint({
    required this.speciesName,
    required this.matchingRecordCount,
    required this.relatedRecordCount,
    required this.soundTypes,
    required this.habitatTags,
    required this.points,
    required this.focus,
    required this.nearCurrentLocation,
  });

  final String speciesName;
  final int matchingRecordCount;
  final int relatedRecordCount;
  final List<String> soundTypes;
  final List<String> habitatTags;
  final List<CommunityActivityPoint> points;
  final CommunitySoundscapeFocus focus;
  final bool nearCurrentLocation;
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
    final values = await Future.wait<Object>([
      postsLoader(),
      parksLoader(),
      sitesLoader(),
    ]);
    final realPosts = (values[0] as List<CommunityPost>)
        .where((post) => !post.isDemo)
        .toList(growable: false);
    final parks = values[1] as List<CommunityPark>;
    final sites = values[2] as List<CommunitySite>;
    final parksById = {for (final park in parks) park.id: park};
    final sitesById = {for (final site in sites) site.id: site};
    final anchorPosts = realPosts
        .where((post) => _matches(post, normalizedSpecies))
        .toList(growable: false);
    if (anchorPosts.isEmpty && preferredParkId == null) return null;

    String? parkIdFor(CommunityPost post) =>
        sitesById[post.siteId]?.parkId ?? post.parkId;

    List<String> habitatTagsFor(CommunityPost post) {
      final tags = <String>{};
      final site = sitesById[post.siteId];
      if (site != null) tags.addAll(site.habitatTags);
      final park = parksById[parkIdFor(post)];
      if (park != null) tags.addAll(park.habitatTags);
      return tags.where((tag) => tag.trim().isNotEmpty).toList(growable: false);
    }

    final seedSiteIds = anchorPosts
        .map((post) => post.siteId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final seedParkIds = anchorPosts
        .map(parkIdFor)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    if (preferredParkId case final id? when id.isNotEmpty) seedParkIds.add(id);
    final seedAreaIds = anchorPosts
        .map((post) => post.areaId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (parksById[preferredParkId]?.areaId case final areaId?) {
      seedAreaIds.add(areaId);
    }
    final seedHabitatTags = <String>{
      for (final post in anchorPosts) ...habitatTagsFor(post),
      if (parksById[preferredParkId] case final park?) ...park.habitatTags,
    };

    bool isRelated(CommunityPost post) {
      if (_matches(post, normalizedSpecies)) return true;
      final parkId = parkIdFor(post);
      if (preferredParkId != null && parkId == preferredParkId) return true;
      if (post.siteId != null && seedSiteIds.contains(post.siteId)) return true;
      if (parkId != null && seedParkIds.contains(parkId)) return true;
      final habitats = habitatTagsFor(post).toSet();
      if (habitats.intersection(seedHabitatTags).isNotEmpty) return true;
      return seedHabitatTags.isEmpty && seedAreaIds.contains(post.areaId);
    }

    final relatedPosts = realPosts.where(isRelated).toList(growable: false);
    if (relatedPosts.isEmpty) return null;
    final groups = <String, List<CommunityPost>>{};
    for (final post in relatedPosts) {
      final key = switch (post.siteId) {
        final String value when value.isNotEmpty => 'site:$value',
        _ => switch (parkIdFor(post)) {
          final String value when value.isNotEmpty => 'park:$value',
          _ => 'area:${post.areaId.isEmpty ? post.areaName : post.areaId}',
        },
      };
      groups.putIfAbsent(key, () => []).add(post);
    }

    final points =
        groups.entries
            .map((entry) {
              final posts = entry.value
                ..sort(
                  (left, right) => right.observedAt.compareTo(left.observedAt),
                );
              final sample = posts.first;
              final site = sitesById[sample.siteId];
              final parkId = parkIdFor(sample);
              final park = parksById[parkId];
              final label = site != null
                  ? '${site.parkName} · ${site.zoneName}'
                  : park?.name ?? '${sample.areaName}公开记录';
              final habitats = {
                for (final post in posts) ...habitatTagsFor(post),
              }.toList(growable: false);
              final soundTypes = posts
                  .map((post) => post.soundType.trim())
                  .where((type) => type.isNotEmpty)
                  .toSet()
                  .toList(growable: false);
              return CommunityActivityPoint(
                id: entry.key,
                label: label,
                recordCount: posts.length,
                sourceSpeciesRecordCount: posts
                    .where((post) => _matches(post, normalizedSpecies))
                    .length,
                soundTypes: soundTypes,
                habitatTags: habitats,
                lastObservedAt: posts.first.observedAt,
                parkId: site?.parkId ?? parkId,
                siteId: site?.id ?? sample.siteId,
                areaId: park?.areaId ?? sample.areaId,
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            final preferredOrder = (right.parkId == preferredParkId ? 1 : 0)
                .compareTo(left.parkId == preferredParkId ? 1 : 0);
            if (preferredOrder != 0) return preferredOrder;
            final anchorOrder = right.sourceSpeciesRecordCount.compareTo(
              left.sourceSpeciesRecordCount,
            );
            if (anchorOrder != 0) return anchorOrder;
            final diversityOrder = right.soundTypes.length.compareTo(
              left.soundTypes.length,
            );
            if (diversityOrder != 0) return diversityOrder;
            final countOrder = right.recordCount.compareTo(left.recordCount);
            if (countOrder != 0) return countOrder;
            return right.lastObservedAt.compareTo(left.lastObservedAt);
          });

    final topPoints = points.take(3).toList(growable: false);
    final primaryPoint = topPoints.first;
    final soundTypes = relatedPosts
        .map((post) => post.soundType.trim())
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final habitats = {
      for (final point in topPoints) ...point.habitatTags,
    }.toList(growable: false);
    return CommunityActivityHint(
      speciesName: speciesName,
      matchingRecordCount: anchorPosts.length,
      relatedRecordCount: relatedPosts.length,
      soundTypes: soundTypes,
      habitatTags: habitats,
      points: topPoints,
      focus: CommunitySoundscapeFocus(
        sourceSpeciesName: speciesName,
        parkId: primaryPoint.parkId,
        siteId: primaryPoint.siteId,
        areaId: primaryPoint.areaId,
        habitatTags: primaryPoint.habitatTags,
      ),
      nearCurrentLocation:
          preferredParkId != null && primaryPoint.parkId == preferredParkId,
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
