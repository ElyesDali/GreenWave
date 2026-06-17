import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/greenwave_provider.dart';
import '../services/navigation_service.dart';
import '../models/traffic_light.dart';
import 'hud_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MapboxMap? _mapboxMap;
  final TextEditingController _searchController = TextEditingController();
  bool _permissionsGranted = false;
  List<GeocodingResult> _searchResults = [];
  bool _showSearchResults = false;
  bool _routeActive = false;
  Timer? _trafficLightsTimer;
  bool _isDrawingLights = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // 1. On vérifie si le GPS physique est allumé
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _permissionsGranted = false);
      return;
    }

    // 2. On vérifie l'état de la permission
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    
    // 3. Si c'est refusé ou non demandé, on lance la popup iOS
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    // 4. On valide si on a "Lorsque l'app est active" OU "Toujours"
    if (mounted) {
      setState(() {
        _permissionsGranted = (permission == geo.LocationPermission.whileInUse || 
                               permission == geo.LocationPermission.always);
      });
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    // Activer la couche de localisation utilisateur
    mapboxMap.location.updateSettings(
      LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );
  }

  /// Recherche d'adresse via Mapbox Geocoding
  Future<void> _onSearch(String query) async {
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    final nav = ref.read(navigationServiceProvider);
    try {
      final results = await nav.geocode(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showSearchResults = results.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint("Erreur geocoding: $e");
      // On affiche l'erreur directement sur l'écran de l'iPhone !
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erreur recherche : $e", 
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// L'utilisateur sélectionne une destination
  Future<void> _selectDestination(GeocodingResult result) async {
    setState(() {
      _showSearchResults = false;
      _searchController.text = result.name;
    });
    FocusScope.of(context).unfocus();

    // Mettre à jour le provider de destination
    ref.read(destinationProvider.notifier).state = result;

    // Calculer et afficher la route
    try {
      final pos = await geo.Geolocator.getCurrentPosition();
      final nav = ref.read(navigationServiceProvider);
      final route = await nav.getRoute(
        pos.latitude, pos.longitude,
        result.latitude, result.longitude,
      );

      if (route != null && _mapboxMap != null) {
        await _drawRoute(route);
        await _addDestinationMarker(result);

        // Calcul de la zone couverte par la route
        final bounds = _calculateBounds(route.routeCoordinates);
        final centerLat = (bounds[1] + bounds[3]) / 2;
        final centerLon = (bounds[0] + bounds[2]) / 2;
        
        // Rayon approximatif en kilomètres
        final dLat = (bounds[3] - bounds[1]) * 111.0;
        final dLon = (bounds[2] - bounds[0]) * 78.5;
        double radiusKm = math.sqrt(dLat*dLat + dLon*dLon) / 2.0;
        if (radiusKm < 2.0) radiusKm = 2.0;
        if (radiusKm > 50.0) radiusKm = 50.0; // Limite pour l'API
        
        // Afficher tous les feux tricolores de la zone
        final service = ref.read(trafficLightServiceProvider);
        final allLights = await service.fetchTrafficLights(centerLat, centerLon, radiusKm: radiusKm);
        
        await _drawTrafficLights(allLights);
        _startTrafficLightsTimer(allLights);

        // Zoomer pour voir toute la route
        _mapboxMap!.setCamera(CameraOptions(
          center: Point(coordinates: Position(
            centerLon,
            centerLat,
          )),
          zoom: 12.0,
        ));

        setState(() => _routeActive = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur calcul itinéraire: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Dessine la route sur la carte via GeoJSON source + line layer
  Future<void> _drawRoute(RouteResult route) async {
    final map = _mapboxMap!;

    // Supprimer l'ancienne route si elle existe
    try {
      await map.style.removeStyleLayer('route-layer');
      await map.style.removeStyleSource('route-source');
    } catch (_) {}

    // GeoJSON de la route
    final geoJson = json.encode({
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': route.routeCoordinates,
      },
    });

    await map.style.addSource(GeoJsonSource(
      id: 'route-source',
      data: geoJson,
    ));

    await map.style.addLayer(LineLayer(
      id: 'route-layer',
      sourceId: 'route-source',
      lineColor: Colors.greenAccent.toARGB32(),
      lineWidth: 5.0,
      lineOpacity: 0.85,
    ));
  }

  // Suppression de _filterLightsOnRoute

  /// Démarre le timer pour rafraichir la couleur des feux en temps réel
  void _startTrafficLightsTimer(List<TrafficLight> lights) {
    _trafficLightsTimer?.cancel();
    _trafficLightsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _routeActive && _mapboxMap != null) {
        _drawTrafficLights(lights);
      }
    });
  }

  /// Génère et affiche les feux tricolores réels
  Future<void> _drawTrafficLights(List<TrafficLight> lights) async {
    if (lights.isEmpty || _isDrawingLights) return;
    _isDrawingLights = true;
    final map = _mapboxMap!;

    try {
      // 1. Nettoyage des anciens feux
      try {
        await map.style.removeStyleLayer('red-lights-layer');
        await map.style.removeStyleLayer('green-lights-layer');
        await map.style.removeStyleSource('red-lights-source');
        await map.style.removeStyleSource('green-lights-source');
      } catch (_) {}

      List<Map<String, dynamic>> redFeatures = [];
      List<Map<String, dynamic>> greenFeatures = [];
      final now = DateTime.now();

      // 2. On trie les feux en fonction de leur état actuel
      for (final light in lights) {
        final isRed = light.isRedAt(now);
        
        final feature = {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [light.longitude, light.latitude]
          }
        };

        if (isRed) {
          redFeatures.add(feature);
        } else {
          greenFeatures.add(feature);
        }
      }

      // 3. Création du calque des feux ROUGES
      if (redFeatures.isNotEmpty) {
        await map.style.addSource(GeoJsonSource(
          id: 'red-lights-source',
          data: json.encode({'type': 'FeatureCollection', 'features': redFeatures}),
        ));
        await map.style.addLayer(CircleLayer(
          id: 'red-lights-layer',
          sourceId: 'red-lights-source',
          circleRadius: 7.0,
          circleColor: Colors.redAccent.toARGB32(),
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.0,
        ));
      }

      // 4. Création du calque des feux VERTS
      if (greenFeatures.isNotEmpty) {
        await map.style.addSource(GeoJsonSource(
          id: 'green-lights-source',
          data: json.encode({'type': 'FeatureCollection', 'features': greenFeatures}),
        ));
        await map.style.addLayer(CircleLayer(
          id: 'green-lights-layer',
          sourceId: 'green-lights-source',
          circleRadius: 7.0,
          circleColor: Colors.greenAccent.toARGB32(),
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.0,
        ));
      }
    } finally {
      _isDrawingLights = false;
    }
  }

// Rien, remplacé plus haut

  /// Ajoute un marqueur cercle à la destination
  Future<void> _addDestinationMarker(GeocodingResult dest) async {
    final map = _mapboxMap!;

    try {
      await map.style.removeStyleLayer('dest-layer');
      await map.style.removeStyleSource('dest-source');
    } catch (_) {}

    final geoJson = json.encode({
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [dest.longitude, dest.latitude],
      },
    });

    await map.style.addSource(GeoJsonSource(
      id: 'dest-source',
      data: geoJson,
    ));

    await map.style.addLayer(CircleLayer(
      id: 'dest-layer',
      sourceId: 'dest-source',
      circleColor: Colors.redAccent.toARGB32(),
      circleRadius: 10.0,
      circleStrokeColor: Colors.white.toARGB32(),
      circleStrokeWidth: 2.0,
    ));
  }

  /// Calcule les bornes [minLon, minLat, maxLon, maxLat] d'une liste de coords
  List<double> _calculateBounds(List<List<double>> coords) {
    double minLon = 180, minLat = 90, maxLon = -180, maxLat = -90;
    for (final c in coords) {
      if (c[0] < minLon) minLon = c[0];
      if (c[0] > maxLon) maxLon = c[0];
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
    }
    return [minLon, minLat, maxLon, maxLat];
  }

  /// Annule la navigation en cours
  /// Annule la navigation en cours
  void _cancelRoute() async {
    _trafficLightsTimer?.cancel();
    _trafficLightsTimer = null;
    ref.read(destinationProvider.notifier).state = null;
    try {
      await _mapboxMap?.style.removeStyleLayer('route-layer');
      await _mapboxMap?.style.removeStyleSource('route-source');
      await _mapboxMap?.style.removeStyleLayer('dest-layer');
      await _mapboxMap?.style.removeStyleSource('dest-source');
      
      // AJOUTE CES 4 LIGNES :
      await _mapboxMap?.style.removeStyleLayer('red-lights-layer');
      await _mapboxMap?.style.removeStyleSource('red-lights-source');
      await _mapboxMap?.style.removeStyleLayer('green-lights-layer');
      await _mapboxMap?.style.removeStyleSource('green-lights-source');
    } catch (_) {}
    setState(() {
// ...
      _routeActive = false;
      _searchController.clear();
    });
  }

  @override
  void dispose() {
    _trafficLightsTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Carte Mapbox plein écran (thème sombre)
          Positioned.fill(
            child: MapWidget(
              key: const ValueKey("mapWidget"),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(2.3488, 48.8534)),
                zoom: 13.0,
              ),
            ),
          ),

          // Barre de recherche + résultats
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    // Champ de recherche
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(128),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          const Icon(Icons.search, color: Colors.greenAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: "Rechercher une destination...",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 14),
                              ),
                              onChanged: _onSearch,
                              onSubmitted: _onSearch,
                            ),
                          ),
                          if (_routeActive)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: _cancelRoute,
                            ),
                        ],
                      ),
                    ),

                    // Liste résultats geocoding
                    if (_showSearchResults)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => Divider(
                            color: Colors.white.withAlpha(25),
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final r = _searchResults[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place,
                                  color: Colors.greenAccent, size: 20),
                              title: Text(
                                r.name,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectDestination(r),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bannière permission GPS manquante
          if (!_permissionsGranted)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(230),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.location_off, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Acceptez la localisation pour activer GreenWave",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Infos route active (distance + temps + statut GreenWave)
          if (_routeActive)
            Positioned(
              top: 110,
              left: 16,
              right: 16,
              child: Consumer(builder: (context, ref, _) {
                final route = ref.watch(activeRouteProvider);
                return route.when(
                  data: (r) {
                    if (r == null) return const SizedBox.shrink();
                    final km = (r.distanceMeters / 1000).toStringAsFixed(1);
                    final min = (r.durationSeconds / 60).round();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.greenAccent.withAlpha(76)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _routeInfoChip(Icons.straighten, "$km km"),
                          _routeInfoChip(Icons.timer, "$min min"),
                          _routeInfoChip(Icons.traffic, "GreenWave"),
                        ],
                      ),
                    );
                  },
                  loading: () => const LinearProgressIndicator(
                      color: Colors.greenAccent),
                  error: (_, __) => const SizedBox.shrink(),
                );
              }),
            ),

          // HUD GreenWave en bas
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HudScreen(),
          ),
        ],
      ),

      // Bouton recentrer position
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 180),
        child: FloatingActionButton(
          onPressed: () async {
            try {
              final pos = await geo.Geolocator.getCurrentPosition();
              _mapboxMap?.setCamera(CameraOptions(
                center: Point(
                    coordinates: Position(pos.longitude, pos.latitude)),
                zoom: 15.0,
              ));
            } catch (e) {
              debugPrint("Erreur GPS: $e");
            }
          },
          backgroundColor: Colors.black87,
          child: const Icon(Icons.my_location, color: Colors.greenAccent),
        ),
      ),
    );
  }

  Widget _routeInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.greenAccent, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
