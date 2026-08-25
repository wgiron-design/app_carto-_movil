import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class DialogoCambioPassword extends StatefulWidget {
  const DialogoCambioPassword({super.key});

  @override
  State<DialogoCambioPassword> createState() => _DialogoCambioPasswordState();
}

class _DialogoCambioPasswordState extends State<DialogoCambioPassword> {
  final _formKey = GlobalKey<FormState>();
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _isSaving = false;
  String? _errorServidor;

  @override
  void initState() {
    super.initState();
    _newPwdCtrl.addListener(() => setState(() {}));
    _confirmPwdCtrl.addListener(() => setState(() {}));
    _currentPwdCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  bool get _cumpleLongitudMinima => _newPwdCtrl.text.length >= 5;
  bool get _coincideConfirmacion =>
      _newPwdCtrl.text.isNotEmpty && _newPwdCtrl.text == _confirmPwdCtrl.text;
  bool get _tienePasswordActual => _currentPwdCtrl.text.trim().isNotEmpty;
  bool get _formularioValido =>
      _cumpleLongitudMinima && _coincideConfirmacion && _tienePasswordActual;

  Future<void> _cambiarPassword() async {
    if (!_formularioValido || _isSaving) return;

    setState(() {
      _isSaving = true;
      _errorServidor = null;
    });

    final authCtrl = context.read<AuthController>();
    final success = await authCtrl.updatePassword(
      _currentPwdCtrl.text,
      _newPwdCtrl.text,
      _confirmPwdCtrl.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  authCtrl.successMessage ?? 'Contraseña actualizada exitosamente.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() {
        _isSaving = false;
        _errorServidor = authCtrl.errorMessage ?? 'No se pudo actualizar la contraseña.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00BFA5).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.lock_reset, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cambiar Contraseña',
                            style: TextStyle(
                              color: AppTheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Actualiza tu clave de acceso',
                            style: TextStyle(
                              color: Color(0xFF90A4AE),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF90A4AE), size: 20),
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── Contenido / Formulario ──────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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

                      // 1. Contraseña Actual
                      const Text(
                        'Contraseña Actual',
                        style: TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _currentPwdCtrl,
                        obscureText: _obscureCurrent,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          hintText: 'Ingresa tu contraseña actual',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: const Color(0xFF90A4AE),
                            ),
                            onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 2. Nueva Contraseña
                      const Text(
                        'Nueva Contraseña',
                        style: TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _newPwdCtrl,
                        obscureText: _obscureNew,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          hintText: 'Mínimo 5 caracteres',
                          prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNew ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: const Color(0xFF90A4AE),
                            ),
                            onPressed: () => setState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Indicador en vivo de longitud
                      Row(
                        children: [
                          Icon(
                            _cumpleLongitudMinima ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 14,
                            color: _cumpleLongitudMinima
                                ? AppTheme.success
                                : (_newPwdCtrl.text.isNotEmpty ? AppTheme.error : const Color(0xFF78909C)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Mínimo 5 caracteres (${_newPwdCtrl.text.length}/5)',
                            style: TextStyle(
                              fontSize: 12,
                              color: _cumpleLongitudMinima
                                  ? AppTheme.success
                                  : (_newPwdCtrl.text.isNotEmpty ? AppTheme.error : const Color(0xFF78909C)),
                              fontWeight: _cumpleLongitudMinima ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // 3. Confirmar Nueva Contraseña
                      const Text(
                        'Confirmar Nueva Contraseña',
                        style: TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmPwdCtrl,
                        obscureText: _obscureConfirm,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          hintText: 'Repite la nueva contraseña',
                          prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: const Color(0xFF90A4AE),
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Indicador en vivo de coincidencia
                      if (_confirmPwdCtrl.text.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              _coincideConfirmacion ? Icons.check_circle : Icons.cancel,
                              size: 14,
                              color: _coincideConfirmacion ? AppTheme.success : AppTheme.error,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _coincideConfirmacion ? 'Las contraseñas coinciden' : 'Las contraseñas no coinciden',
                              style: TextStyle(
                                fontSize: 12,
                                color: _coincideConfirmacion ? AppTheme.success : AppTheme.error,
                                fontWeight: _coincideConfirmacion ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 24),

                      // Botones de acción
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFB0BEC5),
                                side: const BorderSide(color: Color(0xFF455A64)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: const Color(0xFF003731),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                              ),
                              onPressed: _formularioValido && !_isSaving ? _cambiarPassword : null,
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
                                      'Guardar Clave',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
