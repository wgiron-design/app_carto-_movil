import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import 'dialogo_cambio_password.dart';

/// Modal para visualización y edición de datos de cuenta de usuario.
class CuentaUsuarioModal extends StatefulWidget {
  const CuentaUsuarioModal({super.key});

  static Future<void> mostrar(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CuentaUsuarioModal(),
    );
  }

  @override
  State<CuentaUsuarioModal> createState() => _CuentaUsuarioModalState();
}

class _CuentaUsuarioModalState extends State<CuentaUsuarioModal> {
  bool _modoEdicion = false;
  bool _isSaving = false;
  String? _errorServidor;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().currentUser;
    _usernameCtrl = TextEditingController(text: user?.username ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Color _obtenerColorRol(String rol) {
    switch (rol.toLowerCase()) {
      case 'administrador':
      case 'admin':
        return const Color(0xFFEF5350); // Rojo
      case 'supervisor':
        return const Color(0xFFFFB74D); // Naranja
      case 'monitor':
        return const Color(0xFFAB47BC); // Púrpura
      case 'gerente':
        return const Color(0xFF26A69A); // Verde azulado
      case 'cartografo':
      default:
        return const Color(0xFF4FC3F7); // Azul cian
    }
  }

  String _obtenerIniciales(String username) {
    final limpio = username.trim();
    if (limpio.isEmpty) return 'U';
    if (limpio.length == 1) return limpio.toUpperCase();
    final partes = limpio.split(RegExp(r'[\s_.-]+'));
    if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    return limpio.substring(0, 2).toUpperCase();
  }

  String? _validarUsername(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El nombre de usuario es obligatorio.';
    if (v.length < 3) return 'Mínimo 3 caracteres.';
    if (v.length > 50) return 'Máximo 50 caracteres.';
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(v)) {
      return 'Solo letras, números, guiones (-), puntos (.) y guiones bajos (_).';
    }
    return null;
  }

