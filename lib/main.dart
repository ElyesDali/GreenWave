import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation du jeton Mapbox. (À replacer par votre vraie clé depuis un env ou direct)
  MapboxOptions.setAccessToken("pk.eyJ1IjoiY3JpcHRvcmUiLCJhIjoiY21tdDFnNGM1MW5lbTJxc2Q4bzl2OHVtbCJ9.wrN_jj90xlFf9JkrBalinQ"); // User provided token

  runApp(
    const ProviderScope(
      child: GreenWaveApp(),
    ),
  );
}

class GreenWaveApp extends StatelessWidget {
  const GreenWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GreenWave GPS',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.lightGreenAccent,
          surface: Colors.black87,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          bodyLarge: TextStyle(color: Colors.white),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
