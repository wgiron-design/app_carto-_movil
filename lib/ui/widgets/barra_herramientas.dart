import 'package:flutter/material.dart';
import '../../core/controllers/digitalizacion_controller.dart';
import '../../ui/theme/app_theme.dart';

/// Barra de herramientas de digitalización.
///
/// Se muestra en el lateral izquierdo del mapa (debajo de los botones de zoom).
/// Permite alternar entre modos: Navegar, Punto, Línea, Polígono.
/// Cuando hay una geometría en construcción, muestra controles de finalización.
class BarraHerramientas extends StatelessWidget {
  final DigitalizacionController digCtrl;

  const BarraHerramientas({super.key, required this.digCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: digCtrl,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Separador visual ──────────────────────────────────────────
            _Separador(),

            // ── Botones de modo ───────────────────────────────────────────
            _HerramientaBtn(
              icon: Icons.pan_tool_outlined,
              tooltip: 'Navegar (pan/zoom)',
              activo: digCtrl.modo == ModoDigitalizacion.navegar,
              color: AppTheme.onSurface,
              onTap: () => digCtrl.setModo(ModoDigitalizacion.navegar),
            ),

            const SizedBox(height: 4),

            _HerramientaBtn(
              icon: Icons.place_outlined,
              tooltip: 'Digitalizar Puntos (Estructuras)',
              activo: digCtrl.modo == ModoDigitalizacion.punto,
              color: const Color(0xFF4FC3F7), // Cian
              onTap: () => digCtrl.setModo(ModoDigitalizacion.punto),
            ),

            const SizedBox(height: 4),

            _HerramientaBtn(
              icon: Icons.polyline_outlined,
              tooltip: 'Digitalizar Líneas (Caminos)',
              activo: digCtrl.modo == ModoDigitalizacion.linea,
              color: const Color(0xFFFFB74D), // Naranja
              onTap: () => digCtrl.setModo(ModoDigitalizacion.linea),
            ),

            const SizedBox(height: 4),

            _HerramientaBtn(
              icon: Icons.pentagon_outlined,
              tooltip: 'Digitalizar Polígonos (UPM)',
              activo: digCtrl.modo == ModoDigitalizacion.poligono,
              color: const Color(0xFFFF00FF), // Fucsia
              onTap: () => digCtrl.setModo(ModoDigitalizacion.poligono),
            ),

            // ── Controles de construcción (cuando hay vértices) ───────────
            if (digCtrl.estaDigitalizando &&
                digCtrl.verticesEnConstruccion.isNotEmpty) ...[
              _Separador(),
              _buildControlesConstruccion(context),
            ],
          ],
        );
      },
    );
  }

  Widget _buildControlesConstruccion(BuildContext context) {
    final n = digCtrl.verticesEnConstruccion.length;
    final modoLabel = digCtrl.modo == ModoDigitalizacion.linea
        ? 'línea'
        : 'polígono';
    final minimoVerts = digCtrl.modo == ModoDigitalizacion.linea ? 2 : 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Contador de vértices
        Container(
          width: 36,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                '$n',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'pts',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Deshacer último vértice
        _HerramientaBtn(
          icon: Icons.undo,
          tooltip: 'Deshacer último vértice',
          activo: false,
          color: AppTheme.warning,
          size: 32,
          onTap: digCtrl.eliminarUltimoVertice,
        ),

        const SizedBox(height: 4),

        // Cancelar
        _HerramientaBtn(
          icon: Icons.close,
          tooltip: 'Cancelar $modoLabel',
          activo: false,
          color: AppTheme.error,
          size: 32,
          onTap: digCtrl.cancelar,
        ),

        const SizedBox(height: 4),

        // Instrucción
        Container(
          width: 36,
          padding: const EdgeInsets.all(4),
          child: Text(
            n < minimoVerts
                ? 'Min\n$minimoVerts'
                : '2×\ntap',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF546E7A),
              fontSize: 9,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _HerramientaBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool activo;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _HerramientaBtn({
    required this.icon,
    required this.tooltip,
    required this.activo,
    required this.color,
    required this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: activo ? color.withOpacity(0.2) : AppTheme.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: activo ? color : const Color(0xFF2D4054),
              width: activo ? 2 : 1,
            ),
            boxShadow: activo
                ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6)]
                : null,
          ),
          child: Icon(
            icon,
            size: size * 0.5,
            color: activo ? color : AppTheme.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: 36,
        height: 1,
        color: const Color(0xFF2D4054),
      ),
    );
  }
}
