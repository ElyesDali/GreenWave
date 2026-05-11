import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../providers/greenwave_provider.dart';
import '../providers/location_provider.dart';

/// HUD flottant affichant la vitesse actuelle vs vitesse idéale GreenWave
/// avec alertes vocales et vibration haptic.
class HudScreen extends ConsumerStatefulWidget {
  const HudScreen({super.key});

  @override
  ConsumerState<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends ConsumerState<HudScreen> {
  final FlutterTts _tts = FlutterTts();
  String _lastSpokenAlert = '';
  DateTime _lastAlertTime = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  /// Parle l'alerte GreenWave (max 1 fois toutes les 8 secondes)
  void _speakAlert(String text) {
    final now = DateTime.now();
    if (text != _lastSpokenAlert ||
        now.difference(_lastAlertTime).inSeconds > 8) {
      _tts.speak(text);
      _lastSpokenAlert = text;
      _lastAlertTime = now;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = ref.watch(currentSpeedProvider);
    final gw = ref.watch(greenWaveProvider);

    // Déclencher alerte vocale si GreenWave actif et feu rouge détecté
    if (gw.isActive && gw.secondsUntilGreen > 0 && gw.distanceToNextLight < 500) {
      _speakAlert(gw.statusText);
    }

    // Couleur de la jauge selon l'écart vitesse actuelle / idéale
    Color gaugeColor() {
      if (!gw.isActive) return Colors.grey;
      if (gw.isGreen) return Colors.greenAccent;
      final diff = (currentSpeed - gw.recommendedSpeedKmh).abs();
      if (diff <= 5) return Colors.greenAccent;
      if (diff <= 12) return Colors.orangeAccent;
      return Colors.redAccent;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Card(
          elevation: 12,
          color: Colors.black.withAlpha(224),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ligne principale : vitesse actuelle → vitesse cible
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Vitesse actuelle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("VITESSE",
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                letterSpacing: 1.2)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              currentSpeed.round().toString(),
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: gaugeColor(),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Text("km/h",
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(width: 10),

                    // Flèche indicateur
                    Icon(Icons.arrow_forward, color: gaugeColor(), size: 22),

                    const SizedBox(width: 10),

                    // Vitesse cible GreenWave
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.greenAccent.withAlpha(76)),
                        ),
                        child: Column(
                          children: [
                            const Text("GREENWAVE",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    letterSpacing: 1.2)),
                            Text(
                              gw.isActive
                                  ? "${gw.recommendedSpeedKmh.round()} km/h"
                                  : "-- km/h",
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Barre de progression vitesse
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (currentSpeed / 130.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(gaugeColor()),
                    minHeight: 6,
                  ),
                ),

                const SizedBox(height: 10),

                // Alerte texte GreenWave + distance au feu
                Row(
                  children: [
                    Icon(
                      gw.isGreen
                          ? Icons.check_circle_outline
                          : gw.secondsUntilGreen > 0
                              ? Icons.traffic
                              : Icons.radio_button_unchecked,
                      color: gw.isGreen
                          ? Colors.greenAccent
                          : gw.secondsUntilGreen > 0
                              ? Colors.redAccent
                              : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gw.statusText,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (gw.isActive)
                      Text(
                        "${gw.distanceToNextLight.round()}m",
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
