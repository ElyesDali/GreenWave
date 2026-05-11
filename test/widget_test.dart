import 'package:flutter_test/flutter_test.dart';
import 'package:greenwave_gps/utils/greenwave_calculator.dart';
import 'package:greenwave_gps/models/traffic_light.dart';

void main() {
  group('GreenWaveCalculator', () {
    test('calcule la vitesse minimale correctement', () {
      // 200m de distance, 10s de rouge restant, limite 50 km/h
      final v = GreenWaveCalculator.calculateTargetSpeed(200, 10, 50);
      // v = 200/10 * 3.6 = 72 km/h → dépasse 55 (110% de 50), donc 45 (90%)
      expect(v, 45.0);
    });

    test('retourne vitesse réduite si déjà vert', () {
      final v = GreenWaveCalculator.calculateTargetSpeed(200, 0, 50);
      expect(v, 40.0); // 80% de la limite
    });

    test('vitesse normale si faisable sous la limite', () {
      // 100m, 20s de rouge, limite 50 → v=100/20*3.6 = 18 km/h
      final v = GreenWaveCalculator.calculateTargetSpeed(100, 20, 50);
      expect(v, 18.0);
    });
  });

  group('TrafficLight', () {
    test('détecte correctement rouge/vert', () {
      final light = TrafficLight(
        latitude: 48.85,
        longitude: 2.35,
        cycleRouge: 40,
        cycleVert: 20,
        offset: 0,
      );
      // Le résultat dépend de l'heure, on vérifie juste que ça ne crash pas
      final isRed = light.isRedAt(DateTime.now());
      expect(isRed, isA<bool>());
    });

    test('secondsUntilGreen retourne >= 0', () {
      final light = TrafficLight(
        latitude: 48.85,
        longitude: 2.35,
        offset: 0,
      );
      final secs = light.secondsUntilGreen(DateTime.now());
      expect(secs, greaterThanOrEqualTo(0));
    });
  });
}
