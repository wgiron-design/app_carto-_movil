import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/map_controller.dart' as ctrl;
import '../../core/controllers/digitalizacion_controller.dart';
import '../../core/models/proyecto_cartografico.dart';
import '../../core/models/imagen_calibrada.dart';
import '../../core/models/capa_geometrica.dart';
import '../../core/models/resultado_seleccion.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/services/postgis_service.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/dialogo_calibracion.dart';
import '../../ui/widgets/barra_herramientas.dart';
import '../../ui/widgets/dialogos_atributos.dart';
import '../../ui/widgets/cursor_crosshair.dart';
import '../../ui/widgets/panel_digitacion.dart';
import '../../ui/widgets/snap_indicator.dart';
import 'jerarquia_screen.dart';
import 'nivel_lista_screen.dart';

/// Pantalla principal del visor de mapas (Pasos 2 + 3).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Controlador nativo de flutter_map
  final MapController _flutterMapCtrl = MapController();

  // Estado local de UI
  bool _mostrarPanelCapas = true;
  LatLng? _coordsCursor;
  double _zoomActual = 10.0;
  bool _guardando = false;
  bool _cargando = false;
  /// Controla si el botón ℹ️ está activo (mostrar info al tocar elementos)
  bool _modoInfoActivo = false;
  /// Catálogo de tipos (Formal/Referencia) cargado al iniciar.
  /// Se pasa al DialogoAtributosPunto para evitar llamadas extra al abrir el diálogo.
  List<CatalogoItem> _tiposCatalogo = const [];

  @override
  void initState() {
    super.initState();
    // Restaurar zoom inicial del controlador si existe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapCtrl = context.read<ctrl.MapController>();
      setState(() => _zoomActual = mapCtrl.zoom);
      
      // Cargar geometrías desde PostGIS con fallback automático a SQLite local
      context.read<DigitalizacionController>().cargarDesdePostGIS();

      // Precargar catálogo de tipos para el combo dependiente del formulario
      _cargarTiposCatalogo();
    });
  }

  /// Carga el catálogo de tipos de estructura una vez al iniciar la pantalla.
  /// El resultado se almacena en [_tiposCatalogo] y se pasa a [DialogoAtributosPunto].
  Future<void> _cargarTiposCatalogo() async {
    try {
      final svc = PostGISService();
      final uri = Uri.parse('${svc.baseUrl}/api/capas/catalogos/estructuras/tipos');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && mounted) {
        final lista = (jsonDecode(resp.body) as List)
            .map((e) => CatalogoItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _tiposCatalogo = lista);
      }
    } catch (e) {
      debugPrint('[MapScreen] No se pudo cargar catálogo de tipos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ctrl.MapController, DigitalizacionController>(
      builder: (context, mapCtrl, digCtrl, _) {
        // Verificar si hay mensajes o errores pendientes para mostrar en la UI
        if (digCtrl.ultimoMensaje != null || digCtrl.ultimoErrorSync != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (digCtrl.ultimoMensaje != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(digCtrl.ultimoMensaje!),
                  backgroundColor: AppTheme.warning,
                ),
              );
              digCtrl.limpiarMensaje();
            }
            if (digCtrl.ultimoErrorSync != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(digCtrl.ultimoErrorSync!),
                  backgroundColor: AppTheme.error,
                  duration: const Duration(seconds: 4),
                ),
              );
              digCtrl.limpiarErrorSync();
            }
          });
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              // ── Mapa principal ─────────────────────────────────────────
              _buildMapa(mapCtrl, digCtrl),

              // ── Barra superior ─────────────────────────────────────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: _buildTopBar(context, mapCtrl, digCtrl),
              ),

              // ── Panel de capas (derecha) ───────────────────────────────
              if (_mostrarPanelCapas)
                Positioned(
                  top: 64, right: 0, bottom: 32,
                  child: _buildPanelCapas(context, mapCtrl, digCtrl),
                ),

              // ── Toggle panel de capas ──────────────────────────────────
              Positioned(
                top: 70,
                right: _mostrarPanelCapas ? 236 : 0,
                child: _buildTogglePanelBtn(),
              ),

              // ── Barra de herramientas (izquierda) ──────────────────────
              Positioned(
                left: 12,
                bottom: 48,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Zoom
                    _ZoomBtn(
                      icon: Icons.add,
                      onTap: () => _cambiarZoom(mapCtrl, 1),
                    ),
                    const SizedBox(height: 4),
                    _ZoomBtn(
                      icon: Icons.remove,
                      onTap: () => _cambiarZoom(mapCtrl, -1),
                    ),
                    const SizedBox(height: 4),
                    // Separador
                    Container(width: 36, height: 1, color: const Color(0xFF2D4054)),
                    const SizedBox(height: 4),
                    // Botón Info (ℹ️) — solo en modo NO-edición
                    _MapActionBtn(
                      icon: Icons.info_outline,
                      tooltip: digCtrl.modoEdicion
                          ? 'Info (desactivado en modo edición)'
                          : _modoInfoActivo
                              ? 'Desactivar información'
                              : 'Activar información de elementos',
                      activo: _modoInfoActivo && !digCtrl.modoEdicion,
                      color: const Color(0xFF4FC3F7),
                      habilitado: !digCtrl.modoEdicion,
                      onTap: () {
                        if (!digCtrl.modoEdicion) {
                          setState(() => _modoInfoActivo = !_modoInfoActivo);
                        }
                      },
                    ),
                    // Botón Seleccionar/Editar elemento (✂️) — solo en modo Edición (OFF = invisible)
                    if (digCtrl.modoEdicion) ...[
                      const SizedBox(height: 4),
                      _MapActionBtn(
                        icon: Icons.content_cut,
                        tooltip: 'Cortar línea',
                        activo: digCtrl.modo == ModoDigitalizacion.cortarLinea,
                        color: const Color(0xFF9C27B0),
                        habilitado: true,
                        onTap: () {
                          digCtrl.setModo(ModoDigitalizacion.cortarLinea);
                          if (digCtrl.idSeleccionado == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ℹ️ Toca un camino en el mapa para seleccionarlo y cortarlo'),
                                backgroundColor: Color(0xFF9C27B0),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 4),
                      // Botón Deshacer Corte — visible cuando hay historial en modo edición
                      if (digCtrl.hayHistorialCorte) ...[
                        Container(width: 36, height: 1, color: const Color(0xFF9C27B0).withOpacity(0.5)),
                        const SizedBox(height: 4),
                        _MapActionBtn(
                          icon: Icons.undo,
                          tooltip: 'Deshacer último corte',
                          activo: false,
                          color: const Color(0xFF9C27B0),
                          habilitado: true,
                          onTap: () {
                            final ok = digCtrl.deshacerUltimoCorte();
                            if (ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('↩ Corte deshecho — línea original restaurada'),
                                  backgroundColor: Color(0xFF9C27B0),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 4),
                      ],
                      // Herramientas de digitalización
                      BarraHerramientas(digCtrl: digCtrl),
                      // Botón "Agregar Vértice" — visible solo en editarLinea / editarPoligono
                      if (digCtrl.modo == ModoDigitalizacion.editarLinea ||
                          digCtrl.modo == ModoDigitalizacion.editarPoligono) ...[
                        const SizedBox(height: 4),
                        Container(width: 36, height: 1, color: const Color(0xFF26C6DA).withOpacity(0.5)),
                        const SizedBox(height: 4),
                        _MapActionBtn(
                          icon: Icons.add_location_alt_outlined,
                          tooltip: 'Agregar vértice (toca un segmento)',
                          activo: digCtrl.modoAgregarVertice,
                          color: const Color(0xFF26C6DA),
                          habilitado: !digCtrl.dragLineaActivo && !digCtrl.dragPoligonoActivo,
                          onTap: () => digCtrl.toggleModoAgregarVertice(),
                        ),
                        if (digCtrl.puedeDeshacerInsercionVertice) ...[
                          const SizedBox(height: 4),
                          _MapActionBtn(
                            icon: Icons.undo,
                            tooltip: 'Deshacer último vértice agregado',
                            activo: false,
                            color: const Color(0xFF26C6DA),
                            habilitado: true,
                            onTap: () => digCtrl.deshacerUltimaInsercionVertice(),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),

              // ── Banner de modo activo ──────────────────────────────────
              if (digCtrl.estaDigitalizando)
                Positioned(
                  top: 72,
                  left: 0,
                  right: _mostrarPanelCapas ? 236 : 0,
                  child: _buildBannerModo(digCtrl),
                ),

              // ── Barra inferior de coordenadas ──────────────────────────
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _buildBarraCoordenadas(mapCtrl, digCtrl),
              ),

              // ── Cursor Crosshair (punto, línea, polígono, editar línea, editar polígono, cortar línea) ─────────
              if (digCtrl.modoEdicion &&
                  (digCtrl.modo == ModoDigitalizacion.punto ||
                   digCtrl.modo == ModoDigitalizacion.linea || 
                   digCtrl.modo == ModoDigitalizacion.poligono ||
                   (digCtrl.modo == ModoDigitalizacion.cortarLinea && digCtrl.idSeleccionado != null) ||
                   (digCtrl.modo == ModoDigitalizacion.editarLinea && digCtrl.verticeEdicionIndex != null) ||
                   (digCtrl.modo == ModoDigitalizacion.editarPoligono && digCtrl.verticePoligonoIndex != null)))
                const CursorCrosshair(),

              // ── Overlay de modo Agregar Vértice ────────────────────────
              if (digCtrl.modoAgregarVertice)
                const _CursorAgregarVertice(),

              // ── Indicador visual de snap ───────────────────────────────────
              // Cuadrito rosa = snap a vértice exacto.
              // Triángulo rosa = snap al punto más cercano de un segmento.
              if (digCtrl.snapActivo != null && digCtrl.estaDigitalizando)
                Builder(builder: (context) {
                  final snap = digCtrl.snapActivo!;
                  final snapOffset = _flutterMapCtrl.camera
                      .getOffsetFromOrigin(snap.snapPoint);
                  return SnapIndicator(
                    screenPosition: Offset(snapOffset.dx, snapOffset.dy),
                    snapType: snap.type,
                  );
                }),

              // ── Panel flotante de digitación de punto (Estructura) ──────
              if (digCtrl.modo == ModoDigitalizacion.punto)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelDigitacionPunto(
                    onFijarPunto: () {
                      final coord = digCtrl.snapActivo?.snapPoint ?? _flutterMapCtrl.camera.center;
                      _mostrarFormularioPunto(context, digCtrl, coord);
                    },
                    onCancelar: () {
                      digCtrl.setModo(ModoDigitalizacion.navegar);
                    },
                  ),
                ),

              // ── Panel flotante de digitación (línea y polígono) ────────
              if (digCtrl.modo == ModoDigitalizacion.linea || digCtrl.modo == ModoDigitalizacion.poligono)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelDigitacion(
                    digCtrl: digCtrl,
                    onAgregarNodo: () {
                      final centro = _flutterMapCtrl.camera.center;
                      digCtrl.agregarVertice(centro);
                    },
                    onFinalizar: () {
                      if (digCtrl.modo == ModoDigitalizacion.linea) {
                        if (digCtrl.verticesEnConstruccion.length >= 2) {
                          _mostrarFormularioLinea(context, digCtrl);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Se necesitan al menos 2 nodos para crear un camino'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      } else if (digCtrl.modo == ModoDigitalizacion.poligono) {
                        if (digCtrl.verticesEnConstruccion.length >= 3) {
                          _mostrarFormularioPoligono(context, digCtrl);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Se necesitan al menos 3 nodos para crear un polígono'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),

              // ── Panel flotante para Cortar Línea ────────────────────────
              if (digCtrl.modo == ModoDigitalizacion.cortarLinea && digCtrl.idSeleccionado != null)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelDigitacion(
                    digCtrl: digCtrl,
                    onAgregarNodo: () {
                      final centro = _flutterMapCtrl.camera.center;
                      digCtrl.agregarVertice(centro);
                    },
                    onFinalizar: () {
                      if (digCtrl.verticesEnConstruccion.length < 2) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ La línea de corte debe tener al menos 2 nodos'),
                            backgroundColor: Color(0xFF9C27B0),
                          ),
                        );
                        return;
                      }
                      final resultado = digCtrl.ejecutarCorteLinea();
                      switch (resultado) {
                        case ResultadoCorte.ok:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ Línea cortada en ${digCtrl.totalSegmentosUltimoCorte} segmentos. '
                                'Usa Deshacer si fue un error.',
                              ),
                              backgroundColor: AppTheme.success,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        case ResultadoCorte.sinInterseccion:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '⚠️ La línea de corte no intersecta el camino seleccionado',
                              ),
                              backgroundColor: Color(0xFFF57F17),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        case ResultadoCorte.sinSeleccion:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ℹ️ Primero selecciona un camino tocando sobre él'),
                              backgroundColor: Color(0xFF9C27B0),
                            ),
                          );
                        case ResultadoCorte.lineaCorteInvalida:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Agrega al menos 2 nodos a la línea de corte'),
                              backgroundColor: Color(0xFF9C27B0),
                            ),
                          );
                        case ResultadoCorte.sinModoEdicion:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Activa el Modo Edición primero'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                      }
                    },
                  ),
                ),

              // ── Panel flotante para Editar Vértice (Mover Línea por drag) ──────
              if (digCtrl.modo == ModoDigitalizacion.editarLinea)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelEdicionLinea(
                    digCtrl: digCtrl,
                    onFinalizar: () {
                      digCtrl.cancelarEdicionLinea();
                    },
                    onCancelar: () {
                      digCtrl.cancelarEdicionLinea();
                    },
                  ),
                ),

              // ── Panel flotante para Editar Vértices de Polígono (Drag) ─────────
              if (digCtrl.modo == ModoDigitalizacion.editarPoligono)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelEdicionPoligono(
                    digCtrl: digCtrl,
                    onGuardarPoligono: () {
                      digCtrl.confirmarEdicionPoligono();
                    },
                    onCancelarEdicionCompleta: () {
                      digCtrl.cancelarEdicionPoligono();
                    },
                  ),
                ),

              // ── Panel flotante para Editar Posición de Punto (Drag) ──────────
              if (digCtrl.modo == ModoDigitalizacion.editarPunto)
                Positioned(
                  bottom: 48,
                  right: _mostrarPanelCapas ? 252 : 16,
                  child: PanelEdicionPunto(
                    digCtrl: digCtrl,
                    onFinalizar: () {
                      if (digCtrl.posicionDragPuntoTemporal != null) {
                        digCtrl.confirmarDragPunto(digCtrl.posicionDragPuntoTemporal!);
                      } else {
                        digCtrl.cancelarDragPunto();
                      }
                    },
                    onCancelar: () {
                      digCtrl.cancelarDragPunto();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAPA PRINCIPAL
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMapa(ctrl.MapController mapCtrl, DigitalizacionController digCtrl) {
    return FlutterMap(
      mapController: _flutterMapCtrl,
      options: MapOptions(
        initialCenter: mapCtrl.centro,
        initialZoom: mapCtrl.zoom,
        minZoom: 3.0,
        maxZoom: 22.0,
        backgroundColor: const Color(0xFF1A2535),

        // Deshabilitar interacciones de mapa cuando hay un drag activo, durante la edición de vértices o durante la creación
        interactionOptions: InteractionOptions(
          flags: (digCtrl.dragLineaActivo || 
                  digCtrl.dragPoligonoActivo || 
                  digCtrl.dragPuntoActivo ||
                  digCtrl.modo == ModoDigitalizacion.editarLinea || 
                  digCtrl.modo == ModoDigitalizacion.editarPoligono ||
                  digCtrl.modo == ModoDigitalizacion.editarPunto)
              ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
              : ((digCtrl.estaDigitalizando && 
                  digCtrl.modo != ModoDigitalizacion.punto &&
                  digCtrl.modo != ModoDigitalizacion.linea && 
                  digCtrl.modo != ModoDigitalizacion.poligono &&
                  digCtrl.modo != ModoDigitalizacion.cortarLinea &&
                  digCtrl.modo != ModoDigitalizacion.editarLinea &&
                  digCtrl.modo != ModoDigitalizacion.editarPoligono &&
                  digCtrl.modo != ModoDigitalizacion.editarPunto)
                  ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
                  : InteractiveFlag.all),
        ),

        onMapEvent: (event) {
          if (event is MapEventMove) {
            mapCtrl.actualizarCentro(event.camera.center);
            setState(() => _zoomActual = event.camera.zoom);
            mapCtrl.actualizarZoom(event.camera.zoom);

            // ── Actualizar snap en cada movimiento del mapa ────────────────
            // El crosshair siempre está en el centro, así que basta con
            // recalcular el snap cada vez que el mapa se desplaza.
            if (digCtrl.estaDigitalizando) {
              digCtrl.calcularSnap(event.camera.center, event.camera);
            }
          }
        },

        // Tap: crear geometría o registrar coordenadas
        onTap: (tapPosition, point) {
          setState(() => _coordsCursor = point);

          // ── Modo Agregar Vértice: insertar sobre segmento ─────────────────────
          if (digCtrl.modoAgregarVertice) {
            final exito = digCtrl.insertarVerticeSobreSegmento(point, _flutterMapCtrl.camera);
            if (!exito && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ℹ️ Toca sobre un segmento de la geometría'),
                  backgroundColor: Color(0xFF26C6DA),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }

          // ── Modo Cortar Línea: selección silenciosa, sin abrir sheet ─────
          // Si ya hay una línea seleccionada, el tap no interrumpe el trazado.
          if (digCtrl.modo == ModoDigitalizacion.cortarLinea) {
            if (digCtrl.idSeleccionado == null) {
              final res = digCtrl.buscarEntidadCercana(point, _flutterMapCtrl.camera);
              if (res is LineaSeleccionada) {
                digCtrl.seleccionar(res.linea.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✂️ Camino "${res.linea.nombre.isEmpty ? "Sin nombre" : res.linea.nombre}" seleccionado. '
                      'Ahora traza la línea de corte con ➕.',
                    ),
                    backgroundColor: const Color(0xFF9C27B0),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
            return;
          }

          // ── Selección Unificada de Entidades (Puntos, Líneas, Polígonos) ──────
          // Permite seleccionar elementos existentes siempre que no se esté digitalizando (sin vértices en construcción)
          final esModoPermiteSeleccion = digCtrl.modo == ModoDigitalizacion.navegar ||
              ((digCtrl.modo == ModoDigitalizacion.punto ||
                digCtrl.modo == ModoDigitalizacion.linea ||
                digCtrl.modo == ModoDigitalizacion.poligono) &&
               digCtrl.verticesEnConstruccion.isEmpty);

          if (esModoPermiteSeleccion) {
            final res = digCtrl.buscarEntidadCercana(point, _flutterMapCtrl.camera);
            switch (res) {
              case PuntoSeleccionado(:final punto):
                digCtrl.seleccionar(punto.id);
                _mostrarInfoPunto(context, punto, digCtrl);
                return;
              case LineaSeleccionada(:final linea):
                digCtrl.seleccionar(linea.id);
                _mostrarInfoLinea(context, linea, digCtrl);
                return;
              case PoligonoSeleccionado(:final poligono):
                digCtrl.seleccionar(poligono.id);
                _mostrarInfoPoligono(context, poligono, digCtrl);
                return;
              case SinResultado():
                if (digCtrl.idSeleccionado != null) {
                  digCtrl.seleccionar(null);
                }
            }
          }

          // En modo línea/polígono/edición con vértices o en edición activa los taps se manejan por sus herramientas/paneles
          if (digCtrl.modo == ModoDigitalizacion.linea || 
              digCtrl.modo == ModoDigitalizacion.poligono ||
              digCtrl.modo == ModoDigitalizacion.cortarLinea || 
              digCtrl.modo == ModoDigitalizacion.editarLinea ||
              digCtrl.modo == ModoDigitalizacion.editarPoligono) {
            return;
          }
              
          final resultado = digCtrl.procesarTap(point);
          if (resultado != null && digCtrl.modo == ModoDigitalizacion.punto) {
            // No se hace await aquí porque onTap es síncrono.
            // unawaited permite el flujo async sin bloquear el widget tree.
            _mostrarFormularioPunto(context, digCtrl, resultado);
          }
        },


        // Mover cursor: actualiza preview
        onSecondaryTap: null,
      ),
      children: [
        // ── Capa 1: Fondo offline ──────────────────────────────────────────
        const ColoredBox(color: Color(0xFF1A2535)),

        // ── Capa 1.5: Mapa Base Online ─────────────────────────────────────
        if (mapCtrl.mostrarMapaBase)
          TileLayer(
            urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
            userAgentPackageName: 'com.cartodigital.app',
          ),

        // ── Capa 2: Imagen de fondo calibrada ─────────────────────────────
        if (mapCtrl.tieneImagenFondo && mapCtrl.mostrarImagenFondo)
          _buildCapaImagenFondo(mapCtrl.imagenFondo!),

        // ── Capa 3: Polígonos (UPM) — debajo de líneas y puntos ───────────
        if (digCtrl.mostrarPoligonos)
          _buildCapaPoligonos(digCtrl),

        // ── Capa 4: Polígono en construcción (preview) ────────────────────
        if (digCtrl.modo == ModoDigitalizacion.poligono &&
            digCtrl.verticesEnConstruccion.length >= 2)
          _buildPreviewPoligono(digCtrl),

        // ── Capa 4.5: Polígono en edición de vértices (preview) ───────────
        if (digCtrl.modo == ModoDigitalizacion.editarPoligono)
          _buildPreviewPoligonoEdicion(digCtrl),

        // ── Capa 5: Líneas (Caminos) ───────────────────────────────────────
        if (digCtrl.mostrarLineas)
          _buildCapaLineas(digCtrl),

        // ── Capa 6: Línea en construcción (preview) ───────────────────────
        if ((digCtrl.modo == ModoDigitalizacion.linea || digCtrl.modo == ModoDigitalizacion.cortarLinea) &&
            digCtrl.verticesEnConstruccion.isNotEmpty)
          _buildPreviewLinea(digCtrl),

        // ── Capa 7: Vértices en construcción (puntos del path) ─────────────
        if (digCtrl.estaDigitalizando &&
            digCtrl.verticesEnConstruccion.isNotEmpty)
          _buildVerticesEnConstruccion(digCtrl),

        // ── Capa 7.5: Vértices de línea seleccionada (modo editarLinea) ────
        if (digCtrl.modo == ModoDigitalizacion.editarLinea)
          _buildVerticesLineas(digCtrl),

        // ── Capa 7.6: Vértices de polígono seleccionado (modo editarPoligono) ────
        if (digCtrl.modo == ModoDigitalizacion.editarPoligono)
          _buildVerticesPoligono(digCtrl),

        // ── Capa 8: Puntos / Estructuras ───────────────────────────────────
        if (digCtrl.mostrarPuntos)
          _buildCapaPuntos(context, digCtrl),

        // ── Atribución ─────────────────────────────────────────────────────
        const SimpleAttributionWidget(
          source: Text(
            'Carto Digital · WGS84',
            style: TextStyle(color: Color(0x88FFFFFF), fontSize: 10),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAPAS DE GEOMETRÍA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCapaImagenFondo(ImagenCalibrada imagen) {
    return OverlayImageLayer(
      overlayImages: [
        OverlayImage(
          bounds: LatLngBounds(imagen.esquinaSO, imagen.esquinaNE),
          imageProvider: FileImage(File(imagen.rutaArchivo)),
          opacity: imagen.opacidad,
        ),
      ],
    );
  }

  Widget _buildCapaPuntos(BuildContext context, DigitalizacionController digCtrl) {
    return MarkerLayer(
      markers: [
        ...digCtrl.puntos.map((punto) {
          final seleccionado = digCtrl.idSeleccionado == punto.id;
          final esModoEditarPunto = digCtrl.modo == ModoDigitalizacion.editarPunto && seleccionado;
          final enDrag = esModoEditarPunto && digCtrl.dragPuntoActivo;
          final posicionActual = enDrag
              ? (digCtrl.posicionDragPuntoTemporal ?? punto.coordenadas)
              : punto.coordenadas;

          return Marker(
            point: posicionActual,
            width: (seleccionado || esModoEditarPunto) ? 48 : 36,
            height: (seleccionado || esModoEditarPunto) ? 48 : 36,
            child: esModoEditarPunto
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      digCtrl.iniciarDragPunto(punto.id);
                    },
                    onPanUpdate: (details) {
                      final newPos = _flutterMapCtrl.camera.screenOffsetToLatLng(details.globalPosition);
                      digCtrl.actualizarDragPunto(newPos);
                    },
                    onPanEnd: (details) {
                      if (digCtrl.posicionDragPuntoTemporal != null) {
                        digCtrl.confirmarDragPunto(digCtrl.posicionDragPuntoTemporal!);
                      } else {
                        digCtrl.cancelarDragPunto();
                      }
                    },
                    onPanCancel: () {
                      digCtrl.cancelarDragPunto();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enDrag
                            ? const Color(0xFFE53935).withOpacity(0.9)
                            : const Color(0xFFFFB74D).withOpacity(0.95),
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (enDrag ? const Color(0xFFE53935) : const Color(0xFFFFB74D)).withOpacity(0.6),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          punto.emojiActivo,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  )
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: seleccionado
                          ? const Color(0xFF4FC3F7).withOpacity(0.9)
                          : const Color(0xFF4FC3F7).withOpacity(0.85),
                      border: Border.all(
                        color: Colors.white,
                        width: seleccionado ? 3 : 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4FC3F7).withOpacity(0.5),
                          blurRadius: seleccionado ? 12 : 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        punto.emojiActivo,
                        style: TextStyle(fontSize: seleccionado ? 18 : 14),
                      ),
                    ),
                  ),
          );
        }),
      ],
    );
  }

  Widget _buildCapaLineas(DigitalizacionController digCtrl) {
    return PolylineLayer(
      polylines: digCtrl.lineas.map((linea) {
        final seleccionada = digCtrl.idSeleccionado == linea.id;
        List<LatLng> points = linea.vertices;
        if (seleccionada && digCtrl.dragLineaActivo && digCtrl.indiceDragLineaActivo != null && digCtrl.posicionDragLineaTemporal != null) {
          points = List<LatLng>.from(linea.vertices);
          if (digCtrl.indiceDragLineaActivo! >= 0 && digCtrl.indiceDragLineaActivo! < points.length) {
            points[digCtrl.indiceDragLineaActivo!] = digCtrl.posicionDragLineaTemporal!;
          }
        }
        return Polyline(
          points: points,
          color: seleccionada
              ? const Color(0xFFFFCC02)
              : const Color(0xFFFFB74D),
          strokeWidth: seleccionada ? 4.0 : 2.5,
          pattern: linea.tipo == TipoCamino.vereda
              ? const StrokePattern.dotted()
              : const StrokePattern.solid(),
        );
      }).toList(),
    );
  }

  Widget _buildCapaPoligonos(DigitalizacionController digCtrl) {
    final poligonosARenderizar = digCtrl.poligonos.where((p) => p.id != digCtrl.idPoligonoEditando);
    return PolygonLayer(
      polygons: poligonosARenderizar.map((poligono) {
        final seleccionado = digCtrl.idSeleccionado == poligono.id;
        return Polygon(
          points: poligono.vertices,
          color: seleccionado
              ? const Color(0xFFA5D6A7).withOpacity(0.35)
              : const Color(0xFFA5D6A7).withOpacity(0.2),
          borderColor: seleccionado
              ? const Color(0xFF66BB6A)
              : const Color(0xFFA5D6A7),
          borderStrokeWidth: seleccionado ? 3.0 : 1.5,
          label: poligono.codigoUPM.isNotEmpty
              ? poligono.codigoUPM
              : poligono.nombre,
          labelStyle: const TextStyle(
            color: Color(0xFFA5D6A7),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        );
      }).toList(),
    );
  }

  // Preview de polígono en edición de vértices
  Widget _buildPreviewPoligonoEdicion(DigitalizacionController digCtrl) {
    if (digCtrl.modo != ModoDigitalizacion.editarPoligono) return const SizedBox.shrink();
    if (digCtrl.verticesPoligonoEdicion.isEmpty) return const SizedBox.shrink();

    final verts = List<LatLng>.from(digCtrl.verticesPoligonoEdicion);
    final autoIntersecta = digCtrl.dragPoligonoAutoIntersecta;

    if (digCtrl.dragPoligonoActivo &&
        digCtrl.indiceDragPoligonoActivo != null &&
        digCtrl.posicionDragPoligonoTemporal != null) {
      if (digCtrl.indiceDragPoligonoActivo! >= 0 &&
          digCtrl.indiceDragPoligonoActivo! < verts.length) {
        verts[digCtrl.indiceDragPoligonoActivo!] = digCtrl.posicionDragPoligonoTemporal!;
      }
    } else if (digCtrl.verticePoligonoIndex != null &&
        digCtrl.verticePoligonoIndex! >= 0 &&
        digCtrl.verticePoligonoIndex! < verts.length) {
      verts[digCtrl.verticePoligonoIndex!] = _flutterMapCtrl.camera.center;
    }

    final colorFill = autoIntersecta
        ? AppTheme.error.withOpacity(0.3)
        : const Color(0xFF4CAF50).withOpacity(0.3);
    final colorBorder = autoIntersecta ? AppTheme.error : const Color(0xFF4CAF50);

    return PolygonLayer(
      polygons: [
        Polygon(
          points: verts,
          color: colorFill,
          borderColor: colorBorder,
          borderStrokeWidth: 2.5,
        ),
      ],
    );
  }

  // Nodos/vértices del polígono en edición
  Widget _buildVerticesPoligono(DigitalizacionController digCtrl) {
    if (digCtrl.modo != ModoDigitalizacion.editarPoligono) return const SizedBox.shrink();
    if (digCtrl.verticesPoligonoEdicion.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: digCtrl.verticesPoligonoEdicion.asMap().entries.map((entry) {
        final i = entry.key;
        final punto = entry.value;
        final esVerticeEnDrag = digCtrl.dragPoligonoActivo && digCtrl.indiceDragPoligonoActivo == i;
        final posicionActual = esVerticeEnDrag
            ? (digCtrl.posicionDragPoligonoTemporal ?? punto)
            : (digCtrl.verticePoligonoIndex == i ? _flutterMapCtrl.camera.center : punto);

        return Marker(
          point: posicionActual,
          width: 36,
          height: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              digCtrl.iniciarDragVerticePoligono(i);
            },
            onPanUpdate: (details) {
              final newPos = _flutterMapCtrl.camera.screenOffsetToLatLng(details.globalPosition);
              digCtrl.actualizarDragVerticePoligono(newPos);
            },
            onPanEnd: (details) {
              if (digCtrl.posicionDragPoligonoTemporal != null) {
                final exito = digCtrl.confirmarDragVerticePoligono(digCtrl.posicionDragPoligonoTemporal!);
                if (!exito && mounted && digCtrl.ultimoMensaje != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(digCtrl.ultimoMensaje!),
                      backgroundColor: AppTheme.error,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  digCtrl.limpiarMensaje();
                }
              } else {
                digCtrl.cancelarDragVerticePoligono();
              }
            },
            onPanCancel: () {
              digCtrl.cancelarDragVerticePoligono();
            },
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: esVerticeEnDrag
                    ? (digCtrl.dragPoligonoAutoIntersecta ? AppTheme.error : const Color(0xFFE53935))
                    : const Color(0xFF4CAF50),
                border: Border.all(color: Colors.white, width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: (esVerticeEnDrag ? const Color(0xFFE53935) : Colors.black).withOpacity(0.4),
                    blurRadius: esVerticeEnDrag ? 8 : 4,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Preview de línea mientras se digitaliza
  Widget _buildPreviewLinea(DigitalizacionController digCtrl) {
    final verts = digCtrl.verticesEnConstruccion;
    final center = _flutterMapCtrl.camera.center;
    final List<LatLng> puntos = [...verts, center];
    if (puntos.length < 2) return const SizedBox.shrink();

    return PolylineLayer(
      polylines: [
        Polyline(
          points: puntos,
          color: const Color(0xFFFFCC02),
          strokeWidth: 2.0,
          pattern: StrokePattern.dashed(segments: const [8, 4]),
        ),
      ],
    );
  }

  // Preview de polígono mientras se digitaliza
  Widget _buildPreviewPoligono(DigitalizacionController digCtrl) {
    final verts = digCtrl.verticesEnConstruccion;
    final center = _flutterMapCtrl.camera.center;
    final List<LatLng> puntos = [...verts, center];
    if (puntos.length < 2) return const SizedBox.shrink();

    return PolygonLayer(
      polygons: [
        Polygon(
          points: [...puntos, puntos.first], // cerrarlo visualmente
          color: const Color(0xFF66BB6A).withOpacity(0.15),
          borderColor: const Color(0xFF66BB6A),
          borderStrokeWidth: 1.5,
        ),
      ],
    );
  }

  // Puntos de vértices de la línea en edición
  Widget _buildVerticesLineas(DigitalizacionController digCtrl) {
    if (digCtrl.modo != ModoDigitalizacion.editarLinea) return const SizedBox.shrink();
    if (digCtrl.idSeleccionado == null) return const SizedBox.shrink();
    
    final lineaIndex = digCtrl.lineas.indexWhere((l) => l.id == digCtrl.idSeleccionado);
    if (lineaIndex == -1) return const SizedBox.shrink();
    final linea = digCtrl.lineas[lineaIndex];

    return MarkerLayer(
      markers: linea.vertices.asMap().entries.map((entry) {
        final i = entry.key;
        final punto = entry.value;
        final esVerticeEnDrag = digCtrl.dragLineaActivo && digCtrl.indiceDragLineaActivo == i;
        final posicionActual = esVerticeEnDrag ? (digCtrl.posicionDragLineaTemporal ?? punto) : punto;

        return Marker(
          point: posicionActual,
          width: 36,
          height: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              digCtrl.iniciarDragVerticeLinea(i);
            },
            onPanUpdate: (details) {
              final newPos = _flutterMapCtrl.camera.screenOffsetToLatLng(details.globalPosition);
              digCtrl.actualizarDragVerticeLinea(newPos);
            },
            onPanEnd: (details) {
              if (digCtrl.posicionDragLineaTemporal != null) {
                digCtrl.confirmarDragVerticeLinea(digCtrl.posicionDragLineaTemporal!);
              } else {
                digCtrl.cancelarDragVerticeLinea();
              }
            },
            onPanCancel: () {
              digCtrl.cancelarDragVerticeLinea();
            },
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: esVerticeEnDrag ? const Color(0xFFE53935) : const Color(0xFFFFB74D),
                border: Border.all(color: Colors.white, width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: (esVerticeEnDrag ? const Color(0xFFE53935) : Colors.black).withOpacity(0.4),
                    blurRadius: esVerticeEnDrag ? 8 : 4,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Puntos de vértices durante la construcción
  Widget _buildVerticesEnConstruccion(DigitalizacionController digCtrl) {
    return MarkerLayer(
      markers: digCtrl.verticesEnConstruccion.asMap().entries.map((entry) {
        final i = entry.key;
        final punto = entry.value;
        final esInicio = i == 0;
        return Marker(
          point: punto,
          width: 14,
          height: 14,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: esInicio ? const Color(0xFF66BB6A) : const Color(0xFFFFCC02),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCIONES DE FORMULARIO
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _mostrarFormularioPunto(
      BuildContext context, DigitalizacionController digCtrl, LatLng punto) async {
    final auth = Provider.of<AuthController>(context, listen: false);

    // ── PASO 1: Crear el punto INMEDIATAMENTE con datos mínimos ──────────────
    // Esto garantiza que la geometría queda en BD desde el primer tap,
    // independientemente de si el usuario completa el formulario.
    final puntoBase = PuntoEstructura.nuevo(
      coordenadas: punto,
      nombre: '',  // nombre vacío inicial
      idCategoria: 1,
      idTipo: 1,
      estado: EstadoEstructura.presente,
      nivelesCantidad: 1,
      notas: '',
      createdBy: auth.currentUserId,
      deviceId: auth.deviceId,
    );

    // ── PASO 1: Registrar el punto localmente (SQLite) ANTES de abrir formulario.
    // Se usa crearPuntoDraft — NO envía a PostGIS aún, evitando que la posterior
    // llamada a actualizarPunto dispare el ON CONFLICT que incrementaría sync_version.
    digCtrl.crearPuntoDraft(puntoBase);

    // ── PASO 2: Mostrar formulario de atributos ───────────────────────────────
    if (!mounted) return;
    final result = await showDialog<AtributosPuntoResult>(
      context: context,
      barrierDismissible: false,   // evita cierre accidental con tap fuera
      builder: (_) => DialogoAtributosPunto(
        lat: punto.latitude,
        lng: punto.longitude,
        baseUrl: PostGISService().baseUrl,
        tipos: _tiposCatalogo,
      ),
    );

    // ── PASO 3: Actualizar el punto con los atributos ingresados ─────────────
    if (result != null) {
      final puntoActualizado = PuntoEstructura(
        id: puntoBase.id,
        coordenadas: puntoBase.coordenadas,
        nombre: result.nombre,
        idCategoria: result.idCategoria,
        idTipo: result.idTipo,
        estado: result.estado,
        nivelesCantidad: result.nivelesCantidad,
        notas: result.notas,
        fechaCreacion: puntoBase.fechaCreacion,
        updatedAt: DateTime.now(),
        syncDirty: true,
        createdBy: puntoBase.createdBy,
        updatedBy: auth.currentUserId,
        deviceId: puntoBase.deviceId,
        syncVersion: puntoBase.syncVersion,
        niveles: puntoBase.niveles,
      );

      // Persistir actualización de atributos
      digCtrl.actualizarPunto(puntoActualizado);

      // ── PASO 4: Navegar a JerarquiaScreen ────────────────────────────────
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Estructura "${result.nombre}" guardada. Abriendo niveles...'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navegar a NivelListaScreen (Pantalla A del módulo Niveles)
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NivelListaScreen(puntoEstructura: puntoActualizado),
        ),
      );
    } else {
      // Usuario canceló el formulario: se descarta el punto borrador de SQLite y memoria
      digCtrl.descartarPuntoDraft(puntoBase.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Creación de estructura cancelada.'),
          backgroundColor: Color(0xFF546E7A),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _mostrarFormularioLinea(
      BuildContext context, DigitalizacionController digCtrl) async {
    final auth = Provider.of<AuthController>(context, listen: false);
    final verts = List<LatLng>.from(digCtrl.verticesEnConstruccion);
    final linea = LineaCamino.nuevo(vertices: verts, nombre: '');
    final result = await showDialog<AtributosLineaResult>(
      context: context,
      builder: (_) => DialogoAtributosLinea(
        numVertices: verts.length,
        longitudM: linea.longitudMetros,
      ),
    );

    if (result != null) {
      digCtrl.finalizarLinea(
        nombre: result.nombre,
        tipo: result.tipo,
        notas: result.notas,
        createdBy: auth.currentUserId,
        deviceId: auth.deviceId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Línea "${result.nombre}" guardada'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
    // Si cancela, la línea en construcción se mantiene para seguir editando
  }

  Future<void> _mostrarFormularioPoligono(
      BuildContext context, DigitalizacionController digCtrl) async {
    final auth = Provider.of<AuthController>(context, listen: false);
    final verts = List<LatLng>.from(digCtrl.verticesEnConstruccion);
    final poligono = PoligonoUPM.nuevo(vertices: verts, nombre: '');
    final result = await showDialog<AtributosPoligonoResult>(
      context: context,
      builder: (_) => DialogoAtributosPoligono(
        numVertices: verts.length,
        areaMCuad: poligono.areaMetrosCuadrados,
      ),
    );

    if (result != null) {
      digCtrl.finalizarPoligono(
        nombre: result.nombre,
        codigoUPM: result.codigoUPM,
        notas: result.notas,
        createdBy: auth.currentUserId,
        deviceId: auth.deviceId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ UPM "${result.nombre}" guardada'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INFO BUBBLE — PUNTO SELECCIONADO
  // ─────────────────────────────────────────────────────────────────────────

  void _mostrarInfoPunto(BuildContext context, PuntoEstructura punto,
      DigitalizacionController digCtrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D4054),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Text(punto.emojiActivo, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        punto.nombre,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${punto.idTipo == 1 ? "Formal" : punto.idTipo == 2 ? "Ref. Geográfica" : "Tipo ${punto.idTipo}"} · Cat. ${punto.idCategoria}',
                        style: const TextStyle(
                          color: Color(0xFF4FC3F7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF90A4AE), size: 22),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Estado', style: TextStyle(color: AppTheme.primary, fontSize: 11)),
                      Text(punto.estado.label, style: const TextStyle(color: AppTheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Niveles', style: TextStyle(color: AppTheme.primary, fontSize: 11)),
                      Text('${punto.nivelesCantidad}', style: const TextStyle(color: AppTheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Coordenadas
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                'Lat: ${punto.coordenadas.latitude.toStringAsFixed(6)}   '
                'Lng: ${punto.coordenadas.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ]),

            if (punto.notas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 14, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      punto.notas,
                      style: const TextStyle(
                          color: AppTheme.onSurface, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // ── BOTONES DE ACCIÓN PARA EL PUNTO SELECCIONADO ────────────────
            if (digCtrl.modoEdicion) ...[
              Builder(builder: (context) {
                final auth = Provider.of<AuthController>(context, listen: false);
                final esPropietario = (punto.createdBy == null) ||
                    (auth.currentUserId != null && punto.createdBy.toString() == auth.currentUserId.toString());

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.account_tree_outlined, size: 16),
                            label: const Text('Niveles', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4FC3F7),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NivelListaScreen(puntoEstructura: punto),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Editar', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFFB74D),
                              side: const BorderSide(color: Color(0xFFFFB74D)),
                            ),
                            onPressed: () async {
                              if (!esPropietario) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⚠️ Solo el creador puede editar este elemento'),
                                    backgroundColor: AppTheme.warning,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context);
                              final result = await showDialog<AtributosPuntoResult>(
                                context: context,
                                builder: (_) => DialogoAtributosPunto(
                                  lat: punto.coordenadas.latitude,
                                  lng: punto.coordenadas.longitude,
                                  baseUrl: PostGISService().baseUrl,
                                  tipos: _tiposCatalogo,
                                  nombreInicial: punto.nombre,
                                  idCategoriaInicial: punto.idCategoria,
                                  idTipoInicial: punto.idTipo,
                                  estadoInicial: punto.estado,
                                  nivelesInicial: punto.nivelesCantidad,
                                  notasIniciales: punto.notas,
                                  soloLectura: !esPropietario,
                                  onAbrirNiveles: () async {
                                    Navigator.pop(context);
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => NivelListaScreen(puntoEstructura: punto),
                                      ),
                                    );
                                  },
                                ),
                              );
                              if (result != null && mounted && esPropietario) {
                                final puntoEditado = PuntoEstructura(
                                  id: punto.id,
                                  coordenadas: punto.coordenadas,
                                  nombre: result.nombre,
                                  idCategoria: result.idCategoria,
                                  idTipo: result.idTipo,
                                  estado: result.estado,
                                  nivelesCantidad: result.nivelesCantidad,
                                  notas: result.notas,
                                  niveles: punto.niveles,
                                  fechaCreacion: punto.fechaCreacion,
                                  updatedAt: DateTime.now(),
                                  syncDirty: true,
                                  createdBy: punto.createdBy,
                                  updatedBy: auth.currentUserId,
                                  deviceId: punto.deviceId,
                                  syncVersion: punto.syncVersion,
                                );
                                digCtrl.actualizarPunto(puntoEditado);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Estructura "${result.nombre}" actualizada. Abriendo niveles...'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );

                                // Navegar a NivelListaScreen tras guardar edición
                                if (mounted) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => NivelListaScreen(puntoEstructura: puntoEditado),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Ver Atributos', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.onSurface,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await showDialog<AtributosPuntoResult>(
                      context: context,
                      builder: (_) => DialogoAtributosPunto(
                        lat: punto.coordenadas.latitude,
                        lng: punto.coordenadas.longitude,
                        baseUrl: PostGISService().baseUrl,
                        tipos: _tiposCatalogo,
                        nombreInicial: punto.nombre,
                        idCategoriaInicial: punto.idCategoria,
                        idTipoInicial: punto.idTipo,
                        estadoInicial: punto.estado,
                        nivelesInicial: punto.nivelesCantidad,
                        notasIniciales: punto.notas,
                        soloLectura: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _mostrarInfoLinea(BuildContext context, LineaCamino linea, DigitalizacionController digCtrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D4054),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                const Text('🛤️', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        linea.nombre.isEmpty ? 'Sin Nombre' : linea.nombre,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Camino - ${linea.tipo.name}',
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Row(children: [
              const Icon(Icons.show_chart, size: 14, color: Color(0xFFFFB74D)),
              const SizedBox(width: 6),
              Text(
                'Longitud: ${linea.longitudMetros.toStringAsFixed(1)} metros',
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ]),

            if (linea.notas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 14, color: Color(0xFFFFB74D)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      linea.notas,
                      style: const TextStyle(color: AppTheme.onSurface, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            // Acciones — solo visibles en modo Edición
            if (digCtrl.modoEdicion) ...[ 
              const SizedBox(height: 20),
              Builder(builder: (context) {
                final auth = Provider.of<AuthController>(context, listen: false);
                final esPropietario = digCtrl.esPropietario(linea.createdBy, auth.currentUserId);
                void mostrarMensajeNoPropietario() {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ud. no creo este elemento, no tiene permisos de edición'),
                      backgroundColor: AppTheme.warning,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Acciones principales (Mover, Cortar)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit_road, size: 18, color: Colors.white),
                            label: const Text('Mover Vértices', style: TextStyle(color: Colors.white, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: esPropietario ? const Color(0xFF4FC3F7) : Colors.grey.shade700,
                            ),
                            onPressed: () {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                                return;
                              }
                              Navigator.pop(context);
                              digCtrl.setModo(ModoDigitalizacion.editarLinea);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.content_cut, size: 18, color: Colors.white),
                            label: const Text('Cortar Línea', style: TextStyle(color: Colors.white, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: esPropietario ? const Color(0xFF9C27B0) : Colors.grey.shade700,
                            ),
                            onPressed: () {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                                return;
                              }
                              Navigator.pop(context);
                              digCtrl.setModo(ModoDigitalizacion.cortarLinea);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Acciones secundarias (Eliminar, Atributos)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Eliminar', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: esPropietario ? AppTheme.error : Colors.grey,
                              side: BorderSide(color: esPropietario ? AppTheme.error : Colors.grey),
                            ),
                            onPressed: () {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                                return;
                              }
                              digCtrl.eliminarLinea(linea.id, updatedBy: auth.currentUserId);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Atributos', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.onSurface,
                            ),
                            onPressed: () async {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                              }
                              Navigator.pop(context);
                              final result = await showDialog<AtributosLineaResult>(
                                context: context,
                                builder: (_) => DialogoAtributosLinea(
                                  numVertices: linea.vertices.length,
                                  longitudM: linea.longitudMetros,
                                  nombreInicial: linea.nombre,
                                  tipoInicial: linea.tipo,
                                  soloLectura: !esPropietario,
                                ),
                              );
                              if (result != null && esPropietario) {
                                digCtrl.actualizarAtributosLineaSeleccionada(
                                  result.nombre,
                                  result.tipo,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Ver Atributos', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.onSurface,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await showDialog<AtributosLineaResult>(
                      context: context,
                      builder: (_) => DialogoAtributosLinea(
                        numVertices: linea.vertices.length,
                        longitudM: linea.longitudMetros,
                        nombreInicial: linea.nombre,
                        tipoInicial: linea.tipo,
                        soloLectura: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _mostrarInfoPoligono(BuildContext context, PoligonoUPM poligono, DigitalizacionController digCtrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D4054),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                const Text('⬢', style: TextStyle(fontSize: 28, color: Color(0xFFA5D6A7))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poligono.nombre.isEmpty ? 'Sin Nombre' : poligono.nombre,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        poligono.codigoUPM.isNotEmpty
                            ? 'UPM: ${poligono.codigoUPM}'
                            : 'Polígono / UPM',
                        style: const TextStyle(
                          color: Color(0xFFA5D6A7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Row(children: [
              const Icon(Icons.square_foot, size: 14, color: Color(0xFFA5D6A7)),
              const SizedBox(width: 6),
              Text(
                'Área: ${poligono.areaMetrosCuadrados.toStringAsFixed(1)} m²  ·  ${poligono.vertices.length} vértices',
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ]),

            if (poligono.notas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 14, color: Color(0xFFA5D6A7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      poligono.notas,
                      style: const TextStyle(color: AppTheme.onSurface, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            // Acciones — solo visibles en modo Edición
            if (digCtrl.modoEdicion) ...[
              const SizedBox(height: 20),
              Builder(builder: (context) {
                final auth = Provider.of<AuthController>(context, listen: false);
                final esPropietario = digCtrl.esPropietario(poligono.createdBy, auth.currentUserId);
                void mostrarMensajeNoPropietario() {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ud. no creo este elemento, no tiene permisos de edición'),
                      backgroundColor: AppTheme.warning,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Acciones principales (Editar Vértices)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit_location_alt_outlined, size: 18, color: Colors.white),
                            label: const Text('Editar Vértices', style: TextStyle(color: Colors.white, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: esPropietario ? const Color(0xFF4CAF50) : Colors.grey.shade700,
                            ),
                            onPressed: () {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                                return;
                              }
                              Navigator.pop(context);
                              digCtrl.iniciarEdicionPoligono(poligono.id);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Acciones secundarias (Eliminar, Atributos)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Eliminar', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: esPropietario ? AppTheme.error : Colors.grey,
                              side: BorderSide(color: esPropietario ? AppTheme.error : Colors.grey),
                            ),
                            onPressed: () {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                                return;
                              }
                              digCtrl.eliminarPoligono(poligono.id, updatedBy: auth.currentUserId);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Atributos', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.onSurface,
                            ),
                            onPressed: () async {
                              if (!esPropietario) {
                                mostrarMensajeNoPropietario();
                              }
                              Navigator.pop(context);
                              final result = await showDialog<AtributosPoligonoResult>(
                                context: context,
                                builder: (_) => DialogoAtributosPoligono(
                                  numVertices: poligono.vertices.length,
                                  areaMCuad: poligono.areaMetrosCuadrados,
                                  nombreInicial: poligono.nombre,
                                  codigoUPMInicial: poligono.codigoUPM,
                                  soloLectura: !esPropietario,
                                ),
                              );
                              if (result != null && esPropietario) {
                                digCtrl.actualizarAtributosPoligonoSeleccionado(
                                  result.nombre,
                                  result.codigoUPM,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Ver Atributos', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.onSurface,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await showDialog<AtributosPoligonoResult>(
                      context: context,
                      builder: (_) => DialogoAtributosPoligono(
                        numVertices: poligono.vertices.length,
                        areaMCuad: poligono.areaMetrosCuadrados,
                        nombreInicial: poligono.nombre,
                        codigoUPMInicial: poligono.codigoUPM,
                        soloLectura: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BANNER DE MODO ACTIVO
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBannerModo(DigitalizacionController digCtrl) {
    final (label, color, instruccion) = switch (digCtrl.modo) {
      ModoDigitalizacion.punto => (
          '📍 Modo: Punto',
          const Color(0xFF4FC3F7),
          'Mueva el mapa posicionando la mira en la ubicación y use ✔ para confirmar',
        ),
      ModoDigitalizacion.linea => (
          '🛤️ Modo: Línea',
          const Color(0xFFFFB74D),
          digCtrl.verticesEnConstruccion.isEmpty
              ? 'Mueva el mapa y use el botón ➕ para agregar nodos'
              : '${digCtrl.verticesEnConstruccion.length} nodos · Use ➕ para agregar · ✔ para finalizar',
        ),
      ModoDigitalizacion.poligono => (
          '🗺️ Modo: Polígono',
          const Color(0xFFA5D6A7),
          digCtrl.verticesEnConstruccion.isEmpty
              ? 'Mueva el mapa y use el botón ➕ para agregar nodos'
              : '${digCtrl.verticesEnConstruccion.length} nodos · Use ➕ para agregar · ✔ para finalizar',
        ),
      ModoDigitalizacion.editarLinea => (
          '✏️ Modo: Mover Vértices',
          const Color(0xFF4FC3F7),
          digCtrl.verticeEdicionIndex == null 
            ? 'Toca un vértice amarillo para seleccionarlo'
            : 'Mueve el crosshair a la nueva posición y confirma',
        ),
      ModoDigitalizacion.cortarLinea => (() {
          final lineaSel = digCtrl.idSeleccionado != null
              ? digCtrl.lineas.where((l) => l.id == digCtrl.idSeleccionado).firstOrNull
              : null;
          final nNodos = digCtrl.verticesEnConstruccion.length;
          final instruccion = lineaSel == null
              ? '⚠️ Selecciona un camino tocando sobre él primero'
              : nNodos == 0
                  ? 'Camino: "${lineaSel.nombre.isEmpty ? "Sin nombre" : lineaSel.nombre}" · Usa ➕ para trazar la línea de corte'
                  : '$nNodos nodos dibujados · Usa ➕ para agregar · ✔ para ejecutar el corte';
          return ('✂️ Cortar Línea', const Color(0xFF9C27B0), instruccion);
        })(),
      _ => ('', Colors.transparent, ''),
    };

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.2), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: color.withOpacity(0.3),
            ),
            Text(
              instruccion,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BARRA SUPERIOR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, ctrl.MapController mapCtrl,
      DigitalizacionController digCtrl) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.map_outlined, size: 18, color: AppTheme.primary),
            ),
            const SizedBox(width: 8),
            const Text(
              'Visor Cartográfico',
              style: TextStyle(color: AppTheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            // Botón de estado PostGIS & Configurar URL del Servidor
            IconButton(
              icon: Icon(
                digCtrl.onlinePostGIS ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: digCtrl.onlinePostGIS ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                size: 22,
              ),
              tooltip: digCtrl.onlinePostGIS
                  ? 'Conectado a PostGIS (Neon)'
                  : 'Sin conexión a PostGIS (${digCtrl.totalDirty} sin sincronizar). Toca para configurar URL.',
              onPressed: () => _mostrarDialogoConfigURL(context, digCtrl),
            ),
            if (digCtrl.totalDirty > 0)
              IconButton(
                icon: const Icon(Icons.sync, color: Color(0xFFFFB74D), size: 20),
                tooltip: 'Sincronizar ${digCtrl.totalDirty} elementos offline',
                onPressed: () => digCtrl.sincronizarOfflineBatch(),
              ),
            const SizedBox(width: 4),
            if (_guardando || _cargando || digCtrl.cargandoPostGIS)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (mapCtrl.tieneImagenFondo) ...[
              _BarraBtn(icon: Icons.tune, label: 'Recalibrar',
                  onTap: () => _recalibrarImagen(context, mapCtrl)),
              _BarraBtn(icon: Icons.center_focus_strong_outlined, label: 'Centrar',
                  onTap: () => _centrarEnImagen(mapCtrl)),
            ],
            const SizedBox(width: 8),
            _BarraBtn(
              icon: Icons.power_settings_new,
              label: 'Cerrar Aplicación',
              color: AppTheme.error,
              onTap: () => _cerrarAplicacion(context, digCtrl),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _cerrarAplicacion(
      BuildContext context, DigitalizacionController digCtrl) async {
    // Bloqueo de cierre si el modo edición está activado
    if (digCtrl.modoEdicion) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_clock, color: Color(0xFFEF5350)),
              SizedBox(width: 8),
              Text(
                'Modo edición activo',
                style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Debe desactivar el modo edición antes de salir.',
            style: TextStyle(color: AppTheme.onSurface),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    // Diálogo de confirmación para salir
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: AppTheme.error),
            SizedBox(width: 8),
            Text(
              'Cerrar Aplicación',
              style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          '¿Desea cerrar la aplicación?',
          style: TextStyle(color: AppTheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.primary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _salirDeLaApp();
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  /// Ejecuta la sincronización de archivos locales SQLite hacia Postgres/PostGIS.
  Future<void> _ejecutarSincronizacion(
      BuildContext context, DigitalizacionController digCtrl) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF4CAF50),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Sincronizando datos locales con Postgres...',
                style: TextStyle(color: AppTheme.onSurface, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );

    final bool exito = await digCtrl.sincronizarOfflineBatch();

    if (context.mounted) Navigator.of(context).pop();
    if (!context.mounted) return;

    if (exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Datos sincronizados correctamente con Postgres.'),
          backgroundColor: AppTheme.success,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se pudo sincronizar con Postgres. Verifique su conexión.'),
          backgroundColor: AppTheme.error,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _salirDeLaApp() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }


  void _mostrarDialogoConfigURL(BuildContext context, DigitalizacionController digCtrl) {
    final service = PostGISService();
    final controller = TextEditingController(text: service.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.cloud_sync, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Servidor PostGIS API', style: TextStyle(fontSize: 16, color: AppTheme.onSurface)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configura la URL de tu API Python (FastAPI):\n'
              '• Emulador: http://10.0.2.2:8000\n'
              '• Celular Físico (Wi-Fi): http://192.168.X.X:8000\n'
              '• Nube: https://tu-backend.onrender.com',
              style: TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13, color: AppTheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'URL de la API',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                service.setBaseUrl(newUrl);
                digCtrl.cargarDesdePostGIS();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar y Probar'),
          ),
        ],
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // PANEL DE CAPAS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPanelCapas(BuildContext context, ctrl.MapController mapCtrl,
      DigitalizacionController digCtrl) {
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(-2, 0))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera con toggle de edición
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF2D4054),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Capas',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Editar',
                      style: TextStyle(
                        color: digCtrl.modoEdicion
                            ? const Color(0xFFEF5350)
                            : AppTheme.onSurface.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: digCtrl.modoEdicion,
                        onChanged: (_) => digCtrl.toggleModoEdicion(),
                        activeColor: const Color(0xFFEF5350),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                // ── Mapas Base ──────────────────────────────────────────
                _SeccionCapa(titulo: 'Mapas Base'),
                _ItemCapaActiva(
                  icon: Icons.satellite_alt_outlined,
                  label: 'Google Satellite (Online)',
                  count: 0,
                  color: Colors.blue,
                  activo: mapCtrl.mostrarMapaBase,
                  visible: mapCtrl.mostrarMapaBase,
                  onToggleVisibilidad: () => mapCtrl.toggleMapaBase(),
                  onTap: () => mapCtrl.toggleMapaBase(),
                ),

                // ── Imagen de fondo (solo si hay una imagen cargada) ───────────
                if (mapCtrl.tieneImagenFondo) ...[
                  const SizedBox(height: 14),
                  _SeccionCapa(titulo: 'Imagen de Fondo'),
                  _buildItemImagenFondo(context, mapCtrl),
                ],

                const SizedBox(height: 14),

                // ── Geometrías ──────────────────────────────────────────
                _SeccionCapa(titulo: 'Geometrías'),

                _ItemCapaActiva(
                  icon: Icons.place_outlined,
                  label: 'Puntos / Estructuras',
                  count: digCtrl.puntos.length,
                  color: const Color(0xFF4FC3F7),
                  activo: digCtrl.modo == ModoDigitalizacion.punto,
                  esCapaActiva: digCtrl.capaActivaId == '1',
                  mostrarLapiz: digCtrl.modoEdicion,
                  visible: digCtrl.mostrarPuntos,
                  onToggleVisibilidad: () => digCtrl.toggleMostrarPuntos(),
                  onTap: () {
                    digCtrl.setCapaActiva('1');
                    if (digCtrl.modoEdicion) {
                      digCtrl.setModo(ModoDigitalizacion.punto);
                    }
                  },
                ),
                const SizedBox(height: 6),
                _ItemCapaActiva(
                  icon: Icons.polyline_outlined,
                  label: 'Líneas / Caminos',
                  count: digCtrl.lineas.length,
                  color: const Color(0xFFFFB74D),
                  activo: digCtrl.modo == ModoDigitalizacion.linea,
                  esCapaActiva: digCtrl.capaActivaId == '2',
                  mostrarLapiz: digCtrl.modoEdicion,
                  visible: digCtrl.mostrarLineas,
                  onToggleVisibilidad: () => digCtrl.toggleMostrarLineas(),
                  onTap: () {
                    digCtrl.setCapaActiva('2');
                    if (digCtrl.modoEdicion) {
                      digCtrl.setModo(ModoDigitalizacion.linea);
                    }
                  },
                ),
                const SizedBox(height: 6),
                _ItemCapaActiva(
                  icon: Icons.pentagon_outlined,
                  label: 'Polígonos / UPM',
                  count: digCtrl.poligonos.length,
                  color: const Color(0xFFA5D6A7),
                  activo: digCtrl.modo == ModoDigitalizacion.poligono,
                  esCapaActiva: digCtrl.capaActivaId == '3',
                  mostrarLapiz: digCtrl.modoEdicion,
                  visible: digCtrl.mostrarPoligonos,
                  onToggleVisibilidad: () => digCtrl.toggleMostrarPoligonos(),
                  onTap: () {
                    digCtrl.setCapaActiva('3');
                    if (digCtrl.modoEdicion) {
                      digCtrl.setModo(ModoDigitalizacion.poligono);
                    }
                  },
                ),

                if (digCtrl.hayGeometrias) ...[
                  const SizedBox(height: 14),
                  _SeccionCapa(titulo: 'Resumen'),
                  _buildResumen(digCtrl),
                ],

                const SizedBox(height: 14),
                _buildBotonSincronizar(context, digCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonSincronizar(BuildContext context, DigitalizacionController digCtrl) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.sync, size: 18, color: Colors.white),
        label: const Text(
          'Sincronizar',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
        onPressed: () => _ejecutarSincronizacion(context, digCtrl),
      ),
    );
  }

  Widget _buildResumen(DigitalizacionController digCtrl) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _FilaResumen(label: 'Estructuras', valor: '${digCtrl.puntos.length}', color: const Color(0xFF4FC3F7)),
          _FilaResumen(label: 'Caminos', valor: '${digCtrl.lineas.length}', color: const Color(0xFFFFB74D)),
          _FilaResumen(label: 'UPMs', valor: '${digCtrl.poligonos.length}', color: const Color(0xFFA5D6A7)),
          const Divider(height: 12),
          _FilaResumen(label: 'Total', valor: '${digCtrl.totalGeometrias}', color: AppTheme.primary),
        ],
      ),
    );
  }

  Widget _buildBotonCargarImagen(BuildContext context, ctrl.MapController mapCtrl) {
    return InkWell(
      onTap: () => _cargarImagenFondo(context, mapCtrl),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primary, size: 28),
            const SizedBox(height: 6),
            Text('Cargar croquis o plano', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.primary, fontSize: 12)),
            Text('JPG / PNG', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemImagenFondo(BuildContext context, ctrl.MapController mapCtrl) {
    final img = mapCtrl.imagenFondo!;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.image_outlined, size: 18, color: AppTheme.primary),
            ),
            title: Text(img.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              'N:${img.norte.toStringAsFixed(3)}  S:${img.sur.toStringAsFixed(3)}\nE:${img.este.toStringAsFixed(3)}  O:${img.oeste.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF90A4AE)),
            ),
            trailing: IconButton(
              icon: Icon(
                mapCtrl.mostrarImagenFondo ? Icons.visibility : Icons.visibility_off,
                size: 18,
                color: mapCtrl.mostrarImagenFondo ? AppTheme.primary : const Color(0xFF607D8B),
              ),
              tooltip: mapCtrl.mostrarImagenFondo ? 'Ocultar imagen de fondo' : 'Mostrar imagen de fondo',
              onPressed: () => mapCtrl.toggleImagenFondo(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.opacity, size: 13, color: AppTheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Slider(
                    value: img.opacidad,
                    min: 0.1, max: 1.0, divisions: 18,
                    activeColor: AppTheme.primary,
                    inactiveColor: AppTheme.primary.withOpacity(0.15),
                    onChanged: (v) => mapCtrl.setOpacidadImagen(v),
                  ),
                ),
                Text('${(img.opacidad * 100).round()}%',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                Expanded(child: _MiniBtn(icon: Icons.tune, label: 'Recalibrar', onTap: () => _recalibrarImagen(context, mapCtrl))),
                const SizedBox(width: 8),
                Expanded(child: _MiniBtn(icon: Icons.delete_outline, label: 'Quitar', color: AppTheme.error, onTap: () => mapCtrl.quitarImagenFondo())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTROLES INFERIORES Y AUXILIARES
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBarraCoordenadas(ctrl.MapController mapCtrl, DigitalizacionController digCtrl) {
    return Container(
      height: 32,
      color: AppTheme.surface.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.my_location, size: 12, color: AppTheme.primary),
          const SizedBox(width: 6),
          if (_coordsCursor != null)
            Text(
              'Lat: ${_coordsCursor!.latitude.toStringAsFixed(6)}   Lng: ${_coordsCursor!.longitude.toStringAsFixed(6)}',
              style: const TextStyle(color: AppTheme.onSurface, fontSize: 11, fontFamily: 'monospace'),
            )
          else
            Text('Toca el mapa para ver coordenadas', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
          const Spacer(),
          Text(
            'WGS84 · Zoom: ${_zoomActual.toStringAsFixed(1)} · ${digCtrl.totalGeometrias} geom.',
            style: const TextStyle(color: Color(0xFF607D8B), fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildTogglePanelBtn() {
    return GestureDetector(
      onTap: () => setState(() => _mostrarPanelCapas = !_mostrarPanelCapas),
      child: Container(
        width: 22, height: 60,
        decoration: const BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
        ),
        child: Center(child: Icon(_mostrarPanelCapas ? Icons.chevron_right : Icons.chevron_left, size: 16, color: AppTheme.primary)),
      ),
    );
  }

  void _cambiarZoom(ctrl.MapController mapCtrl, int delta) {
    final nuevo = (_zoomActual + delta).clamp(3.0, 22.0);
    _flutterMapCtrl.move(mapCtrl.centro, nuevo);
    mapCtrl.actualizarZoom(nuevo);
    setState(() => _zoomActual = nuevo);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCIONES DE IMAGEN (heredadas del paso 2)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _cargarImagenFondo(BuildContext context, ctrl.MapController mapCtrl) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;

    if (!mounted) return;
    final ImagenCalibrada? imagen = await showDialog<ImagenCalibrada>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogoCalibracion(rutaImagen: file.path!, nombreSugerido: file.name.replaceAll(RegExp(r'\.[^.]+$'), '')),
    );

    if (imagen != null) {
      mapCtrl.establecerImagenFondo(imagen);
      _flutterMapCtrl.move(imagen.centro, mapCtrl.zoom);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ "${imagen.nombre}" cargada'), backgroundColor: AppTheme.success));
    }
  }

  Future<void> _recalibrarImagen(BuildContext context, ctrl.MapController mapCtrl) async {
    if (mapCtrl.imagenFondo == null) return;
    final ImagenCalibrada? nueva = await showDialog<ImagenCalibrada>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogoCalibracion(rutaImagen: mapCtrl.imagenFondo!.rutaArchivo, nombreSugerido: mapCtrl.imagenFondo!.nombre, imagenExistente: mapCtrl.imagenFondo),
    );
    if (nueva != null) mapCtrl.actualizarCalibracion(nueva);
  }

  void _centrarEnImagen(ctrl.MapController mapCtrl) {
    if (mapCtrl.imagenFondo != null) {
      _flutterMapCtrl.move(mapCtrl.imagenFondo!.centro, mapCtrl.zoom);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

class _BarraBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _BarraBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.primary,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}

class _SeccionCapa extends StatelessWidget {
  final String titulo;
  const _SeccionCapa({required this.titulo});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(titulo.toUpperCase(), style: const TextStyle(color: Color(0xFF546E7A), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );
}

class _ItemCapaActiva extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool activo;
  final bool esCapaActiva;
  final bool mostrarLapiz;
  final bool visible;
  final VoidCallback? onToggleVisibilidad;
  final VoidCallback onTap;
  const _ItemCapaActiva({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.activo,
    this.esCapaActiva = false,
    this.mostrarLapiz = false,
    this.visible = true,
    this.onToggleVisibilidad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: esCapaActiva
              ? const Color(0xFF4CAF50).withOpacity(0.18)
              : (activo ? color.withOpacity(0.12) : AppTheme.surfaceVariant),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: esCapaActiva
                ? const Color(0xFF4CAF50)
                : (activo ? color.withOpacity(0.6) : Colors.transparent),
            width: esCapaActiva ? 2.0 : 1.5,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: esCapaActiva ? const Color(0xFF81C784) : (activo ? color : AppTheme.onSurface.withOpacity(0.6))),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: esCapaActiva ? const Color(0xFF81C784) : (activo ? color : AppTheme.onSurface), fontSize: 12, fontWeight: (esCapaActiva || activo) ? FontWeight.w600 : FontWeight.normal))),
          if (onToggleVisibilidad != null) ...[
            GestureDetector(
              onTap: onToggleVisibilidad,
              child: Icon(
                visible ? Icons.visibility : Icons.visibility_off,
                size: 14,
                color: visible ? color : const Color(0xFF607D8B),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (mostrarLapiz) ...[
            Icon(Icons.edit, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          if (count > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class _FilaResumen extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  const _FilaResumen({required this.label, required this.valor, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11))),
      Text(valor, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.label, required this.onTap, this.color = AppTheme.primary});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF2D4054))),
      child: Icon(icon, size: 20, color: AppTheme.onSurface),
    ),
  );
}

/// Botón de acción del mapa (Info / Seleccionar) con estado activo y habilitado.
class _MapActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool activo;
  final bool habilitado;
  final Color color;
  final VoidCallback onTap;

  const _MapActionBtn({
    required this.icon,
    required this.tooltip,
    required this.activo,
    required this.habilitado,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = habilitado ? color : const Color(0xFF37474F);
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: habilitado ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: activo
                ? effectiveColor.withOpacity(0.2)
                : AppTheme.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: activo ? effectiveColor : const Color(0xFF2D4054),
              width: activo ? 2 : 1,
            ),
            boxShadow: activo
                ? [BoxShadow(color: effectiveColor.withOpacity(0.3), blurRadius: 6)]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: activo
                ? effectiveColor
                : habilitado
                    ? AppTheme.onSurface.withOpacity(0.7)
                    : const Color(0xFF37474F),
          ),
        ),
      ),
    );
  }
}

class _CursorAgregarVertice extends StatelessWidget {
  const _CursorAgregarVertice();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF26C6DA).withOpacity(0.2),
            border: Border.all(color: const Color(0xFF26C6DA), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF26C6DA).withOpacity(0.4),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(
            Icons.add,
            color: Color(0xFF26C6DA),
            size: 20,
          ),
        ),
      ),
    );
  }
}
