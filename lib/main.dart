import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/controllers/auth_controller.dart';
import 'core/controllers/digitalizacion_controller.dart';
import 'core/controllers/map_controller.dart' as ctrl;
import 'ui/screens/login_screen.dart';
import 'ui/screens/map_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CartoDigitalApp());
}

class CartoDigitalApp extends StatelessWidget {
  const CartoDigitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (_) => ctrl.MapController()),
        ChangeNotifierProvider(create: (_) => DigitalizacionController()),
      ],
      child: MaterialApp(
        title: 'Carto Digital',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(),
      ),
    );
  }
}

/// Componente Guardia de Navegación que garantiza que el Login sea la primera pantalla
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isCheckingAuth) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/ine_logo.png',
                  width: 220,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(color: Color(0xFF4FC3F7)),
            ],
          ),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const MapScreen();
    }

    // Primera pantalla obligatoria si no hay sesión autenticada
    return const LoginScreen();
  }
}
