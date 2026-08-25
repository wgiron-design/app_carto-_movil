import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import 'postgis_service.dart';

class AuthException implements Exception {
  final String message;
  final int statusCode;

  AuthException(this.message, {this.statusCode = 400});

  @override
  String toString() => message;
}

class AuthResult {
  final UserModel user;
  final String token;

  AuthResult({required this.user, required this.token});
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String get _baseUrl => PostGISService().baseUrl;

  Future<http.Response> _postWithAutoProbe(String path, Map<String, dynamic> body) async {
    Uri url = Uri.parse('$_baseUrl$path');
    try {
      return await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[AuthService] Falló conexión con $_baseUrl. Probando puertos/hosts alternativos...');
      final found = await PostGISService().probeAndFixBaseUrl();
      if (found) {
        url = Uri.parse('$_baseUrl$path');
        debugPrint('[AuthService] Reintentando petición en servidor encontrado: $url');
        return await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        ).timeout(const Duration(seconds: 8));
      }
      rethrow;
    }
  }

  Future<http.Response> _getWithAutoProbe(String path, String token) async {
    Uri url = Uri.parse('$_baseUrl$path');
    try {
      return await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AuthService] Falló conexión GET con $_baseUrl. Probando alternativas...');
      final found = await PostGISService().probeAndFixBaseUrl();
      if (found) {
        url = Uri.parse('$_baseUrl$path');
        return await http.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 5));
      }
      rethrow;
    }
  }

  /// Autentica usuario contra el backend PostgreSQL / FastAPI.
  Future<AuthResult> login(String username, String password) async {
    try {
      final response = await _postWithAutoProbe('/api/v1/auth/login', {
        'username': username.trim(),
        'password': password,
      });

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        final token = data['access_token'] as String;
        final user = UserModel.fromJson(data['user']);
        return AuthResult(user: user, token: token);
      } else {
        final detail = data['detail'] ?? 'Error de autenticación';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error de conexión durante login: $e');
      throw AuthException(
        'No se pudo conectar con el servidor backend en $_baseUrl.\n'
        'Asegúrese de haber ejecutado backend_python/levantar.bat'
      );
    }
  }

  /// Registra un nuevo usuario en la base de datos PostgreSQL.
  Future<UserModel> register(String username, String email, String password) async {
    try {
      final response = await _postWithAutoProbe('/api/v1/auth/register', {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
      });

      final data = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return UserModel.fromJson(data);
      } else {
        final detail = data['detail'] ?? 'Error al registrar usuario';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error de conexión durante registro: $e');
      throw AuthException(
        'No se pudo conectar con el servidor backend en $_baseUrl para registrar la cuenta.\n'
        'Verifique que el servidor uvicorn esté ejecutándose en backend_python (levantar.bat).'
      );
    }
  }

  /// Solicita recuperación de contraseña verificando match username + email.
  Future<String> forgotPassword(String username, String email) async {
    try {
      final response = await _postWithAutoProbe('/api/v1/auth/forgot-password', {
        'username': username.trim(),
        'email': email.trim(),
      });

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return data['message'] ?? 'Si los datos coinciden con nuestros registros, se enviará un correo de recuperación.';
      } else {
        final detail = data['detail'] ?? 'Error al procesar solicitud';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error en recuperación de contraseña: $e');
      throw AuthException('No se pudo conectar con el servidor backend en $_baseUrl.');
    }
  }

  Future<http.Response> _patchWithAutoProbe(String path, Map<String, dynamic> body, String token) async {
    Uri url = Uri.parse('$_baseUrl$path');
    try {
      return await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[AuthService] Falló conexión PATCH con $_baseUrl. Probando alternativas...');
      final found = await PostGISService().probeAndFixBaseUrl();
      if (found) {
        url = Uri.parse('$_baseUrl$path');
        return await http.patch(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(body),
        ).timeout(const Duration(seconds: 8));
      }
      rethrow;
    }
  }

  /// Obtiene los datos del perfil actual usando el token de sesión.
  Future<UserModel> getMe(String token) async {
    try {
      final response = await _getWithAutoProbe('/api/v1/auth/me', token);
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return UserModel.fromJson(data);
      } else {
        final detail = data['detail'] ?? 'Sesión inválida';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al validar sesión');
    }
  }

  /// Actualiza el nombre de usuario del usuario autenticado.
  Future<UserModel> updateUsername(String newUsername, String token) async {
    try {
      final response = await _patchWithAutoProbe(
        '/api/v1/auth/me/username',
        {'new_username': newUsername.trim()},
        token,
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return UserModel.fromJson(data);
      } else {
        final detail = data['detail'] ?? 'Error al actualizar nombre de usuario';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error al actualizar username: $e');
      throw AuthException('No se pudo conectar con el servidor para actualizar el nombre de usuario.');
    }
  }

  /// Actualiza el correo electrónico del usuario autenticado.
  Future<UserModel> updateEmail(String newEmail, String token) async {
    try {
      final response = await _patchWithAutoProbe(
        '/api/v1/auth/me/email',
        {'new_email': newEmail.trim()},
        token,
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return UserModel.fromJson(data);
      } else {
        final detail = data['detail'] ?? 'Error al actualizar correo electrónico';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error al actualizar email: $e');
      throw AuthException('No se pudo conectar con el servidor para actualizar el correo electrónico.');
    }
  }

  /// Actualiza la contraseña del usuario autenticado.
  Future<String> updatePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
    String token,
  ) async {
    try {
      final response = await _patchWithAutoProbe(
        '/api/v1/auth/me/password',
        {
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        },
        token,
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return data['message'] ?? 'Contraseña actualizada exitosamente.';
      } else {
        final detail = data['detail'] ?? 'Error al cambiar contraseña';
        throw AuthException(detail.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('[AuthService] Error al cambiar password: $e');
      throw AuthException('No se pudo conectar con el servidor para cambiar la contraseña.');
    }
  }
}
