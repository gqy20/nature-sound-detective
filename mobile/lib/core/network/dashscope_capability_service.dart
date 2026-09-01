import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nature_sound_detective/core/logging/app_log.dart';
import 'package:nature_sound_detective/core/models/creation.dart';

enum DashscopeCapabilityStatus { allowed, denied, unknown }

// `denied` is only a reliable execution gate for explicitly permission-gated
// models such as Fun-Music. Standard models may remain callable even when this
// authorization-management endpoint reports inference=false.

class DashscopeCapabilityReport {
  const DashscopeCapabilityReport(this.statuses);

  final Map<String, DashscopeCapabilityStatus> statuses;

  DashscopeCapabilityStatus statusOf(String model) =>
      statuses[model] ?? DashscopeCapabilityStatus.unknown;
}

abstract interface class DashscopeCapabilityChecker {
  Future<DashscopeCapabilityReport> check(
    CreationSettings settings,
    Iterable<String> models, {
    String traceId = '',
  });
}

class DashscopeCapabilityService implements DashscopeCapabilityChecker {
  DashscopeCapabilityService({
    http.Client? client,
    this.cacheDuration = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration cacheDuration;
  final _cache = <String, _CachedCapability>{};

  @override
  Future<DashscopeCapabilityReport> check(
    CreationSettings settings,
    Iterable<String> models, {
    String traceId = '',
  }) async {
    final statuses = <String, DashscopeCapabilityStatus>{};
    for (final model in models.map((value) => value.trim()).toSet()) {
      if (model.isEmpty) continue;
      statuses[model] = await _checkModel(settings, model, traceId);
    }
    return DashscopeCapabilityReport(Map.unmodifiable(statuses));
  }

  Future<DashscopeCapabilityStatus> _checkModel(
    CreationSettings settings,
    String model,
    String traceId,
  ) async {
    final cacheKey = [
      settings.dashscopeBaseUrl,
      model,
      settings.dashscopeApiKey.hashCode,
    ].join('|');
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.checkedAt) < cacheDuration) {
      return cached.status;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(
        '${settings.dashscopeBaseUrl}/api/v1/models/permissions',
      ).replace(queryParameters: {'model': model});
      final response = await _client
          .get(
            uri,
            headers: {
              HttpHeaders.authorizationHeader:
                  'Bearer ${settings.dashscopeApiKey.trim()}',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLog.warning(
          'creation',
          'model_permission_check_unavailable',
          traceId: traceId,
          fields: {
            'model': model,
            'status_code': response.statusCode,
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return DashscopeCapabilityStatus.unknown;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<Object?, Object?>) {
        return DashscopeCapabilityStatus.unknown;
      }
      final output = decoded['output'];
      final rawEntries = output is Map<Object?, Object?>
          ? output['permissions']
          : null;
      final entries = rawEntries is List<Object?>
          ? rawEntries.whereType<Map<Object?, Object?>>()
          : const Iterable<Map<Object?, Object?>>.empty();
      Map<Object?, Object?>? matched;
      for (final entry in entries) {
        if (entry['model']?.toString() == model) {
          matched = entry;
          break;
        }
      }
      final rawPermission = matched?['permissions'];
      final allowed =
          rawPermission is Map<Object?, Object?> &&
          rawPermission['inference'] == true;
      AppLog.info(
        'creation',
        'model_permission_checked',
        traceId: traceId,
        fields: {
          'model': model,
          'allowed': allowed,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      final status = allowed
          ? DashscopeCapabilityStatus.allowed
          : DashscopeCapabilityStatus.denied;
      _cache[cacheKey] = _CachedCapability(status, DateTime.now());
      return status;
    } on TimeoutException catch (error, stackTrace) {
      AppLog.warning(
        'creation',
        'model_permission_check_unavailable',
        traceId: traceId,
        fields: {'model': model, 'duration_ms': stopwatch.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      return DashscopeCapabilityStatus.unknown;
    } on SocketException catch (error, stackTrace) {
      AppLog.warning(
        'creation',
        'model_permission_check_unavailable',
        traceId: traceId,
        fields: {'model': model, 'duration_ms': stopwatch.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      return DashscopeCapabilityStatus.unknown;
    } on FormatException catch (error, stackTrace) {
      AppLog.warning(
        'creation',
        'model_permission_check_unavailable',
        traceId: traceId,
        fields: {'model': model, 'duration_ms': stopwatch.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      return DashscopeCapabilityStatus.unknown;
    } catch (error, stackTrace) {
      AppLog.warning(
        'creation',
        'model_permission_check_unavailable',
        traceId: traceId,
        fields: {'model': model, 'duration_ms': stopwatch.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      return DashscopeCapabilityStatus.unknown;
    }
  }
}

class _CachedCapability {
  const _CachedCapability(this.status, this.checkedAt);

  final DashscopeCapabilityStatus status;
  final DateTime checkedAt;
}
