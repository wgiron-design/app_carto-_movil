import 'dart:convert';
import 'package:http/http.dart' as http;
import 'postgis_service.dart';
import '../models/capa_geometrica.dart';
import '../models/jerarquia.dart';
import '../database/database_helper.dart';

class LocalApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? data;

  LocalApiException({required this.code, required this.message, this.data});

  @override
  String toString() => 'LocalApiException: [$code] $message';
}

class LocalResumen {
  final String id;
  final String nivelId;
  final String? nombreLocal;
  final int idTipo;
  final String? nombreTipo;
  final int? idCondicionLocal;
  final String? nombreCondicion;
  final int? numeroHogares;
  final String? descripcion;
  final DateTime? updatedAt;
  final int hogaresRegistrados;

  LocalResumen({
    required this.id,
    required this.nivelId,
    this.nombreLocal,
    required this.idTipo,
    this.nombreTipo,
    this.idCondicionLocal,
    this.nombreCondicion,
    this.numeroHogares,
    this.descripcion,
    this.updatedAt,
    required this.hogaresRegistrados,
  });

  factory LocalResumen.fromJson(Map<String, dynamic> json) {
    return LocalResumen(
      id: json['id'] as String,
      nivelId: (json['nivel_id'] ?? json['id_nivel'] ?? '') as String,
      nombreLocal: json['nombre_local'] as String?,
      idTipo: (json['id_tipo'] as num).toInt(),
      nombreTipo: json['nombre_tipo'] as String?,
      idCondicionLocal: json['id_condicion_local'] != null ? (json['id_condicion_local'] as num).toInt() : null,
      nombreCondicion: json['nombre_condicion'] as String?,
      numeroHogares: json['numero_hogares'] != null ? (json['numero_hogares'] as num).toInt() : null,
      descripcion: json['descripcion'] as String?,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      hogaresRegistrados: (json['hogares_registrados'] as num? ?? 0).toInt(),
    );
  }

  bool get esCompleto {
    if (idCondicionLocal == 4 || idCondicionLocal == 5) return true; // Desocupado / Rechazo
    if (idTipo == 4 || idTipo == 5) return true;                    // Institución pública/privada / En construcción
    if (numeroHogares == null) return true;                         // Sin número de hogares especificado
    return hogaresRegistrados >= numeroHogares!;
  }

  Local toLocalModel() {
    return Local(
      id: id,
      idNivel: nivelId,
      nombre: nombreLocal,
      idTipo: idTipo,
      idCondicionLocal: idCondicionLocal,
      nombreTipo: nombreTipo,
      nombreCondicion: nombreCondicion,
      numeroHogares: numeroHogares,
      descripcion: descripcion,
      updatedAt: updatedAt,
      syncDirty: false,
    );
  }
}

class LocalListResponse {
  final String nivelId;
  final int numeroNivel;
  final int numeroLocalesEsperados;
  final int localesRegistrados;
  final List<LocalResumen> locales;

  LocalListResponse({
    required this.nivelId,
    required this.numeroNivel,
    required this.numeroLocalesEsperados,
    required this.localesRegistrados,
    required this.locales,
  });

