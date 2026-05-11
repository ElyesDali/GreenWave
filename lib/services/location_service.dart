import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  Future<bool> requestPermissions() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      return true;
    }
    return false;
  }

  Future<Position?> getCurrentLocation() async {
    bool hasPermission = await requestPermissions();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
  }

  Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2, // Rafraîchir tous les 2 mètres
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "GreenWave GPS en cours d'utilisation",
          notificationTitle: "Localisation Active",
          enableWakeLock: true,
        ),
      ),
    );
  }
}
