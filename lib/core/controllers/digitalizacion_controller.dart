import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/capa_geometrica.dart';
import '../models/capa_registro.dart';
import '../models/resultado_seleccion.dart';
import '../models/snap_result.dart';
import '../database/database_helper.dart';
import '../services/polygon_clipper.dart';
import '../services/postgis_service.dart';
import 'dart:collection';

/// Modos de interacción del mapa
enum ModoDigitalizacion {
  navegar,   // Modo pan/zoom normal
  punto,     // Tap → crea un punto inmediatamente
  linea,     // Taps sucesivos → vértices; doble-tap → finaliza línea
  poligono,  // Taps sucesivos → vértices; doble-tap → cierra polígono
  editar,    // Tap sobre geometría → selecciona y permite mover vértices (puntos)
  editarLinea, // Modo especial para arrastrar vértices de una línea
  editarPoligono, // Modo especial para arrastrar vértices de un polígono
  editarPunto, // Modo especial para arrastrar una entidad punto
  cortarLinea, // Modo especial para cortar una línea con el crosshair
}

/// Resultado de la operación de corte de línea
enum ResultadoCorte {
  ok,                 // Corte exitoso
  sinInterseccion,    // La línea de corte no intersecta la selección
  sinSeleccion,       // No hay línea seleccionada
  lineaCorteInvalida, // La línea de corte tiene menos de 2 vértices
  sinModoEdicion,     // La capa no está en modo edición
}

/// Controlador de digitalización de geometrías.
///
/// Gestiona:
/// - El modo activo (navegar / punto / línea / polígono / editar)
/// - Las colecciones de geometrías creadas
/// - El polígono/línea "en construcción" (preview en tiempo real)
/// - La geometría seleccionada para edición
class DigitalizacionController extends ChangeNotifier {

  // ── Modo activo ────────────────────────────────────────────────────────────
  ModoDigitalizacion _modo = ModoDigitalizacion.navegar;
  ModoDigitalizacion get modo => _modo;
  bool get estaDigitalizando => _modo != ModoDigitalizacion.navegar && _modo != ModoDigitalizacion.editar;

  // ── Capas de geometrías finalizadas ───────────────────────────────────────
  final List<PuntoEstructura> puntos = [];
  final List<LineaCamino> lineas = [];
  final List<PoligonoUPM> poligonos = [];

  // ── Integración PostGIS & Capas Dinámicas ───────────────────────────
  List<CapaRegistro> _capasRegistro = [
    CapaRegistro(id: '1', nombre: 'Estructuras / Puntos', tipoGeometria: 'POINT', tablaOrigen: 'estructuras', icono: 'place_outlined', color: '#4FC3F7', activa: true, ordenVisualizacion: 1),
    CapaRegistro(id: '2', nombre: 'Caminos / Líneas', tipoGeometria: 'LINESTRING', tablaOrigen: 'caminos', icono: 'polyline_outlined', color: '#FFB74D', activa: true, ordenVisualizacion: 2),
    CapaRegistro(id: '3', nombre: 'UPMs / Polígonos', tipoGeometria: 'POLYGON', tablaOrigen: 'upms', icono: 'pentagon_outlined', color: '#A5D6A7', activa: true, ordenVisualizacion: 3),
  ];
  List<CapaRegistro> get capasRegistro => UnmodifiableListView(_capasRegistro);

  bool _cargandoPostGIS = false;
  bool get cargandoPostGIS => _cargandoPostGIS;

  bool _onlinePostGIS = false;
  bool get onlinePostGIS => _onlinePostGIS;

  int get totalDirty => puntos.where((p) => p.syncDirty).length + lineas.where((l) => l.syncDirty).length + poligonos.where((p) => p.syncDirty).length;

  // ── Geometría en construcción (preview) ───────────────────────────────────
  /// Vértices acumulados durante la digitalización de línea/polígono
  final List<LatLng> _verticesEnConstruccion = [];
  List<LatLng> get verticesEnConstruccion =>
      List.unmodifiable(_verticesEnConstruccion);

  /// Posición actual del cursor (para mostrar línea de preview hacia el puntero)
  LatLng? _cursorPos;
  LatLng? get cursorPos => _cursorPos;


  // ── Snap topológico ───────────────────────────────────────────────────────
  /// Radio de snap en píxeles. Estándar GIS = 12 px.
  static const double snapRadiusPx = 12.0;

  /// Resultado del último cálculo de snap. Null si no hay snap activo.
  SnapResult? _snapActivo;
  SnapResult? get snapActivo => _snapActivo;

  // ── Auto-ensamblado de polígonos ─────────────────────────────────────────
  /// Si true, al finalizar un polígono se recorta automáticamente cualquier
  /// área solapada con polígonos existentes (operación de diferencia topológica).
  bool _autoEnsambladoPoligono = true;
  bool get autoEnsambladoPoligono => _autoEnsambladoPoligono;

  /// Mensaje de error del auto-ensamblado. Se limpia automáticamente tras ser leído.
  String? _errorAutoEnsamblado;
  String? get errorAutoEnsamblado => _errorAutoEnsamblado;

  /// Activa o desactiva el auto-ensamblado de polígonos.
  void toggleAutoEnsamblado() {
    _autoEnsambladoPoligono = !_autoEnsambladoPoligono;
    notifyListeners();
  }

  /// Limpia el mensaje de error del auto-ensamblado (llamar tras mostrarlo en UI).
  void limpiarErrorAutoEnsamblado() {
    _errorAutoEnsamblado = null;
    // No llamar notifyListeners() aquí para evitar rebuild innecesario
  }

  // ── Selección y Edición de Polígono / Línea ─────────────────────────────────
  String? _idSeleccionado;
  String? get idSeleccionado => _idSeleccionado;

  int? _verticeEdicionIndex;
  int? get verticeEdicionIndex => _verticeEdicionIndex;

  String? _idPoligonoEditando;
  String? get idPoligonoEditando => _idPoligonoEditando;

  int? _verticePoligonoIndex;
  int? get verticePoligonoIndex => _verticePoligonoIndex;

  List<LatLng> _verticesPoligonoEdicion = [];
  List<LatLng> get verticesPoligonoEdicion => List.unmodifiable(_verticesPoligonoEdicion);

  List<LatLng> _verticesPoligonoEdicionOriginal = [];

  // ── Drag de Vértice en Línea ───────────────────────────────────────────────
  int? _indiceDragLineaActivo;
  int? get indiceDragLineaActivo => _indiceDragLineaActivo;

  LatLng? _posicionDragLineaTemporal;
  LatLng? get posicionDragLineaTemporal => _posicionDragLineaTemporal;

  bool _dragLineaActivo = false;
  bool get dragLineaActivo => _dragLineaActivo;

  List<LatLng> _verticesLineaEdicionOriginal = [];

  // ── Drag de Vértice en Polígono ─────────────────────────────────────────────
  int? _indiceDragPoligonoActivo;
  int? get indiceDragPoligonoActivo => _indiceDragPoligonoActivo;

  LatLng? _posicionDragPoligonoTemporal;
  LatLng? get posicionDragPoligonoTemporal => _posicionDragPoligonoTemporal;

  bool _dragPoligonoActivo = false;
  bool get dragPoligonoActivo => _dragPoligonoActivo;

  // ── Drag Directo de Punto ───────────────────────────────────────────────
  bool _dragPuntoActivo = false;
  bool get dragPuntoActivo => _dragPuntoActivo;

  LatLng? _posicionDragPuntoTemporal;
  LatLng? get posicionDragPuntoTemporal => _posicionDragPuntoTemporal;

  LatLng? _posicionOriginalPunto;

  // ── Modo "Agregar Vértice" ────────────────────────────────────────────────
  bool _modoAgregarVertice = false;
  bool get modoAgregarVertice => _modoAgregarVertice;

  /// Activa/desactiva el modo de inserción de vértice.
  /// Solo disponible en modos editarLinea / editarPoligono.
  void toggleModoAgregarVertice() {
    if (_modo != ModoDigitalizacion.editarLinea &&
        _modo != ModoDigitalizacion.editarPoligono) return;
    _modoAgregarVertice = !_modoAgregarVertice;
    notifyListeners();
  }

  /// Inserta un nuevo vértice en el segmento más cercano al punto tocado.
  /// Retorna true si la inserción fue exitosa.
  bool insertarVerticeSobreSegmento(LatLng tapPoint, MapCamera camera) {
    if (!_modoAgregarVertice) return false;

    if (_modo == ModoDigitalizacion.editarLinea) {
      return _insertarVerticeEnLinea(tapPoint, camera);
    } else if (_modo == ModoDigitalizacion.editarPoligono) {
      return _insertarVerticeEnPoligono(tapPoint, camera);
    }
    return false;
  }

  bool _insertarVerticeEnLinea(LatLng tapPoint, MapCamera camera) {
    if (_idSeleccionado == null) return false;
    final lineaIndex = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (lineaIndex == -1) return false;
    final verts = lineas[lineaIndex].vertices;
    if (verts.length < 2) return false;

    final (insertIndex, snapPoint) = _encontrarSegmentoMasCercano(
        tapPoint, verts, esCerrado: false, camera: camera);
    if (insertIndex == -1) return false;

    final targetIndex = insertIndex + 1;
    final nuevosVertices = List<LatLng>.from(verts);
    nuevosVertices.insert(targetIndex, snapPoint);

    final original = lineas[lineaIndex];
    final modificada = LineaCamino(
      id: original.id,
      vertices: nuevosVertices,
      nombre: original.nombre,
      tipo: original.tipo,
      notas: original.notas,
      fechaCreacion: original.fechaCreacion,
      updatedAt: DateTime.now(),
      syncDirty: true,
      createdBy: original.createdBy,
      updatedBy: original.updatedBy,
      deviceId: original.deviceId,
      syncVersion: original.syncVersion,
    );
    lineas[lineaIndex] = modificada;
    _historialInsercionVertices.add((original.id, targetIndex));
    DatabaseHelper().insertEntity('caminos', modificada.toMapDB());
    _ultimoMensaje = '➕ Vértice agregado a la línea';
    notifyListeners();
    return true;
  }

