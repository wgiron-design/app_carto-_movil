import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'jerarquia.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE CAPAS GEOMÉTRICAS — Paso 3
//
// Jerarquía del proyecto:
//   PuntoEstructura  (georreferenciado)  ← Esta capa
//     └── Nivel (Paso 4)
//           └── Local (Paso 4)
//                 └── Sub-local (Paso 4)
//   LineaCamino      (georreferenciado)
//   PoligonoUPM      (georreferenciado)
// ─────────────────────────────────────────────────────────────────────────────

/// Item genérico para catalogos (Categorías, Tipos, etc.)
class CatalogoItem {
  final int id;
  final String nombre;
  final int? idCategoria;
  final String? descripcion;

  const CatalogoItem({
    required this.id,
    required this.nombre,
    this.idCategoria,
    this.descripcion,
  });

  factory CatalogoItem.fromJson(Map<String, dynamic> json) {
    return CatalogoItem(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre'] as String? ?? '',
      idCategoria: json['id_categoria'] != null ? (json['id_categoria'] as num).toInt() : null,
      descripcion: json['descripcion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        if (idCategoria != null) 'id_categoria': idCategoria,
        if (descripcion != null) 'descripcion': descripcion,
      };
}

/// Estado de la estructura
enum EstadoEstructura {
  presente('Presente(s)'),
  ausente('Ausente'),
  enConstruccion('En construcción'),
  desocupada('Desocupada');

  final String label;
  const EstadoEstructura(this.label);
}

/// Tipos predefinidos de camino
enum TipoCamino {
  asfaltado('Asfaltado', '═'),
  adoquinado('Adoquinado', '▪'),
  terraceria('Terracería', '─'),
  vereda('Vereda', '···');

  final String label;
  final String simbolo;
  const TipoCamino(this.label, this.simbolo);
}

// ─────────────────────────────────────────────────────────────────────────────
// PUNTO / ESTRUCTURA
// ─────────────────────────────────────────────────────────────────────────────

/// Punto georreferenciado que representa una estructura en el campo.
class PuntoEstructura {
  final String id;
  final LatLng coordenadas;
  final String nombre;
  final int idCategoria;
  final int idTipo;
  final int? idEstructuraUser;
  final String? nombreCategoria;
  final String? nombreTipo;
  final EstadoEstructura estado;
  final int nivelesCantidad;
  final String notas;
  final DateTime fechaCreacion;
  final DateTime updatedAt;
  final bool syncDirty;

  // ── Campos de Auditoría y Sincronización Offline ─────────────────────────
  final String? createdBy;
  final String? updatedBy;
  final String? deviceId;
  final int syncVersion;
  final DateTime? deletedAt;

  // Relación uno-a-muchos con Niveles
  final List<Nivel> niveles;

  // UUID generator global
  static const _uuid = Uuid();

  PuntoEstructura({
    required this.id,
    required this.coordenadas,
    required this.nombre,
    required this.idCategoria,
    required this.idTipo,
    this.idEstructuraUser,
    this.nombreCategoria,
    this.nombreTipo,
    this.estado = EstadoEstructura.presente,
    this.nivelesCantidad = 1,
    this.notas = '',
    DateTime? fechaCreacion,
    DateTime? updatedAt,
    this.syncDirty = true,
    this.createdBy,
    this.updatedBy,
    this.deviceId,
    this.syncVersion = 0,
    this.deletedAt,
    List<Nivel>? niveles,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       niveles = niveles ?? [];

  factory PuntoEstructura.nuevo({
    required LatLng coordenadas,
    required String nombre,
    required int idCategoria,
    required int idTipo,
    int? idEstructuraUser,
    String? nombreCategoria,
    String? nombreTipo,
    EstadoEstructura estado = EstadoEstructura.presente,
    int nivelesCantidad = 1,
    String notas = '',
    String? createdBy,
    String? deviceId,
  }) {
    return PuntoEstructura(
      id: _uuid.v4(),
      coordenadas: coordenadas,
      nombre: nombre,
      idCategoria: idCategoria,
      idTipo: idTipo,
      idEstructuraUser: idEstructuraUser,
      nombreCategoria: nombreCategoria,
      nombreTipo: nombreTipo,
      estado: estado,
      nivelesCantidad: nivelesCantidad,
      notas: notas,
      niveles: [],
      syncDirty: true,
      createdBy: createdBy,
      updatedBy: createdBy,
      deviceId: deviceId,
      syncVersion: 0,
    );
  }

  /// True si el registro fue eliminado lógicamente (soft-delete)
  bool get estaEliminado => deletedAt != null;

  /// Retorna la representación geométrica en WKT
  String get geomWkt => 'POINT(${coordenadas.longitude} ${coordenadas.latitude})';

  /// Convierte a Map para insertar en Base de Datos
  Map<String, dynamic> toMapDB(String upmId) {
    return {
      'id': id,
      'upm_id': upmId,
      'geom_wkt': geomWkt,
      'x': coordenadas.longitude,
      'y': coordenadas.latitude,
      'nombre': nombre,
      'notas': notas,
      'id_categoria': idCategoria,
      'id_tipo': idTipo,
      'id_estructura_user': idEstructuraUser,
      'estado': estado.name,
      'niveles_cantidad': nivelesCantidad,
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
      'created_by': createdBy,
      'updated_by': updatedBy,
      'device_id': deviceId,
      'sync_version': syncVersion,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Helper para obtener el emoji correspondiente al tipo seleccionado
  String get emojiActivo => '📍';
  
  /// Helper para obtener el texto del tipo seleccionado
  String get labelTipoActivo => nombreTipo ?? 'Tipo #$idTipo';

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': coordenadas.latitude,
        'lng': coordenadas.longitude,
        'nombre': nombre,
        'id_categoria': idCategoria,
        'id_tipo': idTipo,
        'id_estructura_user': idEstructuraUser,
        'nombre_categoria': nombreCategoria,
        'nombre_tipo': nombreTipo,
        'estado': estado.name,
        'nivelesCantidad': nivelesCantidad,
        'notas': notas,
        'fechaCreacion': fechaCreacion.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncDirty': syncDirty,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'deviceId': deviceId,
        'syncVersion': syncVersion,
        'deletedAt': deletedAt?.toIso8601String(),
        'niveles': niveles.map((n) => n.toJson()).toList(),
      };

  factory PuntoEstructura.fromJson(Map<String, dynamic> json) {
    return PuntoEstructura(
      id: json['id'] as String,
      coordenadas: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      nombre: json['nombre'] as String,
      idCategoria: (json['id_categoria'] as num?)?.toInt() ?? 1,
      idTipo: (json['id_tipo'] as num?)?.toInt() ?? 1,
      idEstructuraUser: (json['id_estructura_user'] as num?)?.toInt(),
      nombreCategoria: json['nombre_categoria'] as String?,
      nombreTipo: json['nombre_tipo'] as String?,
      estado: EstadoEstructura.values.firstWhere(
        (e) => e.name == json['estado'],
        orElse: () => EstadoEstructura.presente,
      ),
      nivelesCantidad: (json['nivelesCantidad'] as num?)?.toInt() ?? 1,
      notas: json['notas'] as String? ?? '',
      fechaCreacion: json['fechaCreacion'] != null ? DateTime.parse(json['fechaCreacion'] as String) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : DateTime.now(),
      syncDirty: json['syncDirty'] as bool? ?? true,
      createdBy: json['createdBy'] as String?,
      updatedBy: json['updatedBy'] as String?,
      deviceId: json['deviceId'] as String?,
      syncVersion: (json['syncVersion'] as num?)?.toInt() ?? 0,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
      niveles: (json['niveles'] as List? ?? [])
          .map((n) => Nivel.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': 'Point',
          'coordinates': [coordenadas.longitude, coordenadas.latitude],
        },
        'properties': {
          'nombre': nombre,
          'id_categoria': idCategoria,
          'id_tipo': idTipo,
          'id_estructura_user': idEstructuraUser,
          'estado': estado.name,
          'niveles_cantidad': nivelesCantidad,
          'notas': notas,
          'created_by': createdBy,
          'updated_by': updatedBy,
          'device_id': deviceId,
          'sync_version': syncVersion,
        }
      };

  factory PuntoEstructura.fromGeoJson(Map<String, dynamic> feature) {
    final geom = feature['geometry'] as Map<String, dynamic>;
    final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
    final coords = geom['coordinates'] as List;
    return PuntoEstructura(
      id: feature['id'] as String,
      coordenadas: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
      nombre: props['nombre'] as String? ?? '',
      idCategoria: (props['id_categoria'] as num?)?.toInt() ?? 1,
      idTipo: (props['id_tipo'] as num?)?.toInt() ?? 1,
      idEstructuraUser: (props['id_estructura_user'] as num?)?.toInt(),
      nombreCategoria: props['nombre_categoria'] as String?,
      nombreTipo: props['nombre_tipo'] as String?,
      estado: EstadoEstructura.values.firstWhere(
        (e) => e.name == props['estado'],
        orElse: () => EstadoEstructura.presente,
      ),
      nivelesCantidad: (props['niveles_cantidad'] as num?)?.toInt() ?? 1,
      notas: props['notas'] as String? ?? '',
      syncDirty: props['sync_dirty'] == true || props['sync_dirty'] == 1,
      createdBy: props['created_by'] as String?,
      updatedBy: props['updated_by'] as String?,
      deviceId: props['device_id'] as String?,
      syncVersion: (props['sync_version'] as num?)?.toInt() ?? 0,
      deletedAt: props['deleted_at'] != null ? DateTime.parse(props['deleted_at'] as String) : null,
    );
  }

  PuntoEstructura copyWith({
    LatLng? coordenadas,
    String? nombre,
    int? idCategoria,
    int? idTipo,
    int? idEstructuraUser,
    String? nombreCategoria,
    String? nombreTipo,
    EstadoEstructura? estado,
    int? nivelesCantidad,
    String? notas,
    String? updatedBy,
    List<Nivel>? niveles,
  }) =>
      PuntoEstructura(
        id: id,
        coordenadas: coordenadas ?? this.coordenadas,
        nombre: nombre ?? this.nombre,
        idCategoria: idCategoria ?? this.idCategoria,
        idTipo: idTipo ?? this.idTipo,
        idEstructuraUser: idEstructuraUser ?? this.idEstructuraUser,
        nombreCategoria: nombreCategoria ?? this.nombreCategoria,
        nombreTipo: nombreTipo ?? this.nombreTipo,
        estado: estado ?? this.estado,
        nivelesCantidad: nivelesCantidad ?? this.nivelesCantidad,
        notas: notas ?? this.notas,
        fechaCreacion: fechaCreacion,
        updatedAt: DateTime.now(),
        syncDirty: true,
        createdBy: createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
        deviceId: deviceId,
        syncVersion: syncVersion,
        deletedAt: deletedAt,
        niveles: niveles ?? this.niveles,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LÍNEA / CAMINO
// ─────────────────────────────────────────────────────────────────────────────

/// Línea poligonal que representa un camino o ruta en el campo.
class LineaCamino {
  final String id;
  final List<LatLng> vertices;
  final String nombre;
  final TipoCamino tipo;
  final String notas;
  final DateTime fechaCreacion;
  final DateTime updatedAt;
  final bool syncDirty;

  // ── Campos de Auditoría y Sincronización Offline ─────────────────────────
  final String? createdBy;
  final String? updatedBy;
  final String? deviceId;
  final int syncVersion;
  final DateTime? deletedAt;

  static const _uuid = Uuid();

  LineaCamino({
    required this.id,
    required this.vertices,
    required this.nombre,
    this.tipo = TipoCamino.terraceria,
    this.notas = '',
    DateTime? fechaCreacion,
    DateTime? updatedAt,
    this.syncDirty = true,
    this.createdBy,
    this.updatedBy,
    this.deviceId,
    this.syncVersion = 0,
    this.deletedAt,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory LineaCamino.nuevo({
    required List<LatLng> vertices,
    required String nombre,
    TipoCamino tipo = TipoCamino.terraceria,
    String notas = '',
    String? createdBy,
    String? deviceId,
  }) {
    return LineaCamino(
      id: _uuid.v4(),
      vertices: List.from(vertices),
      nombre: nombre,
      tipo: tipo,
      notas: notas,
      syncDirty: true,
      createdBy: createdBy,
      updatedBy: createdBy,
      deviceId: deviceId,
      syncVersion: 0,
    );
  }

  /// True si el registro fue eliminado lógicamente (soft-delete)
  bool get estaEliminado => deletedAt != null;

  /// Retorna la representación geométrica en WKT
  String get geomWkt {
    if (vertices.isEmpty) return 'LINESTRING EMPTY';
    final pts = vertices.map((v) => '${v.longitude} ${v.latitude}').join(', ');
    return 'LINESTRING($pts)';
  }

  /// Bounding box (R-Tree bounds)
  Map<String, double> get bounds {
    if (vertices.isEmpty) return {'min_x': 0, 'max_x': 0, 'min_y': 0, 'max_y': 0};
    double minX = vertices[0].longitude, maxX = vertices[0].longitude;
    double minY = vertices[0].latitude, maxY = vertices[0].latitude;
    for (var v in vertices) {
      if (v.longitude < minX) minX = v.longitude;
      if (v.longitude > maxX) maxX = v.longitude;
      if (v.latitude < minY) minY = v.latitude;
      if (v.latitude > maxY) maxY = v.latitude;
    }
    return {'min_x': minX, 'max_x': maxX, 'min_y': minY, 'max_y': maxY};
  }

  Map<String, dynamic> toMapDB() {
    final b = bounds;
    return {
      'id': id,
      'geom_wkt': geomWkt,
      'nombre': nombre,
      'tipo': tipo.name,
      'notas': notas,
      'min_x': b['min_x'],
      'max_x': b['max_x'],
      'min_y': b['min_y'],
      'max_y': b['max_y'],
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
      'created_by': createdBy,
      'updated_by': updatedBy,
      'device_id': deviceId,
      'sync_version': syncVersion,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Longitud aproximada en metros usando la fórmula de Haversine
  double get longitudMetros {
    if (vertices.length < 2) return 0;
    const Distance d = Distance();
    double total = 0;
    for (int i = 0; i < vertices.length - 1; i++) {
      total += d(vertices[i], vertices[i + 1]);
    }
    return total;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vertices': vertices
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'nombre': nombre,
        'tipo': tipo.name,
        'notas': notas,
        'fechaCreacion': fechaCreacion.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncDirty': syncDirty,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'deviceId': deviceId,
        'syncVersion': syncVersion,
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory LineaCamino.fromJson(Map<String, dynamic> json) {
    return LineaCamino(
      id: json['id'] as String,
      vertices: (json['vertices'] as List)
          .map((v) => LatLng(
                (v['lat'] as num).toDouble(),
                (v['lng'] as num).toDouble(),
              ))
          .toList(),
      nombre: json['nombre'] as String,
      tipo: TipoCamino.values.firstWhere(
        (e) => e.name == json['tipo'],
        orElse: () => TipoCamino.terraceria,
      ),
      notas: json['notas'] as String? ?? '',
      fechaCreacion: json['fechaCreacion'] != null ? DateTime.parse(json['fechaCreacion'] as String) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : DateTime.now(),
      syncDirty: json['syncDirty'] as bool? ?? true,
      createdBy: json['createdBy'] as String?,
      updatedBy: json['updatedBy'] as String?,
      deviceId: json['deviceId'] as String?,
      syncVersion: (json['syncVersion'] as num?)?.toInt() ?? 0,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
    );
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': 'LineString',
          'coordinates': vertices.map((v) => [v.longitude, v.latitude]).toList(),
        },
        'properties': {
          'nombre': nombre,
          'tipo': tipo.name,
          'notas': notas,
          'created_by': createdBy,
          'updated_by': updatedBy,
          'device_id': deviceId,
          'sync_version': syncVersion,
        }
      };

  factory LineaCamino.fromGeoJson(Map<String, dynamic> feature) {
    final geom = feature['geometry'] as Map<String, dynamic>;
    final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
    final coords = geom['coordinates'] as List;
    final List<LatLng> verts = coords
        .map((pt) => LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()))
        .toList();

    return LineaCamino(
      id: feature['id'] as String,
      vertices: verts,
      nombre: props['nombre'] as String? ?? 'Camino',
      tipo: TipoCamino.values.firstWhere(
        (e) => e.name == props['tipo'],
        orElse: () => TipoCamino.terraceria,
      ),
      notas: props['notas'] as String? ?? '',
      syncDirty: props['sync_dirty'] == true || props['sync_dirty'] == 1,
      createdBy: props['created_by'] as String?,
      updatedBy: props['updated_by'] as String?,
      deviceId: props['device_id'] as String?,
      syncVersion: (props['sync_version'] as num?)?.toInt() ?? 0,
      deletedAt: props['deleted_at'] != null ? DateTime.parse(props['deleted_at'] as String) : null,
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// POLÍGONO / UPM (Unidad Primaria de Muestreo)
// ─────────────────────────────────────────────────────────────────────────────

/// Polígono cerrado que delimita una Unidad Primaria de Muestreo (UPM).
class PoligonoUPM {
  final String id;
  final List<LatLng> vertices; // El cierre (último = primero) lo agrega el renderer
  final String nombre;
  final String codigoUPM;
  final String notas;
  final DateTime fechaCreacion;
  final DateTime updatedAt;
  final bool syncDirty;

  // ── Campos de Auditoría y Sincronización Offline ─────────────────────────
  final String? createdBy;
  final String? updatedBy;
  final String? deviceId;
  final int syncVersion;
  final DateTime? deletedAt;

  static const _uuid = Uuid();

  PoligonoUPM({
    required this.id,
    required this.vertices,
    required this.nombre,
    this.codigoUPM = '',
    this.notas = '',
    DateTime? fechaCreacion,
    DateTime? updatedAt,
    this.syncDirty = true,
    this.createdBy,
    this.updatedBy,
    this.deviceId,
    this.syncVersion = 0,
    this.deletedAt,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory PoligonoUPM.nuevo({
    required List<LatLng> vertices,
    required String nombre,
    String codigoUPM = '',
    String notas = '',
    String? createdBy,
    String? deviceId,
  }) {
    return PoligonoUPM(
      id: _uuid.v4(),
      vertices: List.from(vertices),
      nombre: nombre,
      codigoUPM: codigoUPM,
      notas: notas,
      syncDirty: true,
      createdBy: createdBy,
      updatedBy: createdBy,
      deviceId: deviceId,
      syncVersion: 0,
    );
  }

  /// True si el registro fue eliminado lógicamente (soft-delete)
  bool get estaEliminado => deletedAt != null;

  /// Retorna la representación geométrica en WKT
  String get geomWkt {
    if (vertices.isEmpty) return 'POLYGON EMPTY';
    var pts = vertices.map((v) => '${v.longitude} ${v.latitude}').toList();
    // Cerrar poligono
    if (pts.first != pts.last) {
      pts.add(pts.first);
    }
    return 'POLYGON((${pts.join(', ')}))';
  }

  /// Bounding box (R-Tree bounds)
  Map<String, double> get bounds {
    if (vertices.isEmpty) return {'min_x': 0, 'max_x': 0, 'min_y': 0, 'max_y': 0};
    double minX = vertices[0].longitude, maxX = vertices[0].longitude;
    double minY = vertices[0].latitude, maxY = vertices[0].latitude;
    for (var v in vertices) {
      if (v.longitude < minX) minX = v.longitude;
      if (v.longitude > maxX) maxX = v.longitude;
      if (v.latitude < minY) minY = v.latitude;
      if (v.latitude > maxY) maxY = v.latitude;
    }
    return {'min_x': minX, 'max_x': maxX, 'min_y': minY, 'max_y': maxY};
  }

  Map<String, dynamic> toMapDB() {
    final b = bounds;
    return {
      'id': id,
      'geom_wkt': geomWkt,
      'nombre': nombre,
      'codigo_upm': codigoUPM,
      'notas': notas,
      'min_x': b['min_x'],
      'max_x': b['max_x'],
      'min_y': b['min_y'],
      'max_y': b['max_y'],
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
      'created_by': createdBy,
      'updated_by': updatedBy,
      'device_id': deviceId,
      'sync_version': syncVersion,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Área aproximada en m² usando el algoritmo de Shoelace con conversión esférica
  double get areaMetrosCuadrados {
    if (vertices.length < 3) return 0;
    // Aproximación simple usando coordenadas planas (válida para áreas pequeñas)
    const double latToM = 111320.0;
    final double centerLat = vertices.map((v) => v.latitude).reduce((a, b) => a + b) / vertices.length;
    final double lngToM = latToM * _cos(centerLat);

    double area = 0;
    final int n = vertices.length;
    for (int i = 0; i < n; i++) {
      final int j = (i + 1) % n;
      area += vertices[i].latitude * latToM * vertices[j].longitude * lngToM;
      area -= vertices[j].latitude * latToM * vertices[i].longitude * lngToM;
    }
    return (area / 2).abs();
  }

  double _cos(double deg) {
    const double pi = 3.141592653589793;
    return _cosRad(deg * pi / 180.0);
  }

  double _cosRad(double rad) {
    // Aproximación de Taylor para coseno
    double x = rad % (2 * 3.141592653589793);
    return 1 - (x * x) / 2 + (x * x * x * x) / 24 - (x * x * x * x * x * x) / 720;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vertices': vertices
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'nombre': nombre,
        'codigoUPM': codigoUPM,
        'notas': notas,
        'fechaCreacion': fechaCreacion.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncDirty': syncDirty,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'deviceId': deviceId,
        'syncVersion': syncVersion,
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory PoligonoUPM.fromJson(Map<String, dynamic> json) {
    return PoligonoUPM(
      id: json['id'] as String,
      vertices: (json['vertices'] as List)
          .map((v) => LatLng(
                (v['lat'] as num).toDouble(),
                (v['lng'] as num).toDouble(),
              ))
          .toList(),
      nombre: json['nombre'] as String,
      codigoUPM: json['codigoUPM'] as String? ?? '',
      notas: json['notas'] as String? ?? '',
      fechaCreacion: json['fechaCreacion'] != null ? DateTime.parse(json['fechaCreacion'] as String) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : DateTime.now(),
      syncDirty: json['syncDirty'] as bool? ?? true,
      createdBy: json['createdBy'] as String?,
      updatedBy: json['updatedBy'] as String?,
      deviceId: json['deviceId'] as String?,
      syncVersion: (json['syncVersion'] as num?)?.toInt() ?? 0,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
    );
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              ...vertices.map((v) => [v.longitude, v.latitude]),
              if (vertices.isNotEmpty) [vertices.first.longitude, vertices.first.latitude]
            ]
          ],
        },
        'properties': {
          'nombre': nombre,
          'codigo_upm': codigoUPM,
          'notas': notas,
          'created_by': createdBy,
          'updated_by': updatedBy,
          'device_id': deviceId,
          'sync_version': syncVersion,
        }
      };

  factory PoligonoUPM.fromGeoJson(Map<String, dynamic> feature) {
    final geom = feature['geometry'] as Map<String, dynamic>;
    final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
    final ring = (geom['coordinates'] as List).first as List;
    final List<LatLng> verts = ring
        .map((pt) => LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()))
        .toList();
    if (verts.length > 1 &&
        verts.first.latitude == verts.last.latitude &&
        verts.first.longitude == verts.last.longitude) {
      verts.removeLast();
    }

    return PoligonoUPM(
      id: feature['id'] as String,
      vertices: verts,
      nombre: props['nombre'] as String? ?? 'UPM',
      codigoUPM: props['codigo_upm'] as String? ?? '',
      notas: props['notas'] as String? ?? '',
      syncDirty: props['sync_dirty'] == true || props['sync_dirty'] == 1,
      createdBy: props['created_by'] as String?,
      updatedBy: props['updated_by'] as String?,
      deviceId: props['device_id'] as String?,
      syncVersion: (props['sync_version'] as num?)?.toInt() ?? 0,
      deletedAt: props['deleted_at'] != null ? DateTime.parse(props['deleted_at'] as String) : null,
    );
  }

}
