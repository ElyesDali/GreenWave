import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/traffic_light.dart';

/// Service de détection des feux tricolores.
/// Sources : Overpass API (OSM) + data.gouv.fr Paris + cache offline local.
class TrafficLightService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Cache en mémoire pour éviter des appels réseau répétés
  List<TrafficLight>? _cachedLights;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 10);

  /// Récupère les feux tricolores autour de la zone donnée.
  /// Tente Overpass API en premier, puis Paris OpenData, puis cache offline.
  Future<List<TrafficLight>> fetchTrafficLights(
    double lat, double lon, {double radiusKm = 2.0}
  ) async {
    // Vérifier si le cache est encore valide
    if (_cachedLights != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedLights!;
    }

    // 1. Essayer data.gouv.fr Paris OpenData (feux tricolores Paris) en priorité
    try {
      final lights = await _fetchFromParisOpenData(lat, lon);
      if (lights.isNotEmpty) {
        _cachedLights = lights;
        _cacheTime = DateTime.now();
        return lights;
      }
    } catch (e) {
      debugPrint("Paris OpenData indisponible: $e");
    }

    // 2. Essayer Overpass API (OpenStreetMap) en fallback hors de Paris
    try {
      final lights = await _fetchFromOverpass(lat, lon, radiusKm);
      if (lights.isNotEmpty) {
        _cachedLights = lights;
        _cacheTime = DateTime.now();
        return lights;
      }
    } catch (e) {
      debugPrint("Overpass API indisponible: $e");
    }

    // 3. Fallback : cache offline local (assets/mock_data)
    final lights = await _loadOfflineCache();
    _cachedLights = lights;
    _cacheTime = DateTime.now();
    return lights;
  }

  /// Requête Overpass API pour les noeuds highway=traffic_signals
  Future<List<TrafficLight>> _fetchFromOverpass(
    double lat, double lon, double radiusKm
  ) async {
    final margin = radiusKm / 111.0; // ~1 degré = 111 km
    final minLat = lat - margin;
    final maxLat = lat + margin;
    final minLon = lon - margin;
    final maxLon = lon + margin;

    final query = '''
[out:json][timeout:15];
node["highway"="traffic_signals"]($minLat,$minLon,$maxLat,$maxLon);
out body;
''';

    final response = await _dio.post(
      'https://overpass-api.de/api/interpreter',
      data: 'data=${Uri.encodeComponent(query)}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );

    if (response.statusCode == 200) {
      final data = response.data is String
          ? json.decode(response.data)
          : response.data;
      final List elements = data['elements'] ?? [];
      return elements.map((e) => TrafficLight.fromOsmJson(e)).toList();
    }
    return [];
  }

  /// Paris OpenData : feux tricolores via l'API data.gouv.fr / opendata.paris.fr
  Future<List<TrafficLight>> _fetchFromParisOpenData(
    double lat, double lon
  ) async {
    // API Paris OpenData - catalogue des feux tricolores
    final response = await _dio.get(
      'https://opendata.paris.fr/api/explore/v2.1/catalog/datasets/signalisation-tricolore/records',
      queryParameters: {
        'limit': 100,
        'geofilter.distance': '$lat,$lon,2000', // rayon 2km
      },
    );

    if (response.statusCode == 200) {
      final data = response.data is String
          ? json.decode(response.data)
          : response.data;
      final List records = data['results'] ?? [];
      return records
          .where((r) => r['geo_point_2d'] != null)
          .map((r) {
            final geo = r['geo_point_2d'];
            return TrafficLight(
              latitude: (geo['lat'] as num).toDouble(),
              longitude: (geo['lon'] as num).toDouble(),
            );
          })
          .toList();
    }
    return [];
  }

  /// Charge le fichier JSON offline embarqué dans les assets
  Future<List<TrafficLight>> _loadOfflineCache() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/mock_data/paris_traffic_lights.json',
      );
      final List data = json.decode(jsonStr);
      return data.map((e) => TrafficLight.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Erreur chargement cache offline: $e");
      // Dernier recours : feux codés en dur pour test ECE/Vésinet
      return _hardcodedFallback();
    }
  }

  /// Feux codés en dur pour test sans réseau ni assets
  List<TrafficLight> _hardcodedFallback() {
    return [
      TrafficLight(latitude: 48.8566, longitude: 2.3522, cycleRouge: 40, offset: 0),
      TrafficLight(latitude: 48.8512, longitude: 2.2885, cycleRouge: 40, offset: 12),
      TrafficLight(latitude: 48.8920, longitude: 2.1278, cycleRouge: 35, offset: 5),
      TrafficLight(latitude: 48.8520, longitude: 2.2890, cycleRouge: 40, offset: 25),
    ];
  }

  /// Trouve le feu le plus proche d'une position donnée parmi ceux en cache
  TrafficLight? findNearest(double lat, double lon) {
    if (_cachedLights == null || _cachedLights!.isEmpty) return null;
    TrafficLight? nearest;
    double minDist = double.infinity;
    for (final light in _cachedLights!) {
      final d = _quickDist(lat, lon, light.latitude, light.longitude);
      if (d < minDist) {
        minDist = d;
        nearest = light;
      }
    }
    return nearest;
  }

  /// Distance approximative rapide (Pythagore sur petites distances)
  double _quickDist(double lat1, double lon1, double lat2, double lon2) {
    final dLat = (lat2 - lat1) * 111000; // ~111km par degré lat
    final dLon = (lon2 - lon1) * 78500;  // ~78.5km par degré lon à ~45°N
    return (dLat * dLat + dLon * dLon); // Pas besoin de sqrt pour comparer
  }
}
