/// Modèle représentant un feu tricolore avec son cycle rouge/vert simulé.
class TrafficLight {
  final double latitude;
  final double longitude;
  final int cycleRouge; // Durée phase rouge en secondes (défaut 40s)
  final int cycleVert;  // Durée phase verte en secondes (défaut 20s)
  final int offset;     // Décalage temporel dans le cycle (simule désynchronisation)

  TrafficLight({
    required this.latitude,
    required this.longitude,
    this.cycleRouge = 40,
    this.cycleVert = 20,
    int? offset,
  }) : offset = offset ?? (latitude * 1000 + longitude * 1000).toInt().abs() % 60;

  /// Durée totale d'un cycle complet (rouge + vert)
  int get cycleDuration => cycleRouge + cycleVert;

  /// Vérifie si le feu est rouge à un instant T donné
  bool isRedAt(DateTime time) {
    final secondInCycle = _secondInCycle(time);
    return secondInCycle < cycleRouge;
  }

  /// Retourne le nombre de secondes avant le passage au vert (0 si déjà vert)
  int secondsUntilGreen(DateTime time) {
    final secondInCycle = _secondInCycle(time);
    if (secondInCycle < cycleRouge) {
      return cycleRouge - secondInCycle;
    }
    return 0;
  }

  /// Retourne le nombre de secondes avant passage au rouge (0 si déjà rouge)
  int secondsUntilRed(DateTime time) {
    final secondInCycle = _secondInCycle(time);
    if (secondInCycle >= cycleRouge) {
      return cycleDuration - secondInCycle;
    }
    return 0;
  }

  int _secondInCycle(DateTime time) {
    return (time.millisecondsSinceEpoch ~/ 1000 + offset) % cycleDuration;
  }

  /// Construit depuis un noeud OSM (Overpass API)
  factory TrafficLight.fromOsmJson(Map<String, dynamic> json) {
    return TrafficLight(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
    );
  }

  /// Construit depuis le cache JSON local (mock_data)
  factory TrafficLight.fromJson(Map<String, dynamic> json) {
    return TrafficLight(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      cycleRouge: json['cycleRouge'] ?? 40,
      cycleVert: json['cycleVert'] ?? 20,
      offset: json['offset'],
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'cycleRouge': cycleRouge,
    'cycleVert': cycleVert,
    'offset': offset,
  };
}
