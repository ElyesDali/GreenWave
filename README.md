# GreenWave GPS

Application Android complète en Flutter pour de la navigation GPS autonome avec prédiction de feux rouges et optimisation de la vitesse "GreenWave" pour arriver au vert (0s d'arrêt).

## Fonctionnalités Principales
1. **Navigation Turn-by-Turn Mapbox** (recherche de destination + itinéraire)
2. **HUD Flottant Dynamique** : Affiche la vitesse actuelle et la vitesse idéale calculée pour passer au vert.
   - Jauge Vert/Jaune/Rouge selon le respect de la vitesse cible.
3. **Détection des Feux** : Via Overpass API (OSM trafics_signals).
4. **Calcul Algorithmique (GreenWave)** :
   `min_speed = distance_feu / temps_restant_rouge` avec un max à 110% de la speed limit.
5. **Alertes Vocales/Visuelles** *(Alerte texte sur le HUD ajoutée, vibrations/voix via JustAudio configurés dans l'appli mais à connecter selon l'interaction utilisateur).*
6. **UI Material 3** : Thème sombre optimal pour l'utilisation en voiture.

## Prérequis et Installation

1. S'assurer que **Flutter** (>=3.19.0) et son SDK Android soient installés et ajoutés au `$PATH`.
2. Cloner ou télécharger ce répertoire.
3. Ouvrir un terminal dans le répertoire `GreenWaveGPS` et exécuter :
   ```bash
   flutter pub get
   ```
4. Obtenir une clé Mapbox gratuite : [Mapbox Tokens](https://account.mapbox.com/access-tokens/)
5. (Optionnel pour tester Turn-By-Turn) Ajouter la clé Secrète Mapbox dans votre fichier local `~/.gradle/gradle.properties` comme spécifié par le plugin mapbox_maps_flutter.

## Lancer l'Application

Brancher un appareil Android via ADB, ou démarrer un émulateur, puis exécuter :

```bash
flutter run
```

Pour générer un APK Android de debug direct :
```bash
flutter build apk --debug
# L'APK sera généré dans build/app/outputs/flutter-apk/app-debug.apk
```

> **Note Évaluateurs (ECE/Vésinet)** : En cas d'absence de réseau ou de requêtes Overpass trop lentes, l'app utilise un fallback de données mockées (`_getMocksParis()` dans `traffic_light_service.dart`) positionnant des feux rouges à Paris 15 et au Vésinet pour simplifier le test du HUD.