  String? _validarEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El correo electrónico es obligatorio.';
    final emailRegExp = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegExp.hasMatch(v)) {
      return 'Ingresa un correo electrónico válido.';
    }
    return null;
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    final authCtrl = context.read<AuthController>();
    final user = authCtrl.currentUser;
    if (user == null) return;

    final nuevoUsername = _usernameCtrl.text.trim();
    final nuevoEmail = _emailCtrl.text.trim();

    final cambioUsername = nuevoUsername != user.username;
    final cambioEmail = nuevoEmail != user.email;

    if (!cambioUsername && !cambioEmail) {
      setState(() => _modoEdicion = false);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorServidor = null;
    });

    bool ok = true;

    if (cambioUsername) {
      ok = await authCtrl.updateUsername(nuevoUsername);
      if (!ok) {
        setState(() {
          _isSaving = false;
          _errorServidor = authCtrl.errorMessage ?? 'Error al actualizar nombre de usuario.';
        });
        return;
      }
    }

    if (cambioEmail) {
      ok = await authCtrl.updateEmail(nuevoEmail);
      if (!ok) {
        setState(() {
          _isSaving = false;
          _errorServidor = authCtrl.errorMessage ?? 'Error al actualizar correo electrónico.';
        });
        return;
      }
    }

    if (!mounted) return;

    setState(() {
      _isSaving = false;
      _modoEdicion = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Datos de cuenta actualizados exitosamente.'),
          ],
        ),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  Future<void> _confirmarCerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppTheme.warning),
            SizedBox(width: 8),
            Text('Cerrar Sesión', style: TextStyle(color: AppTheme.onSurface, fontSize: 16)),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas cerrar tu sesión actual?',
          style: TextStyle(color: AppTheme.onSurface),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      Navigator.of(context).pop(); // Cierra el modal
      context.read<AuthController>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authCtrl = context.watch<AuthController>();
    final user = authCtrl.currentUser;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: const BoxConstraints(maxWidth: 500),
      margin: EdgeInsets.only(
        top: 40,
        bottom: bottomInset > 0 ? bottomInset : 0,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF00BFA5).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Handle superior y botón de cierre ─────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF455A64),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF90A4AE), size: 20),
                      tooltip: 'Salir del formulario',
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Header con Avatar y Rol ──────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            _obtenerColorRol(user?.role ?? 'cartografo'),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _obtenerIniciales(user?.username ?? 'U'),
                          style: const TextStyle(
                            color: Color(0xFF003731),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      user?.username.isNotEmpty == true ? user!.username : 'Usuario',
                      style: const TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Badge de rol
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: _obtenerColorRol(user?.role ?? 'cartografo').withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _obtenerColorRol(user?.role ?? 'cartografo').withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        (user?.role ?? 'cartógrafo').toUpperCase(),
                        style: TextStyle(
                          color: _obtenerColorRol(user?.role ?? 'cartografo'),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Banner de error del servidor si aplica ───────────
              if (_errorServidor != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorServidor!,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Modo Lectura vs Modo Edición (AnimatedSwitcher) ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _modoEdicion
                    ? _buildModoEdicion(context)
                    : _buildModoLectura(context, user),
              ),

              const SizedBox(height: 16),

              // ── Opción: Cambiar Contraseña ───────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF2D4054),
                  ),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BFA5).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_outline, color: AppTheme.primary, size: 20),
                  ),
                  title: const Text(
                    'Cambiar Contraseña',
                    style: TextStyle(
                      color: AppTheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Actualizar contraseña de acceso',
                    style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF90A4AE)),
                  onTap: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const DialogoCambioPassword(),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // ── Opción: Cerrar Sesión ────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF2D4054),
                  ),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout, color: AppTheme.error, size: 20),
                  ),
                  title: const Text(
                    'Cerrar Sesión',
                    style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Salir de la cuenta en este dispositivo',
                    style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                  ),
                  onTap: _confirmarCerrarSesion,
                ),
              ),

              const SizedBox(height: 16),

              // ── Botón: Salir del Formulario ──────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.onSurface,
                    side: const BorderSide(color: Color(0xFF455A64), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: AppTheme.surfaceVariant.withValues(alpha: 0.3),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18, color: Color(0xFF90A4AE)),
                  label: const Text(
                    'Salir del Formulario',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModoLectura(BuildContext context, dynamic user) {
    return Container(
      key: const ValueKey('modo_lectura'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2D4054)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DATOS DE LA CUENTA',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 20),
                tooltip: 'Editar datos',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _errorServidor = null;
                    _usernameCtrl.text = user?.username ?? '';
                    _emailCtrl.text = user?.email ?? '';
                    _modoEdicion = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Campo: Username
          _buildDatoLectura(
            icon: Icons.person_outline,
            label: 'Nombre de usuario',
            valor: user?.username ?? 'No disponible',
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF2D4054)),
          const SizedBox(height: 12),

          // Campo: Email
          _buildDatoLectura(
            icon: Icons.email_outlined,
            label: 'Correo electrónico',
            valor: user?.email ?? 'No disponible',
          ),
        ],
      ),
    );
  }

  Widget _buildDatoLectura({
    required IconData icon,
    required String label,
    required String valor,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF90A4AE), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF78909C), fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModoEdicion(BuildContext context) {
    return Container(
      key: const ValueKey('modo_edicion'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: AppTheme.primary, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Editar Datos de Cuenta',
                  style: TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Username
            const Text(
              'Nombre de usuario',
              style: TextStyle(color: AppTheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _usernameCtrl,
              enabled: !_isSaving,
              validator: _validarUsername,
              decoration: const InputDecoration(
                hintText: 'Ingresa tu nombre de usuario',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),

            const SizedBox(height: 14),

            // 2. Email
            const Text(
              'Correo electrónico',
              style: TextStyle(color: AppTheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              enabled: !_isSaving,
              keyboardType: TextInputType.emailAddress,
              validator: _validarEmail,
              decoration: const InputDecoration(
                hintText: 'ejemplo@correo.com',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
            ),

            const SizedBox(height: 20),

            // Botones Guardar / Cancelar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB0BEC5),
                      side: const BorderSide(color: Color(0xFF455A64)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isSaving ? null : () => setState(() => _modoEdicion = false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: const Color(0xFF003731),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isSaving ? null : _guardarCambios,
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF003731),
                            ),
                          )
                        : const Text(
                            'Guardar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