  factory LocalListResponse.fromJson(Map<String, dynamic> json) {
    return LocalListResponse(
      nivelId: json['nivel_id'] as String,
      numeroNivel: (json['numero_nivel'] as num).toInt(),
      numeroLocalesEsperados: (json['numero_locales_esperados'] as num).toInt(),
      localesRegistrados: (json['locales_registrados'] as num).toInt(),
      locales: (json['locales'] as List? ?? [])
          .map((l) => LocalResumen.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LocalService {
  static final LocalService _instance = LocalService._internal();
  factory LocalService() => _instance;
  LocalService._internal();

  String get _baseUrl => PostGISService().baseUrl;

  Future<List<CatalogoItem>> getTiposLocales() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/capas/catalogos/locales/tipos');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List list = json.decode(response.body);
        return list.map((item) => CatalogoItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return const [
      CatalogoItem(id: 1, nombre: 'Habitación / Vivienda'),
      CatalogoItem(id: 2, nombre: 'Comercio / Tienda'),
      CatalogoItem(id: 3, nombre: 'Oficina / Servicio'),
      CatalogoItem(id: 4, nombre: 'Institución pública/privada'),
      CatalogoItem(id: 5, nombre: 'En construcción'),
      CatalogoItem(id: 6, nombre: 'Otro'),
    ];
  }

  Future<List<CatalogoItem>> getCondicionesLocales() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/capas/catalogos/locales/condiciones');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List list = json.decode(response.body);
        return list.map((item) => CatalogoItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return const [
      CatalogoItem(id: 1, nombre: 'Ocupado'),
      CatalogoItem(id: 2, nombre: 'Uso temporal'),
      CatalogoItem(id: 3, nombre: 'Desocupado'),
      CatalogoItem(id: 4, nombre: 'Rechazo / Ausente'),
    ];
  }

  Future<LocalListResponse> getLocalesByNivel(String nivelId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/locales/nivel/$nivelId');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return LocalListResponse.fromJson(data);
      }
    } catch (_) {}

    // Fallback SQLite local
    try {
      final db = await DatabaseHelper().database;
      final nivMaps = await db.query('niveles', where: 'id = ?', whereArgs: [nivelId]);
      final numNivel = nivMaps.isNotEmpty ? ((nivMaps.first['numero'] as num?)?.toInt() ?? 1) : 1;
      final numEsp = nivMaps.isNotEmpty ? ((nivMaps.first['numero_locales'] as num?)?.toInt() ?? 1) : 1;

      final localesMaps = await db.query('locales', where: 'nivel_id = ? AND deleted_at IS NULL', whereArgs: [nivelId]);
      final List<LocalResumen> lista = [];

      for (var l in localesMaps) {
        final lid = l['id'] as String;
        final hgMaps = await db.query('hogares', where: 'local_id = ? AND deleted_at IS NULL', whereArgs: [lid]);
        lista.add(LocalResumen(
          id: lid,
          nivelId: nivelId,
          nombreLocal: (l['nombre_local'] ?? l['nombre']) as String?,
          idTipo: (l['id_tipo'] as num?)?.toInt() ?? 1,
          idCondicionLocal: l['id_condicion_local'] != null ? (l['id_condicion_local'] as num).toInt() : null,
          numeroHogares: l['numero_hogares'] != null ? (l['numero_hogares'] as num).toInt() : null,
          descripcion: l['descripcion'] as String?,
          updatedAt: l['updated_at'] != null ? DateTime.parse(l['updated_at'] as String) : null,
          hogaresRegistrados: hgMaps.length,
        ));
      }

      return LocalListResponse(
        nivelId: nivelId,
        numeroNivel: numNivel,
        numeroLocalesEsperados: numEsp,
        localesRegistrados: lista.length,
        locales: lista,
      );
    } catch (e) {
      throw LocalApiException(code: 'db_error', message: 'Error cargando locales locales: $e');
    }
  }

  Future<Local> crearLocal(
    String nivelId, {
    required int idTipo,
    int? idCondicionLocal,
    String? nombreLocal,
    int? numeroHogares,
    String? descripcion,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/locales/nivel/$nivelId');
      final body = json.encode({
        'id_tipo': idTipo,
        if (idCondicionLocal != null) 'id_condicion_local': idCondicionLocal,
        if (nombreLocal != null && nombreLocal.isNotEmpty) 'nombre_local': nombreLocal,
        if (numeroHogares != null) 'numero_hogares': numeroHogares,
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = Local.fromJson(data);
        await DatabaseHelper().insertEntity('locales', loc.toMapDB());
        return loc;
      }
    } catch (_) {}

    // Fallback SQLite
    final nuevoLocal = Local.nuevo(
      idNivel: nivelId,
      idTipo: idTipo,
      idCondicionLocal: idCondicionLocal,
      nombre: nombreLocal,
      numeroHogares: numeroHogares,
      descripcion: descripcion,
    );
    await DatabaseHelper().insertEntity('locales', nuevoLocal.toMapDB());
    return nuevoLocal;
  }

  Future<Local> editarLocal(
    String localId, {
    int? idTipo,
    int? idCondicionLocal,
    String? nombreLocal,
    int? numeroHogares,
    String? descripcion,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/locales/$localId');
      final payload = <String, dynamic>{};
      if (idTipo != null) payload['id_tipo'] = idTipo;
      if (idCondicionLocal != null) payload['id_condicion_local'] = idCondicionLocal;
      if (nombreLocal != null) payload['nombre_local'] = nombreLocal;
      if (numeroHogares != null) payload['numero_hogares'] = numeroHogares;
      if (descripcion != null) payload['descripcion'] = descripcion;

      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = Local.fromJson(data);
        await DatabaseHelper().insertEntity('locales', loc.toMapDB());
        return loc;
      }
    } catch (_) {}

    // Fallback SQLite
    final db = await DatabaseHelper().database;
    final row = await db.query('locales', where: 'id = ?', whereArgs: [localId]);
    if (row.isNotEmpty) {
      final l = row.first;
      final updateData = <String, dynamic>{
        'id': localId,
        'nivel_id': l['nivel_id'],
        'nombre_local': nombreLocal ?? (l['nombre_local'] ?? l['nombre']),
        'id_tipo': idTipo ?? l['id_tipo'],
        'id_condicion_local': idCondicionLocal ?? l['id_condicion_local'],
        'numero_hogares': numeroHogares ?? l['numero_hogares'],
        'descripcion': descripcion ?? l['descripcion'],
        'updated_at': DateTime.now().toIso8601String(),
        'sync_dirty': 1,
      };
      await DatabaseHelper().insertEntity('locales', updateData);
      return Local.fromJson(updateData);
    }
    throw LocalApiException(code: 'not_found', message: 'Local no encontrado localmente');
  }

  Future<void> eliminarLocal(String localId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/locales/$localId');
      await http.delete(uri).timeout(const Duration(seconds: 4));
    } catch (_) {}

    await DatabaseHelper().softDeleteEntity('locales', localId);
  }

  void _handleError(http.Response response) {
    try {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is Map) {
          throw LocalApiException(
            code: detail['error'] as String? ?? 'api_error',
            message: detail['message'] as String? ?? 'Ocurrió un error',
            data: detail['data'] as Map<String, dynamic>?,
          );
        } else if (detail is String) {
          throw LocalApiException(code: 'api_error', message: detail);
        }
      }
    } catch (e) {
      if (e is LocalApiException) rethrow;
    }
    throw LocalApiException(
      code: 'http_${response.statusCode}',
      message: 'Respuesta del servidor no válida (${response.statusCode})',
    );
  }
}
