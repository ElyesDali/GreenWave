import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/traffic_light_service.dart';
import '../services/navigation_service.dart';
import '../models/traffic_light.dart';
import '../utils/distance_utils.dart';
import '../utils/greenwave_calculator.dart';
import 'location_provider.dart';

// --- Providers de services ---

final trafficLightServiceProvider = Provider<TrafficLightService>((ref) {
  return TrafficLightService();
});

final navigationServiceProvider = Provider<NavigationService>((ref) {
  // Token public Mapbox - même que dans main.dart
  return NavigationService(
    'pk.eyJ1IjoibWlzdGVyZTEwIiwiYSI6ImNtcDh5MzFxajBjdzQyc3F1ejdnN2J6ZmwifQ.kL9x8VkcfnAb3fwfEW20rg',
  );
});

// --- Cache des feux tricolores (chargé une fois, mis à jour périodiquement) ---

final trafficLightsProvider = FutureProvider<List<TrafficLight>>((ref) async {
  final service = ref.watch(trafficLightServiceProvider);
  final posAsync = ref.watch(locationStreamProvider);

  return posAsync.when(
    data: (pos) => service.fetchTrafficLights(pos.latitude, pos.longitude),
    loading: () => service.fetchTrafficLights(48.8566, 2.3522), // Paris par défaut
    error: (_, __) => service.fetchTrafficLights(48.8566, 2.3522),
  );
});

// --- Route active (destination sélectionnée par l'utilisateur) ---

final destinationProvider = StateProvider<GeocodingResult?>((ref) => null);

final activeRouteProvider = FutureProvider<RouteResult?>((ref) async {
  final dest = ref.watch(destinationProvider);
  if (dest == null) return null;

  final nav = ref.watch(navigationServiceProvider);
  final posAsync = ref.watch(locationStreamProvider);

  return posAsync.when(
    data: (pos) => nav.getRoute(pos.latitude, pos.longitude, dest.latitude, dest.longitude),
    loading: () => null,
    error: (_, __) => null,
  );
});

// --- État GreenWave principal ---

class GreenWaveState {
  final double distanceToNextLight;
  final int secondsUntilGreen;
  final double recommendedSpeedKmh;
  final String statusText;
  final bool isActive;
  final bool isGreen; // Le feu est-il actuellement vert ?

  GreenWaveState({
    required this.distanceToNextLight,
    required this.secondsUntilGreen,
    required this.recommendedSpeedKmh,
    required this.statusText,
    required this.isActive,
    this.isGreen = false,
  });

  factory GreenWaveState.empty() => GreenWaveState(
    distanceToNextLight: 0,
    secondsUntilGreen: 0,
    recommendedSpeedKmh: 0,
    statusText: "En attente du GPS...",
    isActive: false,
  );
}

/// Provider principal GreenWave : calcule vitesse idéale en temps réel
final greenWaveProvider = Provider<GreenWaveState>((ref) {
  final posAsync = ref.watch(locationStreamProvider);
  final lightsAsync = ref.watch(trafficLightsProvider);

  // Vitesse limite en ville
  const double speedLimit = 50.0;

  return posAsync.when(
    data: (position) {
      return lightsAsync.when(
        data: (lights) {
          if (lights.isEmpty) {
            return GreenWaveState(
              distanceToNextLight: 0,
              secondsUntilGreen: 0,
              recommendedSpeedKmh: speedLimit * 0.8,
              statusText: "Aucun feu détecté à proximité",
              isActive: false,
            );
          }

          // Trouver le feu le plus proche
          TrafficLight? nearest;
          double minDist = double.infinity;
          for (final light in lights) {
            final d = DistanceUtils.calculateDistance(
              position.latitude, position.longitude,
              light.latitude, light.longitude,
            );
            if (d < minDist) {
              minDist = d;
              nearest = light;
            }
          }

          if (nearest == null || minDist > 2000) {
            return GreenWaveState(
              distanceToNextLight: minDist,
              secondsUntilGreen: 0,
              recommendedSpeedKmh: speedLimit * 0.8,
              statusText: "Pas de feu dans les 2km",
              isActive: false,
            );
          }

          final now = DateTime.now();
          final secsUntilGreen = nearest.secondsUntilGreen(now);
          final isCurrentlyGreen = !nearest.isRedAt(now);

          // Calculer la vitesse conseillée
          final recommendedSpeed = GreenWaveCalculator.calculateTargetSpeed(
            minDist, secsUntilGreen, speedLimit,
          );

          // Générer le message d'alerte
          String statusText;
          if (isCurrentlyGreen) {
            final secsUntilRed = nearest.secondsUntilRed(now);
            // Vérifier si on peut passer avant le rouge
            final currentSpeed = position.speed * 3.6; // m/s -> km/h
            final timeToReach = currentSpeed > 0
                ? minDist / (currentSpeed / 3.6)
                : double.infinity;
            if (timeToReach <= secsUntilRed) {
              statusText = "Feu VERT ! Passez (rouge dans ${secsUntilRed}s)";
            } else {
              statusText = "Feu vert mais trop loin (${minDist.round()}m)";
            }
          } else {
            statusText = GreenWaveCalculator.formatAlert(
              recommendedSpeed, secsUntilGreen,
            );
            // Vibration haptic quand on se rapproche d'un feu rouge
            if (minDist < 200) {
              HapticFeedback.mediumImpact();
            }
          }

          return GreenWaveState(
            distanceToNextLight: minDist,
            secondsUntilGreen: secsUntilGreen,
            recommendedSpeedKmh: recommendedSpeed,
            statusText: statusText,
            isActive: true,
            isGreen: isCurrentlyGreen,
          );
        },
        loading: () => GreenWaveState(
          distanceToNextLight: 0,
          secondsUntilGreen: 0,
          recommendedSpeedKmh: 0,
          statusText: "Chargement des feux...",
          isActive: false,
        ),
        error: (e, _) => GreenWaveState(
          distanceToNextLight: 0,
          secondsUntilGreen: 0,
          recommendedSpeedKmh: 0,
          statusText: "Erreur données feux",
          isActive: false,
        ),
      );
    },
    loading: () => GreenWaveState.empty(),
    error: (_, __) => GreenWaveState(
      distanceToNextLight: 0,
      secondsUntilGreen: 0,
      recommendedSpeedKmh: 0,
      statusText: "Signal GPS indisponible",
      isActive: false,
    ),
  );
});