  bool _insertarVerticeEnPoligono(LatLng tapPoint, MapCamera camera) {
    if (_idPoligonoEditando == null) return false;
    if (_verticesPoligonoEdicion.length < 3) return false;

    final (insertIndex, snapPoint) = _encontrarSegmentoMasCercano(
        tapPoint, _verticesPoligonoEdicion, esCerrado: true, camera: camera);
    if (insertIndex == -1) return false;

    final targetIndex = insertIndex + 1;
    final tempVertices = List<LatLng>.from(_verticesPoligonoEdicion);
    tempVertices.insert(targetIndex, snapPoint);

    if (_esPoligonoAutoIntersectante(tempVertices)) {
      _ultimoMensaje = '⚠️ No se puede agregar el vértice: generaría auto-intersección';
      notifyListeners();
      return false;
    }

    _verticesPoligonoEdicion.insert(targetIndex, snapPoint);
    _historialInsercionVertices.add((_idPoligonoEditando!, targetIndex));
    _ultimoMensaje = '➕ Vértice agregado al polígono';
    notifyListeners();
    return true;
  }

  /// Encuentra el segmento más cercano al [tapPoint] y retorna
  /// el índice del vértice de inicio del segmento y el punto proyectado.
  /// Radio de tolerancia: 30 px.
  (int, LatLng) _encontrarSegmentoMasCercano(
      LatLng tapPoint, List<LatLng> verts,
      {required bool esCerrado, required MapCamera camera}) {
    final tapPx = camera.getOffsetFromOrigin(tapPoint);
    const tolerancePx = 30.0;
    double bestDist = double.infinity;
    int bestIndex = -1;
    LatLng bestSnap = tapPoint;

    final n = verts.length;
    final segments = esCerrado ? n : n - 1;

    for (int i = 0; i < segments; i++) {
      final p1 = verts[i];
      final p2 = verts[(i + 1) % n];
      final p1Px = camera.getOffsetFromOrigin(p1);
      final p2Px = camera.getOffsetFromOrigin(p2);

      final dx = p2Px.dx - p1Px.dx;
      final dy = p2Px.dy - p1Px.dy;
      final len2 = dx * dx + dy * dy;
      if (len2 < 1e-6) continue;

      final cx = tapPx.dx - p1Px.dx;
      final cy = tapPx.dy - p1Px.dy;
      final t = ((cx * dx + cy * dy) / len2).clamp(0.0, 1.0);

      final projX = p1Px.dx + t * dx;
      final projY = p1Px.dy + t * dy;
      final dist = math.sqrt(math.pow(tapPx.dx - projX, 2) +
                             math.pow(tapPx.dy - projY, 2));

      if (dist <= tolerancePx && dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
        final snapLat = p1.latitude + t * (p2.latitude - p1.latitude);
        final snapLng = p1.longitude + t * (p2.longitude - p1.longitude);
        bestSnap = LatLng(snapLat, snapLng);
      }
    }
    return (bestIndex, bestSnap);
  }

  // ── Modo edición global ───────────────────────────────────────────────
  /// Controla si las capas permiten edición (eliminar, mover, cortar).
  /// Por defecto: false (modo solo lectura/navegación).
  bool _modoEdicion = false;
  bool get modoEdicion => _modoEdicion;

  // ── Capa activa seleccionada en panel ──────────────────────────────────
  String? _capaActivaId = '1'; // '1': estructuras, '2': caminos, '3': upms
  String? get capaActivaId => _capaActivaId;
  void setCapaActiva(String? id) {
    _capaActivaId = id;
    notifyListeners();
  }

  /// Retorna verdadero si el usuario en sesión es el creador del elemento (propietario_elemento).
  bool esPropietario(String? createdBy, String? currentUserId) {
    if (createdBy == null || currentUserId == null) return false;
    return createdBy == currentUserId;
  }

  // ── Visibilidad de capas de geometrías ──────────────────────────────────
  bool _mostrarPuntos = true;
  bool get mostrarPuntos => _mostrarPuntos;
  void toggleMostrarPuntos() {
    _mostrarPuntos = !_mostrarPuntos;
    notifyListeners();
  }

  bool _mostrarLineas = true;
  bool get mostrarLineas => _mostrarLineas;
  void toggleMostrarLineas() {
    _mostrarLineas = !_mostrarLineas;
    notifyListeners();
  }

  bool _mostrarPoligonos = true;
  bool get mostrarPoligonos => _mostrarPoligonos;
  void toggleMostrarPoligonos() {
    _mostrarPoligonos = !_mostrarPoligonos;
    notifyListeners();
  }

  // ── Mensajes para la UI (SnackBar) ──────────────────────────────────
  /// Mensaje informativo (se limpia tras ser leído por la UI).
  String? _ultimoMensaje;
  String? get ultimoMensaje => _ultimoMensaje;
  void limpiarMensaje() { _ultimoMensaje = null; }

  /// Error de sincronización (se limpia tras ser leído por la UI).
  String? _ultimoErrorSync;
  String? get ultimoErrorSync => _ultimoErrorSync;
  void limpiarErrorSync() { _ultimoErrorSync = null; }

  void toggleModoEdicion() {
    _modoEdicion = !_modoEdicion;
    // Al salir del modo edición, cancela cualquier modo activo de digitación/edición y vuelve a navegar
    if (!_modoEdicion) {
      cancelarEdicionPoligono();
      cancelarEdicionPunto();
      cancelarEdicionLinea();
      _cancelarConstruccion();
      _modo = ModoDigitalizacion.navegar;
      _idSeleccionado = null;
    } else {
      // Al entrar a modo edición, activa el modo de digitalización correspondiente a la capa activa
      if (_capaActivaId == '1') {
        _modo = ModoDigitalizacion.punto;
      } else if (_capaActivaId == '2') {
        _modo = ModoDigitalizacion.linea;
      } else if (_capaActivaId == '3') {
        _modo = ModoDigitalizacion.poligono;
      }
    }
    notifyListeners();
  }

  // ── Historial de cortes (Undo en sesión) ──────────────────────────────
  final List<_OperacionCorte> _historialCorte = [];
  static const int _maxHistorial = 20;
  bool get hayHistorialCorte => _historialCorte.isNotEmpty;
  int get totalSegmentosUltimoCorte =>
      _historialCorte.isEmpty ? 0 : _historialCorte.last.segmentosGenerados.length;

  // ── Estadísticas ──────────────────────────────────────────────────────
  int get totalGeometrias => puntos.length + lineas.length + poligonos.length;
  bool get hayGeometrias => totalGeometrias > 0;

  // ────────────────────────────────────────────────────────────────────────────
  // GESTIÓN DE MODOS
  // ────────────────────────────────────────────────────────────────────────────

  /// Modos que requieren modo edición activo para ser seleccionados.
  static const _modosQueRequierenEdicion = {
    ModoDigitalizacion.punto,
    ModoDigitalizacion.linea,
    ModoDigitalizacion.poligono,
    ModoDigitalizacion.editarLinea,
    ModoDigitalizacion.editarPoligono,
    ModoDigitalizacion.editarPunto,
    ModoDigitalizacion.cortarLinea,
  };

  /// Cambia el modo activo. Si hay una geometría en construcción, la descarta.
  /// Bloquea modos de creación/edición si [modoEdicion] está desactivado.
  void setModo(ModoDigitalizacion nuevoModo) {
    // ── Guard: bloquear si requiere modo edición y no está activo ──────
    if (_modosQueRequierenEdicion.contains(nuevoModo) && !_modoEdicion) {
      _ultimoMensaje = '🔒 Active el Modo Edición para digitalizar';
      notifyListeners();
      return;
    }

    if (_modo == nuevoModo) {
      // Toggle: si ya está en el modo, vuelve a navegar
      _cancelarConstruccion();
      if (_modo == ModoDigitalizacion.editarPoligono) {
        cancelarEdicionPoligono();
      }
      if (_modo == ModoDigitalizacion.editarPunto) {
        cancelarEdicionPunto();
      }
      _modo = ModoDigitalizacion.navegar;
      _idSeleccionado = null;
    } else {
      if (_modo == ModoDigitalizacion.editarPoligono && nuevoModo != ModoDigitalizacion.editarPoligono) {
        cancelarEdicionPoligono();
      }
      if (_modo == ModoDigitalizacion.editarPunto && nuevoModo != ModoDigitalizacion.editarPunto) {
        cancelarEdicionPunto();
      }
      _cancelarConstruccion();
      _modo = nuevoModo;
      // Conservar selección al entrar en modos de edición que dependen de ella.
      // Solo limpiar al ir a modos de creación o navegación pura.
      if (nuevoModo != ModoDigitalizacion.cortarLinea &&
          nuevoModo != ModoDigitalizacion.editarLinea &&
          nuevoModo != ModoDigitalizacion.editarPoligono &&
          nuevoModo != ModoDigitalizacion.editarPunto) {
        _idSeleccionado = null;
      }
    }
    notifyListeners();
  }

  /// Cancela la geometría en construcción y vuelve a modo navegar
  void cancelar() {
    _cancelarConstruccion();
    _modo = ModoDigitalizacion.navegar;
    notifyListeners();
  }

