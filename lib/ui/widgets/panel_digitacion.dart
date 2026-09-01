import 'package:flutter/material.dart';
import '../../core/controllers/digitalizacion_controller.dart';
import '../theme/app_theme.dart';

/// Panel flotante de acciones para la digitación de líneas.
///
/// Contiene tres botones grandes:
/// - Azul: Agregar nodo en la posición actual del crosshair (centro del mapa)
/// - Rojo: Eliminar último nodo digitado
/// - Verde: Finalizar digitación y abrir formulario de atributos
class PanelDigitacion extends StatelessWidget {
  final DigitalizacionController digCtrl;
  final VoidCallback onAgregarNodo;
  final VoidCallback onFinalizar;

  const PanelDigitacion({
    super.key,
    required this.digCtrl,
    required this.onAgregarNodo,
    required this.onFinalizar,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: digCtrl,
      builder: (context, _) {
        final nVertices = digCtrl.verticesEnConstruccion.length;
        final puedeDeshacer = nVertices > 0;
        final puedeFinalizar = nVertices >= 2;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFB74D).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Contador de vértices ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$nVertices ${nVertices == 1 ? 'nodo' : 'nodos'}',
                  style: const TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Botones de acción ──
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botón: Agregar nodo (Azul)
                  _BotonAccion(
                    color: const Color(0xFF2196F3),
                    icon: Icons.add,
                    tooltip: 'Agregar nodo',
                    onPressed: onAgregarNodo,
                  ),

                  const SizedBox(width: 12),

                  // Botón: Eliminar último nodo (Rojo)
                  _BotonAccion(
                    color: const Color(0xFFEF5350),
                    icon: Icons.close,
                    tooltip: 'Eliminar último nodo',
                    enabled: puedeDeshacer,
                    onPressed: puedeDeshacer
                        ? digCtrl.eliminarUltimoVertice
                        : null,
                  ),

                  const SizedBox(width: 12),

                  // Botón: Finalizar (Verde)
                  _BotonAccion(
                    color: const Color(0xFF4CAF50),
                    icon: Icons.check,
                    tooltip: 'Guardar línea',
                    enabled: puedeFinalizar,
                    onPressed: puedeFinalizar ? onFinalizar : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BotonAccion extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  const _BotonAccion({
    required this.color,
    required this.icon,
    required this.tooltip,
    this.enabled = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : color.withOpacity(0.3);

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: effectiveColor,
            shape: BoxShape.circle,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: effectiveColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white38,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// Panel flotante para la edición de vértices de línea por drag
class PanelEdicionLinea extends StatelessWidget {
  final DigitalizacionController digCtrl;
  final VoidCallback onFinalizar;
  final VoidCallback onCancelar;

  const PanelEdicionLinea({
    super.key,
    required this.digCtrl,
    required this.onFinalizar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final enDrag = digCtrl.dragLineaActivo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            enDrag
                ? 'Moviendo vértice ${digCtrl.indiceDragLineaActivo! + 1}'
                : (digCtrl.modoAgregarVertice
                    ? '➕ Toca sobre un segmento para agregar vértice'
                    : 'Arrastra un nodo para moverlo'),
            style: TextStyle(
              color: digCtrl.modoAgregarVertice ? const Color(0xFF26C6DA) : const Color(0xFF4FC3F7),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                ),
                onPressed: onCancelar,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.white,
                ),
                onPressed: onFinalizar,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Finalizar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panel flotante para la edición de vértices de polígono por drag
class PanelEdicionPoligono extends StatelessWidget {
  final DigitalizacionController digCtrl;
  final VoidCallback onGuardarPoligono;
  final VoidCallback onCancelarEdicionCompleta;

  const PanelEdicionPoligono({
    super.key,
    required this.digCtrl,
    required this.onGuardarPoligono,
    required this.onCancelarEdicionCompleta,
  });

  @override
  Widget build(BuildContext context) {
    final enDrag = digCtrl.dragPoligonoActivo;
    final autoIntersecta = digCtrl.dragPoligonoAutoIntersecta;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (autoIntersecta ? AppTheme.error : const Color(0xFFFF00FF)).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            enDrag
                ? (autoIntersecta
                    ? '⚠️ Auto-intersección detectada'
                    : 'Moviendo vértice ${digCtrl.indiceDragPoligonoActivo! + 1}')
                : (digCtrl.modoAgregarVertice
                    ? '➕ Toca sobre un segmento para agregar vértice'
                    : 'Arrastra un nodo para moverlo'),
            style: TextStyle(
              color: autoIntersecta
                  ? AppTheme.error
                  : (digCtrl.modoAgregarVertice ? const Color(0xFF26C6DA) : const Color(0xFFFF00FF)),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                ),
                onPressed: onCancelarEdicionCompleta,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
                onPressed: onGuardarPoligono,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Guardar Polígono', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panel flotante para la edición de posición de punto por drag
class PanelEdicionPunto extends StatelessWidget {
  final DigitalizacionController digCtrl;
  final VoidCallback onFinalizar;
  final VoidCallback onCancelar;

  const PanelEdicionPunto({
    super.key,
    required this.digCtrl,
    required this.onFinalizar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final enDrag = digCtrl.dragPuntoActivo;
    final punto = digCtrl.idSeleccionado != null
        ? digCtrl.puntos.where((p) => p.id == digCtrl.idSeleccionado).firstOrNull
        : null;
    final nombre = (punto?.nombre.isNotEmpty == true) ? punto!.nombre : 'Estructura';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            enDrag ? 'Moviendo "$nombre"...' : 'Mover "$nombre"',
            style: const TextStyle(
              color: Color(0xFF4FC3F7),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Arrastra el punto o toca en el mapa la nueva ubicación',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                ),
                onPressed: onCancelar,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.white,
                ),
                onPressed: onFinalizar,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Confirmar Posición', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panel flotante para la digitación de un punto (Estructura) en la mira central
class PanelDigitacionPunto extends StatelessWidget {
  final VoidCallback onFijarPunto;
  final VoidCallback onCancelar;

  const PanelDigitacionPunto({
    super.key,
    required this.onFijarPunto,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Posicione la mira en la ubicación',
            style: TextStyle(
              color: Color(0xFF4FC3F7),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotonAccion(
                color: const Color(0xFFEF5350),
                icon: Icons.close,
                tooltip: 'Cancelar y salir del modo punto',
                onPressed: onCancelar,
              ),
              const SizedBox(width: 16),
              _BotonAccion(
                color: const Color(0xFF4CAF50),
                icon: Icons.check,
                tooltip: 'Fijar posición y abrir formulario',
                onPressed: onFijarPunto,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
