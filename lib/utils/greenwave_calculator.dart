class GreenWaveCalculator {
  /// Calcule la vitesse minimale requise pour arriver au feu lorsqu'il passe au vert.
  /// Formule: v_mini = distance / temps_restant_rouge
  static double calculateTargetSpeed(
    double distanceToNextLight, 
    int remainingRedTime, 
    double speedLimit
  ) {
    if (remainingRedTime <= 0) {
      // Si c'est déjà vert, on recommande de maintenir une vitesse normale (ex: 80% de la speedlimit)
      return speedLimit * 0.8;
    }

    // Calcul de la vitesse minimale en mètres / seconde, puis conversion en km/h (* 3.6)
    double vMiniMs = distanceToNextLight / remainingRedTime;
    double vMiniKmh = vMiniMs * 3.6;

    // Safety check comme mentionné dans l'énoncé:
    // Si la vitesse minimale requise dépasse 110% de la limite, on force à 90%
    if (vMiniKmh > speedLimit * 1.1) {
      return speedLimit * 0.9;
    }

    return vMiniKmh;
  }
  
  /// Formate et détermine l'alerte à jouer pour l'utilisateur
  static String formatAlert(double vMini, int remainingRedTime) {
    int roundedV = vMini.round();
    return "Maintiens ${roundedV}km/h → vert dans ${remainingRedTime}s";
  }
}