  void _cancelarConstruccion() {
    _verticesEnConstruccion.clear();
    _cursorPos = null;
    _snapActivo = null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // INTERACCIÓN CON EL MAPA
  // ────────────────────────────────────────────────────────────────────────────

  /// Procesa un tap en el mapa según el modo activo.
  ///
  /// Para Punto: retorna inmediatamente el [LatLng] para mostrar el formulario.
  /// Para Línea/Polígono: agrega un vértice y retorna null (sigue construyendo).
  LatLng? procesarTap(LatLng punto) {
    switch (_modo) {
      case ModoDigitalizacion.punto:
        return punto;

      case ModoDigitalizacion.linea:
      case ModoDigitalizacion.poligono:
        _verticesEnConstruccion.add(punto);
        notifyListeners();
        return null;

      default:
        return null;
    }
  }

  /// Actualiza la posición del cursor para el preview de la línea/polígono
  void actualizarCursor(LatLng posicion) {
    if (_modo == ModoDigitalizacion.linea || 
        _modo == ModoDigitalizacion.poligono || 
        _modo == ModoDigitalizacion.cortarLinea) {
      _cursorPos = posicion;
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SNAP TOPOLÓGICO
  // ────────────────────────────────────────────────────────────────────────────

  /// Calcula el snap más cercano al centro del mapa (crosshair) y actualiza
  /// [snapActivo]. Solo activo en modos: línea, polígono y cortarLinea.
  ///
  /// La conversión de coordenadas geográficas a píxeles se hace con la
  /// [camera] del FlutterMap para comparar correctamente con [snapRadiusPx].
  ///
  /// Prioridad: vértice exacto > punto sobre segmento.
  void calcularSnap(LatLng cursorLatLng, MapCamera camera) {
    if (_modo != ModoDigitalizacion.linea &&
        _modo != ModoDigitalizacion.poligono &&
        _modo != ModoDigitalizacion.cortarLinea) {
      if (_snapActivo != null) {
        _snapActivo = null;
        notifyListeners();
      }
      return;
    }

    final cursorPx = camera.getOffsetFromOrigin(cursorLatLng);

    double bestDistPx = double.infinity;
    SnapResult? best;

    // ── 1. Buscar snap a vértices (mayor prioridad) ───────────────────────
    void checkVertex(LatLng v) {
      final vPx = camera.getOffsetFromOrigin(v);
      final dx = vPx.dx - cursorPx.dx;
      final dy = vPx.dy - cursorPx.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= snapRadiusPx && dist < bestDistPx) {
        bestDistPx = dist;
        best = SnapResult(snapPoint: v, type: SnapType.vertex, distancePx: dist);
      }
    }

    for (final linea in lineas) {
      for (final v in linea.vertices) {
        checkVertex(v);
      }
    }
    for (final pol in poligonos) {
      for (final v in pol.vertices) {
        checkVertex(v);
      }
    }

    // ── 2. Si no hay snap a vértice, buscar en segmentos ──────────────────
    if (best == null) {
      void checkSegment(LatLng p1, LatLng p2) {
        final p1Px = camera.getOffsetFromOrigin(p1);
        final p2Px = camera.getOffsetFromOrigin(p2);

        final dx = p2Px.dx - p1Px.dx;
        final dy = p2Px.dy - p1Px.dy;
        final len2 = dx * dx + dy * dy;
        if (len2 < 1e-6) return;

        final cx = cursorPx.dx - p1Px.dx;
        final cy = cursorPx.dy - p1Px.dy;
        final t = ((cx * dx + cy * dy) / len2).clamp(0.0, 1.0);

        // Solo excluir extremos exactos (ya cubiertos por vertex check)
        if (t <= 0.01 || t >= 0.99) return;

        final projX = p1Px.dx + t * dx;
        final projY = p1Px.dy + t * dy;
        final distPx = math.sqrt(
            math.pow(cursorPx.dx - projX, 2) + math.pow(cursorPx.dy - projY, 2));

        if (distPx <= snapRadiusPx && distPx < bestDistPx) {
          bestDistPx = distPx;
          // Interpolar coordenada geográfica del punto proyectado
          final snapLat = p1.latitude + t * (p2.latitude - p1.latitude);
          final snapLng = p1.longitude + t * (p2.longitude - p1.longitude);
          best = SnapResult(
            snapPoint: LatLng(snapLat, snapLng),
            type: SnapType.segment,
            distancePx: distPx,
          );
        }
      }

      for (final linea in lineas) {
        final verts = linea.vertices;
        for (int i = 0; i < verts.length - 1; i++) {
          checkSegment(verts[i], verts[i + 1]);
        }
      }
      for (final pol in poligonos) {
        final verts = pol.vertices;
        for (int i = 0; i < verts.length; i++) {
          checkSegment(verts[i], verts[(i + 1) % verts.length]);
        }
      }
    }

    if (best != _snapActivo) {
      _snapActivo = best;
      notifyListeners();
    }
  }

  /// Limpia el snap activo (llamar al salir del modo de digitalización).
  void limpiarSnap() {
    if (_snapActivo != null) {
      _snapActivo = null;
      notifyListeners();
    }
  }

  /// Agrega un vértice a la geometría en construcción (línea, polígono o corte).
  /// Si hay un snap activo calculado por [calcularSnap], aplica el punto
  /// snapeado exacto en lugar de la posición del crosshair.
  void agregarVertice(LatLng punto) {
    if (_modo == ModoDigitalizacion.linea ||
        _modo == ModoDigitalizacion.poligono ||
        _modo == ModoDigitalizacion.cortarLinea) {
      // Aplicar snap si está activo
      final puntoFinal = _snapActivo?.snapPoint ?? punto;
      _verticesEnConstruccion.add(puntoFinal);
      notifyListeners();
    }
  }

  /// Procesa un doble-tap: finaliza la línea o polígono en construcción.
  /// Retorna true si hay suficientes vértices para finalizar.
  bool procesarDobleTap() {
    if (_modo == ModoDigitalizacion.linea && _verticesEnConstruccion.length >= 2) {
      return true; // El llamador muestra el formulario y luego llama finalizarLinea()
    }
    if (_modo == ModoDigitalizacion.poligono && _verticesEnConstruccion.length >= 3) {
      return true; // El llamador muestra el formulario y luego llama finalizarPoligono()
    }
    return false;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // CREACIÓN DE GEOMETRÍAS
  // ────────────────────────────────────────────────────────────────────────────

  /// Crea y registra un nuevo punto. Llamar tras obtener atributos del usuario.
  void crearPunto(PuntoEstructura punto, {String? createdBy, String? deviceId}) {
    // Si se pasan credenciales de auditoría, re-crear el punto con esos campos
    final puntoConAuditoria = createdBy != null || deviceId != null
        ? PuntoEstructura(
            id: punto.id,
            coordenadas: punto.coordenadas,
            nombre: punto.nombre,
            idCategoria: punto.idCategoria,
            idTipo: punto.idTipo,
            estado: punto.estado,
            nivelesCantidad: punto.nivelesCantidad,
            notas: punto.notas,
            fechaCreacion: punto.fechaCreacion,
            updatedAt: punto.updatedAt,
            syncDirty: punto.syncDirty,
            createdBy: createdBy ?? punto.createdBy,
            updatedBy: createdBy ?? punto.updatedBy,
            deviceId: deviceId ?? punto.deviceId,
            syncVersion: punto.syncVersion,
            niveles: punto.niveles,
          )
        : punto;

    puntos.add(puntoConAuditoria);
    notifyListeners();
    // Guardado persistente en SQLite local
    DatabaseHelper().saveEstructuraCompleta(puntoConAuditoria);
  }

  /// Registra un punto en memoria + SQLite localmente, SIN enviarlo a PostGIS.
  ///
  /// Usar cuando se quiere que el punto aparezca en el mapa inmediatamente
  /// (mientras el usuario llena el formulario de atributos) pero evitar la
  /// llamada al backend hasta tener los datos completos — así se garantiza que
  /// PostGIS recibe el INSERT solo una vez y sync_version queda en 0.
  void crearPuntoDraft(PuntoEstructura punto) {
    puntos.add(punto);
    notifyListeners();
    DatabaseHelper().saveEstructuraCompleta(punto);
  }

  /// Descarta un punto borrador (draft) en memoria y en SQLite cuando el usuario presiona "Cancelar".
  void descartarPuntoDraft(String id) {
    puntos.removeWhere((p) => p.id == id);
    DatabaseHelper().deleteEntity('estructuras', id);
    if (_idSeleccionado == id) _idSeleccionado = null;
    notifyListeners();
  }

  /// Finaliza la línea en construcción y la agrega a la colección.
  void finalizarLinea({
    required String nombre,
    TipoCamino tipo = TipoCamino.terraceria,
    String notas = '',
    String? createdBy,
    String? deviceId,
  }) {
    if (_verticesEnConstruccion.length < 2) return;
    final linea = LineaCamino.nuevo(
      vertices: List.from(_verticesEnConstruccion),
      nombre: nombre,
      tipo: tipo,
      notas: notas,
      createdBy: createdBy,
      deviceId: deviceId,
    );
    lineas.add(linea);
    DatabaseHelper().insertEntity('caminos', linea.toMapDB());
    
    _cancelarConstruccion();
    notifyListeners();
  }

  /// Finaliza el polígono en construcción y lo agrega a la colección.
  ///
  /// Si [autoEnsambladoPoligono] está activo, se aplica una operación de
  /// diferencia topológica contra todos los polígonos existentes, recortando
  /// cualquier área solapada antes de guardar el nuevo polígono.
  void finalizarPoligono({
    required String nombre,
    String codigoUPM = '',
    String notas = '',
    String? createdBy,
    String? deviceId,
  }) {
    if (_verticesEnConstruccion.length < 3) return;

    var vertices = List<LatLng>.from(_verticesEnConstruccion);

    // ── Auto-ensamblado topológico ─────────────────────────────────────────
    if (_autoEnsambladoPoligono && poligonos.isNotEmpty) {
      final existing = poligonos.map((p) => p.vertices).toList();
      vertices = PolygonClipper.differencePolygon(vertices, existing);

      if (vertices.length < 3) {
        // El nuevo polígono queda completamente dentro de uno existente
        _errorAutoEnsamblado =
            'El polígono digitado queda completamente cubierto por polígonos '
            'existentes. Verifique el área y vuelva a intentarlo.';
        _cancelarConstruccion();
        _modo = ModoDigitalizacion.navegar;
        notifyListeners();
        return;
      }
    }
    // ──────────────────────────────────────────────────────────────

    final poligono = PoligonoUPM.nuevo(
      vertices: vertices,
      nombre: nombre,
      codigoUPM: codigoUPM,
      notas: notas,
      createdBy: createdBy,
      deviceId: deviceId,
    );
    poligonos.add(poligono);
    DatabaseHelper().insertEntity('upm', poligono.toMapDB());

    _cancelarConstruccion();
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ELIMINACIÓN Y EDICIÓN
  // ────────────────────────────────────────────────────────────────────────────

  void eliminarPunto(String id, {String? updatedBy}) {
    // Soft-delete local: marcar como eliminado en lugar de borrar físicamente
    final index = puntos.indexWhere((p) => p.id == id);
    if (index != -1) {
      final puntoEliminado = PuntoEstructura(
        id: puntos[index].id,
        coordenadas: puntos[index].coordenadas,
        nombre: puntos[index].nombre,
        idCategoria: puntos[index].idCategoria,
        idTipo: puntos[index].idTipo,
        estado: puntos[index].estado,
        nivelesCantidad: puntos[index].nivelesCantidad,
        notas: puntos[index].notas,
        fechaCreacion: puntos[index].fechaCreacion,
        syncDirty: true,
        createdBy: puntos[index].createdBy,
        updatedBy: updatedBy ?? puntos[index].updatedBy,
        deviceId: puntos[index].deviceId,
        syncVersion: puntos[index].syncVersion,
        deletedAt: DateTime.now(),
        niveles: puntos[index].niveles,
      );
      DatabaseHelper().softDeleteEntity('estructuras', id);
      puntos.removeAt(index);
    }
    if (_idSeleccionado == id) _idSeleccionado = null;
    notifyListeners();
  }

  Future<void> actualizarPunto(PuntoEstructura puntoActualizado) async {
    final index = puntos.indexWhere((p) => p.id == puntoActualizado.id);
    if (index != -1) {
      puntos[index] = puntoActualizado;
      notifyListeners();
      try {
        await DatabaseHelper().actualizarEstructuraAtributos(puntoActualizado);
      } catch (e) {
        debugPrint('[DigitalizacionController] ❌ Error guardando atributos de punto en SQLite: $e');
      }
    }
  }

  void eliminarLinea(String id, {String? updatedBy}) {
    // Soft-delete local
    final index = lineas.indexWhere((l) => l.id == id);
    if (index != -1) {
      DatabaseHelper().softDeleteEntity('caminos', id);
      lineas.removeAt(index);
    }
    if (_idSeleccionado == id) _idSeleccionado = null;
    notifyListeners();
  }

  void eliminarPoligono(String id, {String? updatedBy}) {
    // Soft-delete local
    final index = poligonos.indexWhere((p) => p.id == id);
    if (index != -1) {
      DatabaseHelper().softDeleteEntity('upm', id);
      poligonos.removeAt(index);
    }
    if (_idSeleccionado == id) _idSeleccionado = null;
    notifyListeners();
  }

  void eliminarUltimoVertice() {
    if (_verticesEnConstruccion.isNotEmpty) {
      _verticesEnConstruccion.removeLast();
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SELECCIÓN Y EDICIÓN
  // ────────────────────────────────────────────────────────────────────────────

  void seleccionar(String? id) {
    _idSeleccionado = id;
    notifyListeners();
  }

  void seleccionarVerticeEdicion(int? index) {
    if (index == -1) index = null;
    _verticeEdicionIndex = index;
    notifyListeners();
  }

  /// Busca la entidad (Punto, Línea o Polígono) más cercana dentro de un radio de 12px.
  /// Prioridad en caso de colisión: Punto > Línea > Polígono.
  ResultadoSeleccion buscarEntidadCercana(LatLng tapPoint, MapCamera camera) {
    final tapPx = camera.getOffsetFromOrigin(tapPoint);
    const tolerancePx = snapRadiusPx; // 12.0 px
    final soloCapaActiva = _capaActivaId != null;

    // 1. Buscar en PUNTOS (solo si capa activa es '1' o no hay capa activa)
    if (_mostrarPuntos && (!soloCapaActiva || _capaActivaId == '1')) {
      double minPuntoDist = double.infinity;
      PuntoEstructura? closestPunto;
      for (final punto in puntos) {
        final puntoPx = camera.getOffsetFromOrigin(punto.coordenadas);
        final dx = puntoPx.dx - tapPx.dx;
        final dy = puntoPx.dy - tapPx.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= tolerancePx && dist < minPuntoDist) {
          minPuntoDist = dist;
          closestPunto = punto;
        }
      }
      if (closestPunto != null) {
        return PuntoSeleccionado(closestPunto);
      }
    }

    // 2. Buscar en LÍNEAS (solo si capa activa es '2' o no hay capa activa)
    if (_mostrarLineas && (!soloCapaActiva || _capaActivaId == '2')) {
      double minLineaDist = double.infinity;
      LineaCamino? closestLinea;
      for (final linea in lineas) {
        if (linea.vertices.length < 2) continue;
        for (int i = 0; i < linea.vertices.length - 1; i++) {
          final p1Px = camera.getOffsetFromOrigin(linea.vertices[i]);
          final p2Px = camera.getOffsetFromOrigin(linea.vertices[i + 1]);
          final distPx = _distanceToSegmentPx(tapPx, p1Px, p2Px);
          if (distPx <= tolerancePx && distPx < minLineaDist) {
            minLineaDist = distPx;
            closestLinea = linea;
          }
        }
      }
      if (closestLinea != null) {
        return LineaSeleccionada(closestLinea);
      }
    }

    // 3. Buscar en POLÍGONOS (solo si capa activa es '3' o no hay capa activa)
    if (_mostrarPoligonos && (!soloCapaActiva || _capaActivaId == '3')) {
      double minPolDist = double.infinity;
      PoligonoUPM? closestPoligono;

      for (final pol in poligonos) {
        if (pol.vertices.length < 3) continue;

        // a) Comprobar si el tap está dentro del polígono
        if (_pointInPolygon(tapPoint, pol.vertices)) {
          return PoligonoSeleccionado(pol);
        }

        // b) Comprobar distancia en píxeles a las aristas del polígono
        for (int i = 0; i < pol.vertices.length; i++) {
          final p1Px = camera.getOffsetFromOrigin(pol.vertices[i]);
          final p2Px = camera.getOffsetFromOrigin(pol.vertices[(i + 1) % pol.vertices.length]);
          final distPx = _distanceToSegmentPx(tapPx, p1Px, p2Px);
          if (distPx <= tolerancePx && distPx < minPolDist) {
            minPolDist = distPx;
            closestPoligono = pol;
          }
        }
      }
      if (closestPoligono != null) {
        return PoligonoSeleccionado(closestPoligono);
      }
    }

    return SinResultado();
  }

  double _distanceToSegmentPx(Offset p, Offset v, Offset w) {
    final dx = w.dx - v.dx;
    final dy = w.dy - v.dy;
    final l2 = dx * dx + dy * dy;
    if (l2 == 0) {
      final px = p.dx - v.dx;
      final py = p.dy - v.dy;
      return math.sqrt(px * px + py * py);
    }
    final t = (((p.dx - v.dx) * dx + (p.dy - v.dy) * dy) / l2).clamp(0.0, 1.0);
    final projX = v.dx + t * dx;
    final projY = v.dy + t * dy;
    final ex = p.dx - projX;
    final ey = p.dy - projY;
    return math.sqrt(ex * ex + ey * ey);
  }

  bool _pointInPolygon(LatLng point, List<LatLng> vs) {
    final x = point.longitude;
    final y = point.latitude;
    bool inside = false;
    for (int i = 0, j = vs.length - 1; i < vs.length; j = i++) {
      final xi = vs[i].longitude, yi = vs[i].latitude;
      final xj = vs[j].longitude, yj = vs[j].latitude;
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  // ── Métodos de Edición de Polígono ──────────────────────────────────────────

  void iniciarEdicionPoligono(String id) {
    final index = poligonos.indexWhere((p) => p.id == id);
    if (index == -1) return;

    _idSeleccionado = id;
    _idPoligonoEditando = id;
    _verticesPoligonoEdicion = List<LatLng>.from(poligonos[index].vertices);
    _verticesPoligonoEdicionOriginal = List<LatLng>.from(poligonos[index].vertices);
    _verticePoligonoIndex = null;
    _modo = ModoDigitalizacion.editarPoligono;
    notifyListeners();
  }

  void seleccionarVerticePoligono(int? index) {
    if (index == -1) index = null;
    _verticePoligonoIndex = index;
    notifyListeners();
  }

  void cancelarSeleccionVerticePoligono() {
    _verticePoligonoIndex = null;
    notifyListeners();
  }

  bool _esPoligonoAutoIntersectante(List<LatLng> verts) {
    final n = verts.length;
    if (n < 4) return false;
    for (int i = 0; i < n; i++) {
      final a1 = verts[i];
      final a2 = verts[(i + 1) % n];
      for (int j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue;
        final b1 = verts[j];
        final b2 = verts[(j + 1) % n];
        if (_segmentIntersectionWithT(a1, a2, b1, b2) != null) {
          return true;
        }
      }
    }
    return false;
  }

  bool confirmarMovimientoVerticePoligono(LatLng nuevaPos) {
    if (_idPoligonoEditando == null || _verticePoligonoIndex == null) return false;
    if (_verticePoligonoIndex! < 0 || _verticePoligonoIndex! >= _verticesPoligonoEdicion.length) return false;

    final tempVertices = List<LatLng>.from(_verticesPoligonoEdicion);
    tempVertices[_verticePoligonoIndex!] = nuevaPos;

    if (tempVertices.length < 3) {
      _ultimoMensaje = '⚠️ El polígono debe tener al menos 3 vértices';
      notifyListeners();
      return false;
    }

    if (_esPoligonoAutoIntersectante(tempVertices)) {
      _ultimoMensaje = '⚠️ La posición genera auto-intersección en el polígono';
      notifyListeners();
      return false;
    }

    _verticesPoligonoEdicion[_verticePoligonoIndex!] = nuevaPos;
    _verticePoligonoIndex = null;
    notifyListeners();
    return true;
  }

  void confirmarEdicionPoligono() {
    if (_idPoligonoEditando == null) return;
    final index = poligonos.indexWhere((p) => p.id == _idPoligonoEditando);
    if (index == -1) return;

    final original = poligonos[index];
    final modificada = PoligonoUPM(
      id: original.id,
      vertices: List<LatLng>.from(_verticesPoligonoEdicion),
      nombre: original.nombre,
      codigoUPM: original.codigoUPM,
      notas: original.notas,
      fechaCreacion: original.fechaCreacion,
      updatedAt: DateTime.now(),
      syncDirty: true,
      createdBy: original.createdBy,
      updatedBy: original.updatedBy,
      deviceId: original.deviceId,
      syncVersion: original.syncVersion,
    );

    poligonos[index] = modificada;
    DatabaseHelper().insertEntity('upm', modificada.toMapDB());

    _idPoligonoEditando = null;
    _verticePoligonoIndex = null;
    _verticesPoligonoEdicion = [];
    _verticesPoligonoEdicionOriginal = [];
    _modo = ModoDigitalizacion.navegar;
    notifyListeners();
  }

  // ── Drag Directo de Vértices de Polígono ─────────────────────────────────────

  void iniciarDragVerticePoligono(int index) {
    if (_idPoligonoEditando == null) return;
    if (index < 0 || index >= _verticesPoligonoEdicion.length) return;

    _indiceDragPoligonoActivo = index;
    _posicionDragPoligonoTemporal = _verticesPoligonoEdicion[index];
    _dragPoligonoActivo = true;
    notifyListeners();
  }

  void actualizarDragVerticePoligono(LatLng nuevaPos) {
    if (!_dragPoligonoActivo || _indiceDragPoligonoActivo == null) return;
    _posicionDragPoligonoTemporal = nuevaPos;
    notifyListeners();
  }

  bool get dragPoligonoAutoIntersecta {
    if (!_dragPoligonoActivo || _indiceDragPoligonoActivo == null || _posicionDragPoligonoTemporal == null) return false;
    final tempVertices = List<LatLng>.from(_verticesPoligonoEdicion);
    tempVertices[_indiceDragPoligonoActivo!] = _posicionDragPoligonoTemporal!;
    return _esPoligonoAutoIntersectante(tempVertices);
  }

  bool confirmarDragVerticePoligono(LatLng posicionFinal) {
    if (!_dragPoligonoActivo || _idPoligonoEditando == null || _indiceDragPoligonoActivo == null) return false;

    final tempVertices = List<LatLng>.from(_verticesPoligonoEdicion);
    tempVertices[_indiceDragPoligonoActivo!] = posicionFinal;

    if (tempVertices.length < 3) {
      _ultimoMensaje = '⚠️ El polígono debe tener al menos 3 vértices';
      cancelarDragVerticePoligono();
      return false;
    }

    if (_esPoligonoAutoIntersectante(tempVertices)) {
      _ultimoMensaje = '⚠️ La posición genera auto-intersección en el polígono';
      cancelarDragVerticePoligono();
      return false;
    }

    _verticesPoligonoEdicion[_indiceDragPoligonoActivo!] = posicionFinal;
    _dragPoligonoActivo = false;
    _indiceDragPoligonoActivo = null;
    _posicionDragPoligonoTemporal = null;
    notifyListeners();
    return true;
  }

  void cancelarDragVerticePoligono() {
    _dragPoligonoActivo = false;
    _indiceDragPoligonoActivo = null;
    _posicionDragPoligonoTemporal = null;
    notifyListeners();
  }

  // Stack de deshacer para inserción de vértices
  final List<(String id, int indexInsertado)> _historialInsercionVertices = [];
  bool get puedeDeshacerInsercionVertice => _historialInsercionVertices.isNotEmpty;

  /// Deshace la última inserción de vértice realizada en modo edición.
  bool deshacerUltimaInsercionVertice() {
    if (_historialInsercionVertices.isEmpty) return false;
    final (id, indexInsertado) = _historialInsercionVertices.removeLast();

    if (_modo == ModoDigitalizacion.editarLinea) {
      final lineaIndex = lineas.indexWhere((l) => l.id == id);
      if (lineaIndex != -1) {
        final original = lineas[lineaIndex];
        if (indexInsertado >= 0 && indexInsertado < original.vertices.length && original.vertices.length > 2) {
          final nuevosVerts = List<LatLng>.from(original.vertices);
          nuevosVerts.removeAt(indexInsertado);
          final modificada = LineaCamino(
            id: original.id,
            vertices: nuevosVerts,
            nombre: original.nombre,
            tipo: original.tipo,
            notas: original.notas,
            fechaCreacion: original.fechaCreacion,
            createdBy: original.createdBy,
            updatedBy: original.updatedBy,
            deviceId: original.deviceId,
            syncVersion: original.syncVersion,
          );
          lineas[lineaIndex] = modificada;
          DatabaseHelper().insertEntity('caminos', modificada.toMapDB());
          _ultimoMensaje = '↩ Vértice removido de la línea';
          notifyListeners();
          return true;
        }
      }
    } else if (_modo == ModoDigitalizacion.editarPoligono) {
      if (_idPoligonoEditando == id &&
          indexInsertado >= 0 &&
          indexInsertado < _verticesPoligonoEdicion.length &&
          _verticesPoligonoEdicion.length > 3) {
        _verticesPoligonoEdicion.removeAt(indexInsertado);
        _ultimoMensaje = '↩ Vértice removido del polígono';
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void cancelarEdicionPoligono() {
    _modoAgregarVertice = false;
    _historialInsercionVertices.clear();
    _dragPoligonoActivo = false;
    _indiceDragPoligonoActivo = null;
    _posicionDragPoligonoTemporal = null;
    _idPoligonoEditando = null;
    _verticePoligonoIndex = null;
    _verticesPoligonoEdicion = [];
    _verticesPoligonoEdicionOriginal = [];
    if (_modo == ModoDigitalizacion.editarPoligono) {
      _modo = ModoDigitalizacion.navegar;
    }
    notifyListeners();
  }

  void actualizarAtributosPoligonoSeleccionado(String nombre, String codigoUPM) {
    if (_idSeleccionado == null) return;
    final index = poligonos.indexWhere((p) => p.id == _idSeleccionado);
    if (index == -1) return;

    final original = poligonos[index];
    final modificada = PoligonoUPM(
      id: original.id,
      vertices: original.vertices,
      nombre: nombre,
      codigoUPM: codigoUPM,
      notas: original.notas,
      fechaCreacion: original.fechaCreacion,
      updatedAt: DateTime.now(),
      syncDirty: true,
      createdBy: original.createdBy,
      updatedBy: original.updatedBy,
      deviceId: original.deviceId,
      syncVersion: original.syncVersion,
    );

    poligonos[index] = modificada;
    DatabaseHelper().insertEntity('upm', modificada.toMapDB());
    notifyListeners();
  }

  /// Busca la línea más cercana al punto tocado (máx ~15m) - Deprecado pero mantenido para compatibilidad
  LineaCamino? buscarLineaCercana(LatLng tapPoint) {
    const distanceCalc = Distance();
    double minDistance = double.infinity;
    LineaCamino? closestLine;

    for (final linea in lineas) {
      if (linea.vertices.length < 2) continue;
      
      for (int i = 0; i < linea.vertices.length - 1; i++) {
        final p1 = linea.vertices[i];
        final p2 = linea.vertices[i + 1];
        
        final dist = _distanceToSegment(tapPoint, p1, p2, distanceCalc);
        if (dist < minDistance && dist <= 15.0) {
          minDistance = dist;
          closestLine = linea;
        }
      }
    }
    return closestLine;
  }

  double _distanceToSegment(LatLng p, LatLng v, LatLng w, Distance distCalc) {
    // Proyección equirrectangular local aproximada
    final latMid = (v.latitude + w.latitude) / 2.0;
    final cosLat = math.cos(latMid * math.pi / 180.0);
    
    final dx1 = (w.longitude - v.longitude) * cosLat;
    final dy1 = (w.latitude - v.latitude);
    final l2 = dx1 * dx1 + dy1 * dy1;
    
    if (l2 == 0) return distCalc.distance(p, v);
    
    final dx2 = (p.longitude - v.longitude) * cosLat;
    final dy2 = (p.latitude - v.latitude);
    
    final t = (dx2 * dx1 + dy2 * dy1) / l2;
    final tClamped = t.clamp(0.0, 1.0);
               
    final proj = LatLng(v.latitude + tClamped * (w.latitude - v.latitude), v.longitude + tClamped * (w.longitude - v.longitude));
    return distCalc.distance(p, proj);
  }

  void actualizarAtributosLineaSeleccionada(String descripcion, TipoCamino tipo) {
    if (_idSeleccionado == null) return;
    final index = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (index == -1) return;

    final original = lineas[index];
    final modificada = LineaCamino(
      id: original.id,
      vertices: original.vertices,
      nombre: descripcion,
      tipo: tipo,
      notas: original.notas,
      fechaCreacion: original.fechaCreacion,
      updatedAt: DateTime.now(),
      syncDirty: true,
      createdBy: original.createdBy,
      updatedBy: original.updatedBy,
      deviceId: original.deviceId,
      syncVersion: original.syncVersion,
    );

    lineas[index] = modificada;
    DatabaseHelper().insertEntity('caminos', modificada.toMapDB());
    notifyListeners();
  }

  void confirmarMovimientoVertice(LatLng nuevaPos) {
    if (_idSeleccionado == null || _verticeEdicionIndex == null) return;
    final index = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (index == -1) return;

    final original = lineas[index];
    final nuevosVertices = List<LatLng>.from(original.vertices);
    nuevosVertices[_verticeEdicionIndex!] = nuevaPos;

    final modificada = LineaCamino(
      id: original.id,
      vertices: nuevosVertices,
      nombre: original.nombre,
      tipo: original.tipo,
      notas: original.notas,
      fechaCreacion: original.fechaCreacion,
      updatedAt: DateTime.now(),
      syncDirty: true,
      createdBy: original.createdBy,
      updatedBy: original.updatedBy,
      deviceId: original.deviceId,
      syncVersion: original.syncVersion,
    );

    lineas[index] = modificada;
    DatabaseHelper().insertEntity('caminos', modificada.toMapDB());
    
    _verticeEdicionIndex = null;
    notifyListeners();
  }

  // ── Drag Directo de Vértices de Línea ─────────────────────────────────────

  void iniciarDragVerticeLinea(int index) {
    if (_idSeleccionado == null) return;
    final lineaIndex = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (lineaIndex == -1) return;
    final linea = lineas[lineaIndex];
    if (index < 0 || index >= linea.vertices.length) return;

    _indiceDragLineaActivo = index;
    _verticesLineaEdicionOriginal = List<LatLng>.from(linea.vertices);
    _posicionDragLineaTemporal = linea.vertices[index];
    _dragLineaActivo = true;
    notifyListeners();
  }

  void actualizarDragVerticeLinea(LatLng nuevaPos) {
    if (!_dragLineaActivo || _indiceDragLineaActivo == null) return;
    _posicionDragLineaTemporal = nuevaPos;
    notifyListeners();
  }

  void confirmarDragVerticeLinea(LatLng posicionFinal) {
    if (!_dragLineaActivo || _idSeleccionado == null || _indiceDragLineaActivo == null) return;
    final lineaIndex = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (lineaIndex != -1) {
      final original = lineas[lineaIndex];
      final nuevosVertices = List<LatLng>.from(original.vertices);
      nuevosVertices[_indiceDragLineaActivo!] = posicionFinal;

      final modificada = LineaCamino(
        id: original.id,
        vertices: nuevosVertices,
        nombre: original.nombre,
        tipo: original.tipo,
        notas: original.notas,
        fechaCreacion: original.fechaCreacion,
        updatedAt: DateTime.now(),
        syncDirty: true,
        createdBy: original.createdBy,
        updatedBy: original.updatedBy,
        deviceId: original.deviceId,
        syncVersion: original.syncVersion,
      );

      lineas[lineaIndex] = modificada;
      DatabaseHelper().insertEntity('caminos', modificada.toMapDB());
    }

    _dragLineaActivo = false;
    _indiceDragLineaActivo = null;
    _posicionDragLineaTemporal = null;
    _verticesLineaEdicionOriginal = [];
    notifyListeners();
  }

  void cancelarDragVerticeLinea() {
    _dragLineaActivo = false;
    _indiceDragLineaActivo = null;
    _posicionDragLineaTemporal = null;
    _verticesLineaEdicionOriginal = [];
    notifyListeners();
  }

  void cancelarEdicionLinea() {
    _modoAgregarVertice = false;
    _historialInsercionVertices.clear();
    _dragLineaActivo = false;
    _indiceDragLineaActivo = null;
    _posicionDragLineaTemporal = null;
    _verticesLineaEdicionOriginal = [];
    _verticeEdicionIndex = null;
    if (_modo == ModoDigitalizacion.editarLinea) {
      _modo = ModoDigitalizacion.navegar;
    }
    notifyListeners();
  }

  // ── Drag Directo de Punto ───────────────────────────────────────────────

  void iniciarDragPunto(String puntoId) {
    final index = puntos.indexWhere((p) => p.id == puntoId);
    if (index == -1) return;

    _idSeleccionado = puntoId;
    _posicionOriginalPunto = puntos[index].coordenadas;
    _posicionDragPuntoTemporal = puntos[index].coordenadas;
    _dragPuntoActivo = true;
    _modo = ModoDigitalizacion.editarPunto;
    notifyListeners();
  }

  void actualizarDragPunto(LatLng nuevaPos) {
    if (!_dragPuntoActivo) return;
    _posicionDragPuntoTemporal = nuevaPos;
    notifyListeners();
  }

  void confirmarDragPunto(LatLng posicionFinal) {
    if (_idSeleccionado == null) return;
    final index = puntos.indexWhere((p) => p.id == _idSeleccionado);
    if (index != -1) {
      final original = puntos[index];
      final modificada = PuntoEstructura(
        id: original.id,
        coordenadas: posicionFinal,
        nombre: original.nombre,
        idCategoria: original.idCategoria,
        idTipo: original.idTipo,
        estado: original.estado,
        nivelesCantidad: original.nivelesCantidad,
        notas: original.notas,
        niveles: original.niveles,
        fechaCreacion: original.fechaCreacion,
        createdBy: original.createdBy,
        updatedBy: original.updatedBy,
        deviceId: original.deviceId,
        syncVersion: original.syncVersion,
        updatedAt: DateTime.now(),
        syncDirty: true,
      );

      actualizarPunto(modificada);
      _ultimoMensaje = '✅ Ubicación de estructura "${original.nombre.isEmpty ? 'sin nombre' : original.nombre}" actualizada';
    }

    _dragPuntoActivo = false;
    _posicionDragPuntoTemporal = null;
    _posicionOriginalPunto = null;
    _modo = ModoDigitalizacion.navegar;
    notifyListeners();
  }

  void cancelarDragPunto() {
    _dragPuntoActivo = false;
    _posicionDragPuntoTemporal = null;
    _posicionOriginalPunto = null;
    _modo = ModoDigitalizacion.navegar;
    notifyListeners();
  }

  void cancelarEdicionPunto() {
    _dragPuntoActivo = false;
    _posicionDragPuntoTemporal = null;
    _posicionOriginalPunto = null;
    if (_modo == ModoDigitalizacion.editarPunto) {
      _modo = ModoDigitalizacion.navegar;
    }
    notifyListeners();
  }

  /// Ejecuta el corte de la línea seleccionada contra la línea temporal de corte.
  ///
  /// Detecta TODAS las intersecciones y genera N+1 segmentos.
  /// Conserva todos los atributos de la línea original en cada segmento.
  /// Registra la operación en el historial para permitir Deshacer.
  /// Retorna [ResultadoCorte] con el resultado de la operación.
  ResultadoCorte ejecutarCorteLinea() {
    // ── Validaciones previas ─────────────────────────────────────────────
    if (!_modoEdicion) return ResultadoCorte.sinModoEdicion;
    if (_idSeleccionado == null) return ResultadoCorte.sinSeleccion;
    if (_verticesEnConstruccion.length < 2) return ResultadoCorte.lineaCorteInvalida;

    final index = lineas.indexWhere((l) => l.id == _idSeleccionado);
    if (index == -1) return ResultadoCorte.sinSeleccion;

    final original = lineas[index];
    if (original.vertices.length < 2) return ResultadoCorte.lineaCorteInvalida;

    // ── Paso 1: Recolectar TODAS las intersecciones ──────────────────────
    // Cada intersección se representa como (segmentoIndex, t, punto)
    // donde t ∈ [0,1] es la posición paramétrica sobre el segmento original.
    final List<_PuntoCorte> intersecciones = [];

    for (int i = 0; i < original.vertices.length - 1; i++) {
      final p1 = original.vertices[i];
      final p2 = original.vertices[i + 1];

      for (int j = 0; j < _verticesEnConstruccion.length - 1; j++) {
        final p3 = _verticesEnConstruccion[j];
        final p4 = _verticesEnConstruccion[j + 1];

        final resultado = _segmentIntersectionWithT(p1, p2, p3, p4);
        if (resultado != null) {
          final (punto, t) = resultado;
          intersecciones.add(_PuntoCorte(segmentoIdx: i, t: t, punto: punto));
        }
      }
    }

    if (intersecciones.isEmpty) {
      _verticesEnConstruccion.clear();
      _modo = ModoDigitalizacion.navegar;
      notifyListeners();
      return ResultadoCorte.sinInterseccion;
    }

    // ── Paso 2: Ordenar por posición en la línea original ────────────────
    // Primero por índice de segmento, luego por t dentro del segmento.
    intersecciones.sort((a, b) {
      if (a.segmentoIdx != b.segmentoIdx) {
        return a.segmentoIdx.compareTo(b.segmentoIdx);
      }
      return a.t.compareTo(b.t);
    });

    // ── Paso 3: Eliminar intersecciones duplicadas (tolerancia 1e-9) ─────
    final List<_PuntoCorte> unicas = [];
    for (final pc in intersecciones) {
      if (unicas.isEmpty ||
          (pc.segmentoIdx != unicas.last.segmentoIdx ||
              (pc.t - unicas.last.t).abs() > 1e-9)) {
        unicas.add(pc);
      }
    }

    // ── Paso 4: Construir los segmentos resultantes ──────────────────────
    // Insertamos los puntos de corte en la geometría original y partimos.
    final List<List<LatLng>> segmentosVertices = [];
    List<LatLng> segmentoActual = [original.vertices[0]];

    int corteIdx = 0;
    for (int i = 0; i < original.vertices.length - 1; i++) {
      // Agregar todos los puntos de corte que caen en este segmento
      while (corteIdx < unicas.length && unicas[corteIdx].segmentoIdx == i) {
        final pc = unicas[corteIdx];
        segmentoActual.add(pc.punto);
        // Cerrar el segmento actual y abrir uno nuevo desde el punto de corte
        segmentosVertices.add(List.from(segmentoActual));
        segmentoActual = [pc.punto];
        corteIdx++;
      }
      // Agregar el vértice final del segmento original
      segmentoActual.add(original.vertices[i + 1]);
    }
    segmentosVertices.add(segmentoActual); // Último segmento

    // ── Paso 5: Filtrar segmentos de longitud cero ───────────────────────
    const distCalc = Distance();
    const double toleranciaMetros = 0.01; // 1 cm
    final List<List<LatLng>> segmentosValidos = segmentosVertices.where((verts) {
      if (verts.length < 2) return false;
      double longitud = 0;
      for (int i = 0; i < verts.length - 1; i++) {
        longitud += distCalc.distance(verts[i], verts[i + 1]);
      }
      return longitud > toleranciaMetros;
    }).toList();

    if (segmentosValidos.length < 2) {
      // No se generaron segmentos válidos
      _verticesEnConstruccion.clear();
      _modo = ModoDigitalizacion.navegar;
      notifyListeners();
      return ResultadoCorte.sinInterseccion;
    }

    // ── Paso 6: Crear las nuevas entidades conservando atributos ─────────
    final List<LineaCamino> nuevasLineas = segmentosValidos.map((verts) {
      return LineaCamino.nuevo(
        vertices: verts,
        nombre: original.nombre,
        tipo: original.tipo,
        notas: original.notas,
      );
    }).toList();

    // ── Paso 7: Registrar en historial (Undo) ────────────────────────────
    final operacion = _OperacionCorte(
      lineaOriginal: original,
      segmentosGenerados: nuevasLineas,
      insertIndex: index,
    );
    _historialCorte.add(operacion);
    if (_historialCorte.length > _maxHistorial) {
      _historialCorte.removeAt(0);
    }

    // ── Paso 8: Persistir — borrar original e insertar segmentos ─────────
    lineas.removeWhere((l) => l.id == original.id);
    DatabaseHelper().deleteEntity('caminos', original.id);

    for (int i = 0; i < nuevasLineas.length; i++) {
      lineas.insert(index + i, nuevasLineas[i]);
      DatabaseHelper().insertEntity('caminos', nuevasLineas[i].toMapDB());
    }

    // ── Paso 9: Limpiar estado — mantener modo edición activo ────────────
    _verticesEnConstruccion.clear();
    _idSeleccionado = null;
    _modo = ModoDigitalizacion.navegar; // Vuelve a navegar pero edición sigue activa
    notifyListeners();
    return ResultadoCorte.ok;
  }

  /// Deshace el último corte realizado en esta sesión.
  ///
  /// Elimina los segmentos generados y restaura la línea original.
  /// Retorna true si se pudo deshacer.
  bool deshacerUltimoCorte() {
    if (_historialCorte.isEmpty) return false;

    final operacion = _historialCorte.removeLast();
    final original = operacion.lineaOriginal;
    final segmentos = operacion.segmentosGenerados;

    // Eliminar los segmentos de la lista y la BD local
    for (final seg in segmentos) {
      lineas.removeWhere((l) => l.id == seg.id);
      DatabaseHelper().deleteEntity('caminos', seg.id);
    }

    // Restaurar la línea original en la posición correcta
    final insertIdx = operacion.insertIndex.clamp(0, lineas.length);
    lineas.insert(insertIdx, original);
    DatabaseHelper().insertEntity('caminos', original.toMapDB());

    _idSeleccionado = null;
    notifyListeners();
    return true;
  }

  /// Versión extendida de _segmentIntersection que devuelve también el parámetro t
  /// para ordenar múltiples intersecciones dentro de un mismo segmento.
  (LatLng, double)? _segmentIntersectionWithT(
      LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    double s1x = p2.longitude - p1.longitude;
    double s1y = p2.latitude - p1.latitude;
    double s2x = p4.longitude - p3.longitude;
    double s2y = p4.latitude - p3.latitude;

    double denom = -s2x * s1y + s1x * s2y;
    if (denom.abs() < 1e-12) return null; // Paralelos o colineales

    double s = (-s1y * (p1.longitude - p3.longitude) +
            s1x * (p1.latitude - p3.latitude)) /
        denom;
    double t = (s2x * (p1.latitude - p3.latitude) -
            s2y * (p1.longitude - p3.longitude)) /
        denom;

    if (s >= 0 && s <= 1 && t >= 0 && t <= 1) {
      final punto = LatLng(
          p1.latitude + (t * s1y), p1.longitude + (t * s1x));
      return (punto, t);
    }
    return null;
  }

  LatLng? _segmentIntersection(LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    final resultado = _segmentIntersectionWithT(p1, p2, p3, p4);
    return resultado?.$1;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SERIALIZACIÓN
  // ────────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> capasAJson() => {
        'puntos': puntos.map((p) => p.toJson()).toList(),
        'lineas': lineas.map((l) => l.toJson()).toList(),
        'poligonos': poligonos.map((p) => p.toJson()).toList(),
      };

  /// Carga offline-first: siempre lee primero de SQLite local (fuente de verdad local).
  /// Si hay conexión con PostGIS, actualiza el estado online y la lista de capas activas.
  Future<void> cargarDesdePostGIS() async {
    _cargandoPostGIS = true;
    notifyListeners();

    try {
      // 1. Cargar SIEMPRE primero desde la base de datos local SQLite
      await cargarDesdeBD();

      // 2. Verificar conexión con el backend y obtener capas activas si está disponible
      final service = PostGISService();
      final activas = await service.getCapasActivas();
      if (activas.isNotEmpty) {
        _capasRegistro = activas;
        _onlinePostGIS = true;
      }
    } catch (e) {
      debugPrint('[DigitalizacionController] Sin conexión a PostGIS o error: $e');
      _onlinePostGIS = false;
    } finally {
      _cargandoPostGIS = false;
      notifyListeners();
    }
  }

  Future<bool> sincronizarOfflineBatch({String? userId, String? deviceId}) async {
    final service = PostGISService();
    final db = await DatabaseHelper().database;

    // 1. Filtrar geometrías marcadas con syncDirty
    final dirtyPuntos = puntos.where((p) => p.syncDirty).toList();
    final dirtyLineas = lineas.where((l) => l.syncDirty).toList();
    final dirtyPoligonos = poligonos.where((p) => p.syncDirty && p.id != 'default_upm').toList();

    // 2. Leer niveles, locales y hogares con sync_dirty = 1 desde SQLite
    List<Map<String, dynamic>> nivelesMaps = [];
    List<Map<String, dynamic>> localesMaps = [];
    List<Map<String, dynamic>> hogaresMaps = [];

    try {
      final rawNiveles = await db.query('niveles', where: 'sync_dirty = 1');
      final rawLocales = await db.query('locales', where: 'sync_dirty = 1');
      final rawHogares = await db.query('hogares', where: 'sync_dirty = 1');

      nivelesMaps = rawNiveles.map((n) => {
        'id': n['id'] as String,
        'estructura_id': n['estructura_id'] as String,
        'numero': (n['numero'] as num).toInt(),
        'numero_locales': (n['numero_locales'] as num?)?.toInt() ?? 1,
        'updated_at': n['updated_at'] as String?,
      }).toList();

      localesMaps = rawLocales.map((l) => {
        'id': l['id'] as String,
        'nivel_id': l['nivel_id'] as String,
        'nombre_local': (l['nombre'] ?? l['nombre_local']) as String?,
        'id_tipo': (l['id_tipo'] as num?)?.toInt() ?? 1,
        'id_condicion_local': l['id_condicion_local'] != null ? (l['id_condicion_local'] as num).toInt() : null,
        'numero_hogares': l['numero_hogares'] != null ? (l['numero_hogares'] as num).toInt() : null,
        'descripcion': l['descripcion'] as String?,
        'updated_at': l['updated_at'] as String?,
      }).toList();

      hogaresMaps = rawHogares.map((h) => {
        'id': h['id'] as String,
        'local_id': h['local_id'] as String,
        'jefe_familia': h['jefe_familia'] as String? ?? '',
        'id_sexo': h['id_sexo'] != null ? (h['id_sexo'] as num).toInt() : null,
        'id_idioma': h['id_idioma'] != null ? (h['id_idioma'] as num).toInt() : null,
        'direccion': h['direccion'] as String?,
        'total_habitantes': (h['total_habitantes'] as num?)?.toInt() ?? 0,
        'personas_0_5': (h['personas_0_5'] as num?)?.toInt() ?? 0,
        'personas_6_11': (h['personas_6_11'] as num?)?.toInt() ?? 0,
        'personas_12_17': (h['personas_12_17'] as num?)?.toInt() ?? 0,
        'personas_18_23': (h['personas_18_23'] as num?)?.toInt() ?? 0,
        'personas_24_34': (h['personas_24_34'] as num?)?.toInt() ?? 0,
        'personas_35_44': (h['personas_35_44'] as num?)?.toInt() ?? 0,
        'personas_45_59': (h['personas_45_59'] as num?)?.toInt() ?? 0,
        'personas_60_69': (h['personas_60_69'] as num?)?.toInt() ?? 0,
        'personas_70_79': (h['personas_70_79'] as num?)?.toInt() ?? 0,
        'personas_80_mas': (h['personas_80_mas'] as num?)?.toInt() ?? 0,
        'personas_no_edad': (h['personas_no_edad'] as num?)?.toInt() ?? 0,
        'updated_at': h['updated_at'] as String?,
      }).toList();
    } catch (e) {
      debugPrint('[DigitalizacionController] Error consultando jerarquía dirty en SQLite: $e');
    }

    if (dirtyPuntos.isEmpty &&
        dirtyLineas.isEmpty &&
        dirtyPoligonos.isEmpty &&
        nivelesMaps.isEmpty &&
        localesMaps.isEmpty &&
        hogaresMaps.isEmpty) {
      debugPrint('[DigitalizacionController] ℹ️ Nada pendiente por sincronizar');
      return true;
    }

    debugPrint('[DigitalizacionController] 📤 Iniciando sincronización por lote: ${dirtyPuntos.length} puntos, ${dirtyLineas.length} líneas, ${dirtyPoligonos.length} polígonos, ${nivelesMaps.length} niveles, ${localesMaps.length} locales, ${hogaresMaps.length} hogares');

    try {
      final ok = await service.sincronizarOfflineBatch(
        puntos: dirtyPuntos,
        lineas: dirtyLineas,
        poligonos: dirtyPoligonos,
        niveles: nivelesMaps,
        locales: localesMaps,
        hogares: hogaresMaps,
        userId: userId,
        deviceId: deviceId,
      );

      if (ok) {
        _onlinePostGIS = true;
        try {
          await db.transaction((txn) async {
            await txn.rawUpdate('UPDATE estructuras SET sync_dirty = 0 WHERE sync_dirty = 1');
            await txn.rawUpdate('UPDATE caminos SET sync_dirty = 0 WHERE sync_dirty = 1');
            await txn.rawUpdate('UPDATE upm SET sync_dirty = 0 WHERE sync_dirty = 1');
            await txn.rawUpdate('UPDATE niveles SET sync_dirty = 0 WHERE sync_dirty = 1');
            await txn.rawUpdate('UPDATE locales SET sync_dirty = 0 WHERE sync_dirty = 1');
            await txn.rawUpdate('UPDATE hogares SET sync_dirty = 0 WHERE sync_dirty = 1');
          });
          debugPrint('[DigitalizacionController] ✅ sync_dirty limpiado exitosamente en SQLite');
        } catch (e) {
          debugPrint('[DigitalizacionController] ⚠️ Error actualizando sync_dirty en SQLite: $e');
        }
        await cargarDesdeBD();
        return true;
      } else {
        debugPrint('[DigitalizacionController] ❌ El servidor rechazó la sincronización por lote');
        return false;
      }
    } catch (e, stack) {
      debugPrint('[DigitalizacionController] ❌ Excepción en sincronizarOfflineBatch: $e\n$stack');
      return false;
    }
  }

  /// Sincroniza cambios locales a Postgres y luego reemplaza la base local
  /// y la memoria con los datos más recientes descargados directamente de Postgres.
  Future<({bool exito, bool offline, String mensaje})> sincronizarYActualizar({
    String? userId,
    String? deviceId,
  }) async {
    final service = PostGISService();

    // 1. Probar conectividad
    debugPrint('[DigitalizacionController] 🔍 Verificando conectividad con el backend...');
    final online = await service.probeAndFixBaseUrl();
    if (!online) {
      debugPrint('[DigitalizacionController] 📡 Backend no disponible (modo offline)');
      _onlinePostGIS = false;
      notifyListeners();
      return (
        exito: false,
        offline: true,
        mensaje: 'Actualmente está en modo offline por lo que no se puede realizar la operación.',
      );
    }

    _onlinePostGIS = true;

    // 2. Subir primero todos los cambios pendientes
    debugPrint('[DigitalizacionController] ⬆️ Paso 1: Subiendo cambios locales pendientes...');
    final subidaOk = await sincronizarOfflineBatch(userId: userId, deviceId: deviceId);
    if (!subidaOk) {
      return (
        exito: false,
        offline: false,
        mensaje: 'Error subiendo los cambios locales a Postgres.',
      );
    }

    // 3. Descargar todos los registros directamente desde Postgres
    debugPrint('[DigitalizacionController] ⬇️ Paso 2: Descargando datos completos desde Postgres...');
    try {
      final nuevasEstructuras = await service.getEstructuras();
      final nuevosCaminos = await service.getCaminos();
      final nuevasUPMs = await service.getUPMs();
      debugPrint('[DigitalizacionController] 📦 Descargados: ${nuevasEstructuras.length} estructuras, ${nuevosCaminos.length} caminos, ${nuevasUPMs.length} UPMs');

      // 4. Reemplazar SQLite local con los datos descargados
      debugPrint('[DigitalizacionController] 💾 Paso 3: Reemplazando SQLite local...');
      await DatabaseHelper().reemplazarTodoDesdeServidor(
        estructuras: nuevasEstructuras,
        caminos: nuevosCaminos,
        upms: nuevasUPMs,
      );

      // 5. Recargar la memoria de la aplicación
      debugPrint('[DigitalizacionController] 🔄 Paso 4: Recargando estado en memoria...');
      await cargarDesdeBD();

      debugPrint('[DigitalizacionController] ✅ Sinc & Update completado con éxito');
      return (
        exito: true,
        offline: false,
        mensaje: 'Proyecto sincronizado',
      );
    } catch (e, stack) {
      debugPrint('[DigitalizacionController] ❌ Error descargando desde Postgres: $e\n$stack');
      return (
        exito: false,
        offline: false,
        mensaje: 'Los datos locales se subieron pero ocurrió un error al actualizar: $e',
      );
    }
  }

  /// Verifica cuántos elementos locales NO están en PostGIS.
  /// Compara el conteo local contra el conteo real del servidor.
  /// Retorna:
  ///   - `null`  → No hay conexión con PostGIS (no se puede verificar).
  ///   - `0`     → Todos los elementos están guardados en PostGIS.
  ///   - `N > 0` → Hay N elementos que faltan en PostGIS.
  Future<int?> verificarElementosSinGuardar() async {
    final service = PostGISService();
    final conteoServidor = await service.contarElementosEnPostGIS();

    if (conteoServidor == null) {
      return null;
    }

    final localTotal = puntos.length + lineas.length + poligonos.length;
    final servidorTotal = (conteoServidor['puntos'] ?? 0)
        + (conteoServidor['lineas'] ?? 0)
        + (conteoServidor['poligonos'] ?? 0);

    final faltantes = localTotal - servidorTotal;
    return faltantes > 0 ? faltantes : 0;
  }

  Future<void> cargarDesdeBD() async {
    final dbHelper = DatabaseHelper();
    final polyRegex = RegExp(r'POLYGON\s*\(\((.*?)\)\)', caseSensitive: false);
    final lineRegex = RegExp(r'LINESTRING\s*\((.*?)\)', caseSensitive: false);
    
    // 1. Cargar UPMs (Polígonos)
    final upmsData = await dbHelper.queryAll('upm');
    poligonos.clear();
    for (var u in upmsData) {
      try {
        final geomStr = u['geom_wkt'] as String?;
        if (geomStr == null) continue;
        final match = polyRegex.firstMatch(geomStr);
        if (match != null) {
          final ptsStr = match.group(1)!;
          final pairs = ptsStr.split(',');
          List<LatLng> verts = [];
          for (var pair in pairs) {
            final xy = pair.trim().split(' ');
            if (xy.length >= 2) {
              verts.add(LatLng(double.parse(xy[1]), double.parse(xy[0])));
            }
          }
          if (verts.isNotEmpty) {
            poligonos.add(PoligonoUPM(
              id: u['id'] as String,
              vertices: verts,
              nombre: (u['nombre'] as String?)?.isNotEmpty == true ? u['nombre'] as String : 'UPM',
              codigoUPM: u['codigo_upm'] as String? ?? '',
              notas: u['notas'] as String? ?? '',
              updatedAt: u['updated_at'] != null ? DateTime.parse(u['updated_at'] as String) : DateTime.now(),
              syncDirty: u['sync_dirty'] == 1,
              createdBy: u['created_by'] as String?,
              updatedBy: u['updated_by'] as String?,
              deviceId: u['device_id'] as String?,
              syncVersion: (u['sync_version'] as num?)?.toInt() ?? 0,
            ));
          }
        }
      } catch (e) {
        debugPrint('Error parseando poligono ${u['id']}: $e');
      }
    }

    // 2. Cargar Caminos (Líneas)
    final caminosData = await dbHelper.queryAll('caminos');
    lineas.clear();
    for (var c in caminosData) {
      try {
        final geomStr = c['geom_wkt'] as String?;
        if (geomStr == null) continue;
        final match = lineRegex.firstMatch(geomStr);
        if (match != null) {
          final ptsStr = match.group(1)!;
          final pairs = ptsStr.split(',');
          List<LatLng> verts = [];
          for (var pair in pairs) {
            final xy = pair.trim().split(' ');
            if (xy.length >= 2) {
              verts.add(LatLng(double.parse(xy[1]), double.parse(xy[0])));
            }
          }
          if (verts.isNotEmpty) {
            lineas.add(LineaCamino(
              id: c['id'] as String,
              vertices: verts,
              nombre: (c['nombre'] as String?)?.isNotEmpty == true ? c['nombre'] as String : 'Camino',
              tipo: TipoCamino.values.firstWhere(
                (e) => e.name == c['tipo'],
                orElse: () => TipoCamino.terraceria,
              ),
              notas: c['notas'] as String? ?? '',
              updatedAt: c['updated_at'] != null ? DateTime.parse(c['updated_at'] as String) : DateTime.now(),
              syncDirty: c['sync_dirty'] == 1,
              createdBy: c['created_by'] as String?,
              updatedBy: c['updated_by'] as String?,
              deviceId: c['device_id'] as String?,
              syncVersion: (c['sync_version'] as num?)?.toInt() ?? 0,
            ));
          }
        }
      } catch (e) {
        debugPrint('Error parseando linea ${c['id']}: $e');
      }
    }

    // 3. Cargar Estructuras y jerarquía
    puntos.clear();
    puntos.addAll(await dbHelper.getEstructuras());
    
    notifyListeners();
  }

  void cargarDesdeJson(Map<String, dynamic> json) {
    puntos.clear();
    lineas.clear();
    poligonos.clear();

    for (final p in (json['puntos'] as List? ?? [])) {
      puntos.add(PuntoEstructura.fromJson(p));
    }
    for (final l in (json['lineas'] as List? ?? [])) {
      lineas.add(LineaCamino.fromJson(l));
    }
    for (final p in (json['poligonos'] as List? ?? [])) {
      poligonos.add(PoligonoUPM.fromJson(p));
    }
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASES AUXILIARES PRIVADAS
// ─────────────────────────────────────────────────────────────────────────────

/// Representa un punto de intersección encontrado durante el corte.
/// Incluye la posición paramétrica [t] para ordenar múltiples
/// intersecciones dentro del mismo segmento de la línea original.
class _PuntoCorte {
  final int segmentoIdx; // Índice del segmento de la línea ORIGINAL
  final double t;        // Parámetro t ∈ [0,1] dentro de ese segmento
  final LatLng punto;    // Coordenadas exactas de la intersección

  const _PuntoCorte({
    required this.segmentoIdx,
    required this.t,
    required this.punto,
  });
}

/// Registro de una operación de corte, utilizado para implementar Deshacer.
class _OperacionCorte {
  final LineaCamino lineaOriginal;            // La línea antes del corte
  final List<LineaCamino> segmentosGenerados; // Los segmentos resultantes
  final int insertIndex;                      // Posición original en la lista

  const _OperacionCorte({
    required this.lineaOriginal,
    required this.segmentosGenerados,
    required this.insertIndex,
  });
}
