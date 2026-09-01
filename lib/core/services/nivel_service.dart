import 'dart:convert';
import 'package:http/http.dart' as http;
import 'postgis_service.dart';
import '../models/jerarquia.dart';
import '../database/database_helper.dart';

class NivelApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? data;

  NivelApiException({required this.code, required this.message, this.data});

  @override
  String toString() => 'NivelApiException: [$code] $message';
}

class NivelResumen {
  final String id;
  final int numero;
  final int numeroLocales;
  final String? descripcion;
  final DateTime updatedAt;
  final int localesRegistrados;
  final int hogaresRegistrados;
  final int personasRegistradas;

  NivelResumen({
    required this.id,
    required this.numero,
    required this.numeroLocales,
    this.descripcion,
    required this.updatedAt,
    required this.localesRegistrados,
    required this.hogaresRegistrados,
    required this.personasRegistradas,
  });

  factory NivelResumen.fromJson(Map<String, dynamic> json) {
    return NivelResumen(
      id: json['id'] as String,
      numero: (json['numero'] as num).toInt(),
      numeroLocales: (json['numero_locales'] as num).toInt(),
      descripcion: json['descripcion'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      localesRegistrados: ((json['locales_registrados'] ?? 0) as num).toInt(),
      hogaresRegistrados: ((json['hogares_registrados'] ?? 0) as num).toInt(),
      personasRegistradas: ((json['personas_registradas'] ?? 0) as num).toInt(),
    );
  }

  Nivel toNivelModel(String estructuraId) {
    return Nivel(
      id: id,
      idEstructura: estructuraId,
      numeroNivel: numero,
      numeroLocales: numeroLocales,
      descripcion: descripcion,
      updatedAt: updatedAt,
      syncDirty: false,
    );
  }
}

class NivelListResponse {
  final String estructuraId;
  final String nombreEstructura;
  final int nivelesCantidad;
  final int nivelesRegistrados;
  final List<NivelResumen> niveles;

  NivelListResponse({
    required this.estructuraId,
    required this.nombreEstructura,
    required this.nivelesCantidad,
    required this.nivelesRegistrados,
    required this.niveles,
  });

