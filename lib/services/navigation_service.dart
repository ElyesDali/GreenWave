import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/route_step.dart';

/// Service de navigation utilisant l'API Mapbox Directions + Geocoding.
class NavigationService {
  final Dio _dio = Dio();
  final String _accessToken;

  NavigationService(this._accessToken);

  /// Géocode une adresse en coordonnées (lat, lon) via Mapbox Geocoding API
  Future<List<GeocodingResult>> geocode(String query) async {
    if (query.trim().isEmpty) return [];

    final response = await _dio.get(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json',
      queryParameters: {
        'access_token': _accessToken,
        'language': 'fr',
        'country': 'fr',
        'limit': 5,
        'types': 'address,poi,place',
      },
    );

    if (response.statusCode == 200) {
      final data = response.data is String
          ? json.decode(response.data)
          : response.data;
      final List features = data['features'] ?? [];
      return features.map((f) {
        final coords = f['center'] as List; // [lon, lat]
        return GeocodingResult(
          name: f['place_name'] ?? '',
          latitude: (coords[1] as num).toDouble(),
          longitude: (coords[0] as num).toDouble(),
        );
      }).toList();
    }
    return [];
  }

  /// Calcule un itinéraire entre deux points via Mapbox Directions API
  Future<RouteResult?> getRoute(
    double startLat, double startLng,
    double endLat, double endLng,
  ) async {
    final response = await _dio.get(
      'https://api.mapbox.com/directions/v5/mapbox/driving/'
      '$startLng,$startLat;$endLng,$endLat',
      queryParameters: {
        'access_token': _accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'true',
        'language': 'fr',
        'annotations': 'speed,duration',
      },
    );

    if (response.statusCode == 200) {
      final data = response.data is String
          ? json.decode(response.data)
          : response.data;
      final List routes = data['routes'] ?? [];
      if (routes.isEmpty) return null;

      final route = routes[0];
      final geometry = route['geometry'];
      final List legs = route['legs'] ?? [];

      // Parser les étapes de navigation
      List<RouteStep> steps = [];
      for (final leg in legs) {
        final List legSteps = leg['steps'] ?? [];
        for (int i = 0; i < legSteps.length; i++) {
          final s = legSteps[i];
          final maneuver = s['maneuver'];
          final location = maneuver['location'] as List;

          // Coordonnées de fin = début de l'étape suivante ou fin du trajet
          double endStepLat = endLat;
          double endStepLng = endLng;
          if (i + 1 < legSteps.length) {
            final nextLoc = legSteps[i + 1]['maneuver']['location'] as List;
            endStepLat = (nextLoc[1] as num).toDouble();
            endStepLng = (nextLoc[0] as num).toDouble();
          }

          steps.add(RouteStep(
            startLat: (location[1] as num).toDouble(),
            startLng: (location[0] as num).toDouble(),
            endLat: endStepLat,
            endLng: endStepLng,
            distance: (s['distance'] as num).toDouble(),
            instruction: maneuver['instruction'] ?? '',
          ));
        }
      }

      // Extraire les coordonnées GeoJSON pour tracer la ligne sur la carte
      final List coords = geometry['coordinates'] ?? [];
      final routeCoords = coords
          .map((c) => [
                (c[0] as num).toDouble(), // lon
                (c[1] as num).toDouble(), // lat
              ])
          .toList();

      return RouteResult(
        steps: steps,
        durationSeconds: (route['duration'] as num).toDouble(),
        distanceMeters: (route['distance'] as num).toDouble(),
        routeCoordinates: routeCoords,
      );
    }
    return null;
  }
}

/// Résultat de géocodage
class GeocodingResult {
  final String name;
  final double latitude;
  final double longitude;

  GeocodingResult({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

/// Résultat complet d'un itinéraire calculé
class RouteResult {
  final List<RouteStep> steps;
  final double durationSeconds;
  final double distanceMeters;
  final List<List<double>> routeCoordinates; // [[lon,lat], ...]

  RouteResult({
    required this.steps,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.routeCoordinates,
  });
}
