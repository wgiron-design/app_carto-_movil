import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isCheckingAuth = true;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  UserModel? _currentUser;
  String? _token;
  String? _errorMessage;
  String? _successMessage;

  bool get isCheckingAuth => _isCheckingAuth;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  /// UUID del usuario actualmente autenticado (null si no hay sesión)
  String? get currentUserId => _currentUser?.id;

  /// Identificador único e inmutable del dispositivo móvil.
  /// Se genera en el primer login y persiste en SharedPreferences.
  String? _deviceId;
  String? get deviceId => _deviceId;

  bool get isInactiveUserError =>
      _errorMessage != null && _errorMessage!.toLowerCase().contains('usuario inactivo');

  AuthController() {
    _initAuth();
  }

  Future<void> _initAuth() async {
    _isCheckingAuth = true;
    notifyListeners();

    // Cargar device_id persistido (si existe)
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    // En inicio, por seguridad no hay sesión activa por defecto hasta que el usuario se loguee
    _isAuthenticated = false;
    _currentUser = null;
    _isCheckingAuth = false;
    notifyListeners();
  }

  /// Genera y persiste un UUID de dispositivo único la primera vez que se llama.
  Future<void> _initDeviceId() async {
    if (_deviceId != null) return;
    const uuid = Uuid();
    _deviceId = uuid.v4();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', _deviceId!);
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final result = await _authService.login(username, password);
      _currentUser = result.user;
      _token = result.token;
      _isAuthenticated = true;
      // Asegurar que el device_id esté inicializado en el primer login
      await _initDeviceId();
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isAuthenticated = false;
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Ocurrió un error insospechado durante el inicio de sesión.';
      _isAuthenticated = false;
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final user = await _authService.register(username, email, password);
      _successMessage = '¡Registro exitoso! Ya puedes iniciar sesión con tu cuenta.';
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error insospechado durante el registro.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword(String username, String email) async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final msg = await _authService.forgotPassword(username, email);
      _successMessage = msg;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error insospechado al procesar la solicitud.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateUsername(String newUsername) async {
    if (_token == null) {
      _errorMessage = 'Sesión no válida o expirada.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final updatedUser = await _authService.updateUsername(newUsername, _token!);
      _currentUser = updatedUser;
      _successMessage = 'Nombre de usuario actualizado exitosamente.';
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error inesperado al actualizar el nombre de usuario.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateEmail(String newEmail) async {
    if (_token == null) {
      _errorMessage = 'Sesión no válida o expirada.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final updatedUser = await _authService.updateEmail(newEmail, _token!);
      _currentUser = updatedUser;
      _successMessage = 'Correo electrónico actualizado exitosamente.';
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error inesperado al actualizar el correo electrónico.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    if (_token == null) {
      _errorMessage = 'Sesión no válida o expirada.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final msg = await _authService.updatePassword(
        currentPassword,
        newPassword,
        confirmPassword,
        _token!,
      );
      _successMessage = msg;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error inesperado al cambiar la contraseña.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _currentUser = null;
    _token = null;
    _isAuthenticated = false;
    _errorMessage = null;
    _successMessage = null;
    // No se resetea _deviceId: el identificador de dispositivo persiste entre sesiones
    notifyListeners();
  }
}