  factory NivelListResponse.fromJson(Map<String, dynamic> json) {
    return NivelListResponse(
      estructuraId: json['estructura_id'] as String,
      nombreEstructura: json['nombre_estructura'] as String? ?? 'Estructura',
      nivelesCantidad: (json['niveles_cantidad'] as num).toInt(),
      nivelesRegistrados: (json['niveles_registrados'] as num).toInt(),
      niveles: (json['niveles'] as List? ?? [])
          .map((n) => NivelResumen.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NivelService {
  static final NivelService _instance = NivelService._internal();
  factory NivelService() => _instance;
  NivelService._internal();

  String get _baseUrl => PostGISService().baseUrl;

  Future<NivelListResponse> getNivelesByEstructura(String estructuraId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/niveles/estructura/$estructuraId');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return NivelListResponse.fromJson(data);
      }
    } catch (_) {}

    // Fallback SQLite local
    try {
      final db = await DatabaseHelper().database;
      final estMaps = await db.query('estructuras', where: 'id = ?', whereArgs: [estructuraId]);
      final nombreEst = estMaps.isNotEmpty ? (estMaps.first['nombre'] as String? ?? 'Estructura') : 'Estructura';
      final nivelesCant = estMaps.isNotEmpty ? ((estMaps.first['niveles_cantidad'] as num?)?.toInt() ?? 1) : 1;

      final nivelesMaps = await db.query('niveles', where: 'estructura_id = ? AND deleted_at IS NULL', whereArgs: [estructuraId], orderBy: 'numero ASC');
      final List<NivelResumen> lista = [];

      for (var n in nivelesMaps) {
        final nid = n['id'] as String;
        final localesMaps = await db.query('locales', where: 'nivel_id = ? AND deleted_at IS NULL', whereArgs: [nid]);
        int localesReg = localesMaps.length;
        int hogaresReg = 0;
        int personasReg = 0;
        for (var loc in localesMaps) {
          final lid = loc['id'] as String;
          final hgMaps = await db.query('hogares', where: 'local_id = ? AND deleted_at IS NULL', whereArgs: [lid]);
          hogaresReg += hgMaps.length;
          for (var h in hgMaps) {
            personasReg += (h['total_habitantes'] as num?)?.toInt() ?? 0;
          }
        }

        lista.add(NivelResumen(
          id: nid,
          numero: (n['numero'] as num).toInt(),
          numeroLocales: (n['numero_locales'] as num?)?.toInt() ?? 1,
          descripcion: n['descripcion'] as String?,
          updatedAt: n['updated_at'] != null ? DateTime.parse(n['updated_at'] as String) : DateTime.now(),
          localesRegistrados: localesReg,
          hogaresRegistrados: hogaresReg,
          personasRegistradas: personasReg,
        ));
      }

      return NivelListResponse(
        estructuraId: estructuraId,
        nombreEstructura: nombreEst,
        nivelesCantidad: nivelesCant,
        nivelesRegistrados: lista.length,
        niveles: lista,
      );
    } catch (e) {
      throw NivelApiException(code: 'db_error', message: 'Error cargando niveles locales: $e');
    }
  }

  Future<Nivel> crearNivel(String estructuraId, {required int numeroLocales, String? descripcion}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/niveles/estructura/$estructuraId');
      final body = json.encode({
        'numero_locales': numeroLocales,
        if (descripcion != null) 'descripcion': descripcion,
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final nivel = Nivel.fromJson(data);
        await DatabaseHelper().insertEntity('niveles', nivel.toMapDB());
        return nivel;
      } else if (response.statusCode == 409 || response.statusCode == 422) {
        _handleError(response);
      }
    } catch (e) {
      if (e is NivelApiException) rethrow;
    }

    // Fallback SQLite
    final db = await DatabaseHelper().database;
    final countMaps = await db.rawQuery('SELECT COUNT(*) as c FROM niveles WHERE estructura_id = ?', [estructuraId]);
    final nextNum = ((countMaps.first['c'] as num?)?.toInt() ?? 0) + 1;
    final nuevoNivel = Nivel.nuevo(
      idEstructura: estructuraId,
      numeroNivel: nextNum,
      numeroLocales: numeroLocales,
      descripcion: descripcion,
    );
    await DatabaseHelper().insertEntity('niveles', nuevoNivel.toMapDB());
    return nuevoNivel;
  }

  Future<Nivel> editarNivel(String nivelId, {int? numeroLocales, String? descripcion}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/niveles/$nivelId');
      final payload = <String, dynamic>{};
      if (numeroLocales != null) payload['numero_locales'] = numeroLocales;
      if (descripcion != null) payload['descripcion'] = descripcion;

      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final nivel = Nivel.fromJson(data);
        await DatabaseHelper().insertEntity('niveles', nivel.toMapDB());
        return nivel;
      } else if (response.statusCode == 409 || response.statusCode == 422) {
        _handleError(response);
      }
    } catch (e) {
      if (e is NivelApiException) rethrow;
    }

    // Fallback SQLite
    final db = await DatabaseHelper().database;
    final row = await db.query('niveles', where: 'id = ?', whereArgs: [nivelId]);
    if (row.isNotEmpty) {
      final n = row.first;
      final updateData = <String, dynamic>{
        'id': nivelId,
        'estructura_id': n['estructura_id'],
        'numero': n['numero'],
        'numero_locales': numeroLocales ?? n['numero_locales'],
        'descripcion': descripcion ?? n['descripcion'],
        'updated_at': DateTime.now().toIso8601String(),
        'sync_dirty': 1,
      };
      await DatabaseHelper().insertEntity('niveles', updateData);
      return Nivel.fromJson(updateData);
    }
    throw NivelApiException(code: 'not_found', message: 'Nivel no encontrado localmente');
  }

  Future<Nivel> confirmarEliminacionLocales(String nivelId, int numeroLocalesNuevo) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/niveles/$nivelId/locales-excedentes');
      final body = json.encode({
        'numero_locales_nuevo': numeroLocalesNuevo,
      });

      final response = await http.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Nivel.fromJson(data);
      }
    } catch (_) {}

    return await editarNivel(nivelId, numeroLocales: numeroLocalesNuevo);
  }

  void _handleError(http.Response response) {
    try {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is Map) {
          throw NivelApiException(
            code: detail['error'] as String? ?? 'api_error',
            message: detail['message'] as String? ?? 'Ocurrió un error',
            data: detail['data'] as Map<String, dynamic>?,
          );
        } else if (detail is String) {
          throw NivelApiException(code: 'api_error', message: detail);
        }
      }
    } catch (e) {
      if (e is NivelApiException) rethrow;
    }
    throw NivelApiException(
      code: 'http_${response.statusCode}',
      message: 'Respuesta del servidor no válida (${response.statusCode})',
    );
  }
}
