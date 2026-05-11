import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

// Provider pour le service Location
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

// StreamProvider qui gère les erreurs de permission proprement
// Retourne un stream vide si pas de permission, évite l'erreur GPS au démarrage
final locationStreamProvider = StreamProvider<Position>((ref) async* {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Services GPS désactivés - on attend sans rien émettre
    return;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return; // Pas de permission, stream vide (pas d'erreur)
    }
  }
  if (permission == LocationPermission.deniedForever) {
    return; // Permission refusée définitivement
  }

  // Permission accordée : on stream les positions
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // Mise à jour tous les 2m
    ),
  );
});

// Vitesse en km/h calculée depuis la dernière position GPS
final currentSpeedProvider = Provider<double>((ref) {
  final positionAsyncValue = ref.watch(locationStreamProvider);

  return positionAsyncValue.when(
    data: (position) {
      // position.speed est en m/s, on convertit en km/h
      final double speedKmh = position.speed * 3.6;
      return speedKmh < 0 ? 0.0 : speedKmh;
    },
    loading: () => 0.0,
    error: (_, __) => 0.0,
  );
});
