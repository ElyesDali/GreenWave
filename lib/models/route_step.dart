class RouteStep {
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final double distance; // Distance in meters
  final String instruction; // Turn instruction, e.g., "Tournez à droite"

  RouteStep({
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.distance,
    required this.instruction,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    // Mapbox route step format is relatively complex, adapting for standard structure.
    return RouteStep(
      startLat: json['maneuver']['location'][1].toDouble(),
      startLng: json['maneuver']['location'][0].toDouble(),
      endLat: 0.0, // Should be computed dynamically based on geometry
      endLng: 0.0,
      distance: json['distance'].toDouble(),
      instruction: json['maneuver']['instruction'] ?? "",
    );
  }
}
