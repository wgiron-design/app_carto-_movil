import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'postgis_service.dart';
import '../models/capa_geometrica.dart';
import '../models/jerarquia.dart';
import '../database/database_helper.dart';

class HogarApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? data;

  HogarApiException({required this.code, required this.message, this.data});

  @override
  String toString() => 'HogarApiException: [$code] $message';
}

class HogarResumen {
  final String id;
  final String localId;
  final String? jefeFamilia;
  final int? idSexo;
  final String? nombreSexo;
  final int? idIdioma;
  final String? nombreIdioma;
  final String? direccion;
  final int totalHabitantes;
  final int personas_0_5;
  final int personas_6_11;
  final int personas_12_17;
  final int personas_18_23;
  final int personas_24_34;
  final int personas_35_44;
  final int personas_45_59;
  final int personas_60_69;
  final int personas_70_79;
  final int personas_80_mas;
  final int personasNoEdad;
  final DateTime? updatedAt;

  HogarResumen({
    required this.id,
    required this.localId,
    this.jefeFamilia,
    this.idSexo,
    this.nombreSexo,
    this.idIdioma,
    this.nombreIdioma,
    this.direccion,
    required this.totalHabitantes,
    required this.personas_0_5,
    required this.personas_6_11,
    required this.personas_12_17,
    required this.personas_18_23,
    required this.personas_24_34,
    required this.personas_35_44,
    required this.personas_45_59,
    required this.personas_60_69,
    required this.personas_70_79,
    required this.personas_80_mas,
    required this.personasNoEdad,
    this.updatedAt,
  });

  factory HogarResumen.fromJson(Map<String, dynamic> json) {
    return HogarResumen(
      id: json['id'] as String,
      localId: (json['local_id'] ?? json['id_local'] ?? '') as String,
      jefeFamilia: json['jefe_familia'] as String?,
      idSexo: json['id_sexo'] != null ? (json['id_sexo'] as num).toInt() : null,
      nombreSexo: json['nombre_sexo'] as String?,
      idIdioma: json['id_idioma'] != null ? (json['id_idioma'] as num).toInt() : null,
      nombreIdioma: json['nombre_idioma'] as String?,
      direccion: json['direccion'] as String?,
      totalHabitantes: (json['total_habitantes'] as num? ?? 0).toInt(),
      personas_0_5: (json['personas_0_5'] as num? ?? 0).toInt(),
      personas_6_11: (json['personas_6_11'] as num? ?? 0).toInt(),
      personas_12_17: (json['personas_12_17'] as num? ?? 0).toInt(),
      personas_18_23: (json['personas_18_23'] as num? ?? 0).toInt(),
      personas_24_34: (json['personas_24_34'] as num? ?? 0).toInt(),
      personas_35_44: (json['personas_35_44'] as num? ?? 0).toInt(),
      personas_45_59: (json['personas_45_59'] as num? ?? 0).toInt(),
      personas_60_69: (json['personas_60_69'] as num? ?? 0).toInt(),
      personas_70_79: (json['personas_70_79'] as num? ?? 0).toInt(),
      personas_80_mas: (json['personas_80_mas'] as num? ?? 0).toInt(),
      personasNoEdad: (json['personas_no_edad'] as num? ?? 0).toInt(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }

  int get sumaEdades {
    return personas_0_5 + personas_6_11 + personas_12_17 + personas_18_23 + personas_24_34 + personas_35_44 + personas_45_59 + personas_60_69 + personas_70_79 + personas_80_mas + personasNoEdad;
  }

  bool get esValidoMatematicamente {
    final suma = sumaEdades;
    return suma == 0 || totalHabitantes == suma;
  }

  Hogar toHogarModel() {
    return Hogar(
      id: id,
      idLocal: localId,
      jefeFamilia: jefeFamilia ?? '',
      idSexo: idSexo,
      idIdioma: idIdioma,
      nombreSexo: nombreSexo,
      nombreIdioma: nombreIdioma,
      direccion: direccion,
      totalHabitantes: totalHabitantes,
      personas_0_5: personas_0_5,
      personas_6_11: personas_6_11,
      personas_12_17: personas_12_17,
      personas_18_23: personas_18_23,
      updatedAt: updatedAt,
      syncDirty: false,
    );
  }
}

class HogarListResponse {
  final String localId;
  final String nombreLocal;
  final int idTipo;
  final int? idCondicionLocal;
  final int numeroHogaresEsperados;
  final int hogaresRegistrados;
  final List<HogarResumen> hogares;

  HogarListResponse({
    required this.localId,
    required this.nombreLocal,
    required this.idTipo,
    this.idCondicionLocal,
    required this.numeroHogaresEsperados,
    required this.hogaresRegistrados,
    required this.hogares,
  });

  factory HogarListResponse.fromJson(Map<String, dynamic> json) {
    return HogarListResponse(
      localId: json['local_id'] as String,
      nombreLocal: json['nombre_local'] as String? ?? 'Local',
      idTipo: (json['id_tipo'] as num? ?? json['id_tipo_local'] as num? ?? 1).toInt(),
      idCondicionLocal: json['id_condicion_local'] != null ? (json['id_condicion_local'] as num).toInt() : null,
      numeroHogaresEsperados: (json['numero_hogares_esperados'] as num? ?? 1).toInt(),
      hogaresRegistrados: (json['hogares_registrados'] as num? ?? 0).toInt(),
      hogares: (json['hogares'] as List? ?? [])
          .map((h) => HogarResumen.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get esCompleto {
    if (idCondicionLocal == 4 || idCondicionLocal == 5) return true; // Desocupado / Rechazo
    if (idTipo == 4 || idTipo == 5) return true;                     // Institución / En Construcción
    if (hogaresRegistrados < numeroHogaresEsperados) return false;
    for (var hogar in hogares) {
      if (!hogar.esValidoMatematicamente) return false;
    }
    return true;
  }
}

class HogarService {
  static final HogarService _instance = HogarService._internal();
  factory HogarService() => _instance;
  HogarService._internal();

  final _uuid = const Uuid();
  String get _baseUrl => PostGISService().baseUrl;

  Future<List<CatalogoItem>> getSexos() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/capas/catalogos/hogares/sexo');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List list = json.decode(response.body);
        return list.map((item) => CatalogoItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return const [
      CatalogoItem(id: 1, nombre: 'Hombre'),
      CatalogoItem(id: 2, nombre: 'Mujer'),
    ];
  }

  Future<List<CatalogoItem>> getIdiomas() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/capas/catalogos/hogares/idiomas');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List list = json.decode(response.body);
        return list.map((item) => CatalogoItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return const [
      CatalogoItem(id: 1, nombre: 'Español'),
      CatalogoItem(id: 2, nombre: 'K’iche’'),
      CatalogoItem(id: 3, nombre: 'Q’eqchi’'),
      CatalogoItem(id: 4, nombre: 'Kaqchikel'),
      CatalogoItem(id: 5, nombre: 'Mam'),
      CatalogoItem(id: 6, nombre: 'Poqomchi’'),
      CatalogoItem(id: 7, nombre: 'Tz’utujil'),
      CatalogoItem(id: 8, nombre: 'Achi'),
      CatalogoItem(id: 9, nombre: 'Q’anjob’al'),
      CatalogoItem(id: 10, nombre: 'Otro idioma Maya'),
      CatalogoItem(id: 11, nombre: 'Garífuna'),
      CatalogoItem(id: 12, nombre: 'Xinka'),
      CatalogoItem(id: 13, nombre: 'Inglés / Extranjero'),
      CatalogoItem(id: 14, nombre: 'No especificado'),
    ];
  }

  Future<HogarListResponse> getHogaresByLocal(String localId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/hogares/local/$localId');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return HogarListResponse.fromJson(data);
      }
    } catch (_) {}

    try {
      final db = await DatabaseHelper().database;
      final locMaps = await db.query('locales', where: 'id = ?', whereArgs: [localId]);
      final nomLoc = locMaps.isNotEmpty ? ((locMaps.first['nombre_local'] ?? locMaps.first['nombre']) as String? ?? 'Local') : 'Local';
      final idTipo = locMaps.isNotEmpty ? ((locMaps.first['id_tipo'] as num?)?.toInt() ?? 1) : 1;
      final idCond = locMaps.isNotEmpty ? (locMaps.first['id_condicion_local'] as num?)?.toInt() : null;
      final numHogEsp = locMaps.isNotEmpty ? ((locMaps.first['numero_hogares'] as num?)?.toInt() ?? 1) : 1;

      final hgMaps = await db.query('hogares', where: 'local_id = ? AND deleted_at IS NULL', whereArgs: [localId]);
      final List<HogarResumen> lista = [];

      for (var h in hgMaps) {
        lista.add(HogarResumen(
          id: h['id'] as String,
          localId: localId,
          jefeFamilia: h['jefe_familia'] as String? ?? '',
          idSexo: h['id_sexo'] != null ? (h['id_sexo'] as num).toInt() : null,
          idIdioma: h['id_idioma'] != null ? (h['id_idioma'] as num).toInt() : null,
          direccion: h['direccion'] as String?,
          totalHabitantes: (h['total_habitantes'] as num? ?? 0).toInt(),
          personas_0_5: (h['personas_0_5'] as num? ?? 0).toInt(),
          personas_6_11: (h['personas_6_11'] as num? ?? 0).toInt(),
          personas_12_17: (h['personas_12_17'] as num? ?? 0).toInt(),
          personas_18_23: (h['personas_18_23'] as num? ?? 0).toInt(),
          personas_24_34: (h['personas_24_34'] as num? ?? 0).toInt(),
          personas_35_44: (h['personas_35_44'] as num? ?? 0).toInt(),
          personas_45_59: (h['personas_45_59'] as num? ?? 0).toInt(),
          personas_60_69: (h['personas_60_69'] as num? ?? 0).toInt(),
          personas_70_79: (h['personas_70_79'] as num? ?? 0).toInt(),
          personas_80_mas: (h['personas_80_mas'] as num? ?? 0).toInt(),
          personasNoEdad: (h['personas_no_edad'] as num? ?? 0).toInt(),
          updatedAt: h['updated_at'] != null ? DateTime.parse(h['updated_at'] as String) : null,
        ));
      }

      return HogarListResponse(
        localId: localId,
        nombreLocal: nomLoc,
        idTipo: idTipo,
        idCondicionLocal: idCond,
        numeroHogaresEsperados: numHogEsp,
        hogaresRegistrados: lista.length,
        hogares: lista,
      );
    } catch (e) {
      throw HogarApiException(code: 'db_error', message: 'Error cargando hogares locales: $e');
    }
  }

  Future<Hogar> crearHogar(
    String localId, {
    String? jefeFamilia,
    int? idSexo,
    int? idIdioma,
    String? direccion,
    int? totalHabitantes,
    int? p0_5, int? p6_11, int? p12_17, int? p18_23,
    int? p24_34, int? p35_44, int? p45_59, int? p60_69,
    int? p70_79, int? p80mas, int? pNoEdad,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/hogares/local/$localId');
      final body = json.encode({
        if (jefeFamilia != null && jefeFamilia.isNotEmpty) 'jefe_familia': jefeFamilia,
        if (idSexo != null) 'id_sexo': idSexo,
        if (idIdioma != null) 'id_idioma': idIdioma,
        if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
        'total_habitantes': totalHabitantes ?? 0,
        'personas_0_5': p0_5 ?? 0,
        'personas_6_11': p6_11 ?? 0,
        'personas_12_17': p12_17 ?? 0,
        'personas_18_23': p18_23 ?? 0,
        'personas_24_34': p24_34 ?? 0,
        'personas_35_44': p35_44 ?? 0,
        'personas_45_59': p45_59 ?? 0,
        'personas_60_69': p60_69 ?? 0,
        'personas_70_79': p70_79 ?? 0,
        'personas_80_mas': p80mas ?? 0,
        'personas_no_edad': pNoEdad ?? 0,
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final hg = Hogar.fromJson(data);
        await DatabaseHelper().insertEntity('hogares', hg.toMapDB());
        return hg;
      } else if (response.statusCode == 409 || response.statusCode == 422 || response.statusCode == 503) {
        _handleError(response);
      }
    } catch (e) {
      if (e is HogarApiException) rethrow;
    }

    final nuevoHogar = Hogar(
      id: _uuid.v4(),
      idLocal: localId,
      jefeFamilia: jefeFamilia ?? '',
      idSexo: idSexo,
      idIdioma: idIdioma,
      direccion: direccion,
      totalHabitantes: totalHabitantes,
      personas_0_5: p0_5,
      personas_6_11: p6_11,
      personas_12_17: p12_17,
      personas_18_23: p18_23,
      personas_24_34: p24_34,
      personas_35_44: p35_44,
      personas_45_59: p45_59,
      personas_60_69: p60_69,
      personas_70_79: p70_79,
      personas_80_mas: p80mas,
      personasNoEdad: pNoEdad,
      updatedAt: DateTime.now(),
      syncDirty: true,
    );
    await DatabaseHelper().insertEntity('hogares', nuevoHogar.toMapDB());
    return nuevoHogar;
  }

  Future<Hogar> editarHogar(
    String hogarId, {
    String? jefeFamilia,
    int? idSexo,
    int? idIdioma,
    String? direccion,
    int? totalHabitantes,
    int? p0_5, int? p6_11, int? p12_17, int? p18_23,
    int? p24_34, int? p35_44, int? p45_59, int? p60_69,
    int? p70_79, int? p80mas, int? pNoEdad,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/hogares/$hogarId');
      final payload = <String, dynamic>{};
      if (jefeFamilia != null) payload['jefe_familia'] = jefeFamilia;
      if (idSexo != null) payload['id_sexo'] = idSexo;
      if (idIdioma != null) payload['id_idioma'] = idIdioma;
      if (direccion != null) payload['direccion'] = direccion;
      if (totalHabitantes != null) payload['total_habitantes'] = totalHabitantes;
      if (p0_5 != null) payload['personas_0_5'] = p0_5;
      if (p6_11 != null) payload['personas_6_11'] = p6_11;
      if (p12_17 != null) payload['personas_12_17'] = p12_17;
      if (p18_23 != null) payload['personas_18_23'] = p18_23;
      if (p24_34 != null) payload['personas_24_34'] = p24_34;
      if (p35_44 != null) payload['personas_35_44'] = p35_44;
      if (p45_59 != null) payload['personas_45_59'] = p45_59;
      if (p60_69 != null) payload['personas_60_69'] = p60_69;
      if (p70_79 != null) payload['personas_70_79'] = p70_79;
      if (p80mas != null) payload['personas_80_mas'] = p80mas;
      if (pNoEdad != null) payload['personas_no_edad'] = pNoEdad;

      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hg = Hogar.fromJson(data);
        await DatabaseHelper().insertEntity('hogares', hg.toMapDB());
        return hg;
      } else if (response.statusCode == 409 || response.statusCode == 422) {
        _handleError(response);
      }
    } catch (e) {
      if (e is HogarApiException) rethrow;
    }

    final db = await DatabaseHelper().database;
    final row = await db.query('hogares', where: 'id = ?', whereArgs: [hogarId]);
    if (row.isNotEmpty) {
      final h = row.first;
      final updateData = <String, dynamic>{
        'id': hogarId,
        'local_id': h['local_id'],
        'jefe_familia': jefeFamilia ?? h['jefe_familia'],
        'id_sexo': idSexo ?? h['id_sexo'],
        'id_idioma': idIdioma ?? h['id_idioma'],
        'direccion': direccion ?? h['direccion'],
        'total_habitantes': totalHabitantes ?? h['total_habitantes'],
        'personas_0_5': p0_5 ?? h['personas_0_5'],
        'personas_6_11': p6_11 ?? h['personas_6_11'],
        'personas_12_17': p12_17 ?? h['personas_12_17'],
        'personas_18_23': p18_23 ?? h['personas_18_23'],
        'personas_24_34': p24_34 ?? h['personas_24_34'],
        'personas_35_44': p35_44 ?? h['personas_35_44'],
        'personas_45_59': p45_59 ?? h['personas_45_59'],
        'personas_60_69': p60_69 ?? h['personas_60_69'],
        'personas_70_79': p70_79 ?? h['personas_70_79'],
        'personas_80_mas': p80mas ?? h['personas_80_mas'],
        'personas_no_edad': pNoEdad ?? h['personas_no_edad'],
        'updated_at': DateTime.now().toIso8601String(),
        'sync_dirty': 1,
      };
      await DatabaseHelper().insertEntity('hogares', updateData);
      return Hogar(
        id: hogarId,
        idLocal: h['local_id'] as String,
        jefeFamilia: (updateData['jefe_familia'] as String?) ?? '',
        idSexo: (updateData['id_sexo'] as num?)?.toInt(),
        idIdioma: (updateData['id_idioma'] as num?)?.toInt(),
        direccion: updateData['direccion'] as String?,
        totalHabitantes: (updateData['total_habitantes'] as num?)?.toInt(),
        personas_0_5: (updateData['personas_0_5'] as num?)?.toInt(),
        personas_6_11: (updateData['personas_6_11'] as num?)?.toInt(),
        personas_12_17: (updateData['personas_12_17'] as num?)?.toInt(),
        personas_18_23: (updateData['personas_18_23'] as num?)?.toInt(),
        personas_24_34: (updateData['personas_24_34'] as num?)?.toInt(),
        personas_35_44: (updateData['personas_35_44'] as num?)?.toInt(),
        personas_45_59: (updateData['personas_45_59'] as num?)?.toInt(),
        personas_60_69: (updateData['personas_60_69'] as num?)?.toInt(),
        personas_70_79: (updateData['personas_70_79'] as num?)?.toInt(),
        personas_80_mas: (updateData['personas_80_mas'] as num?)?.toInt(),
        personasNoEdad: (updateData['personas_no_edad'] as num?)?.toInt(),
        updatedAt: DateTime.now(),
        syncDirty: true,
      );
    }
    throw HogarApiException(code: 'not_found', message: 'Hogar no encontrado localmente');
  }

  Future<void> eliminarHogar(String hogarId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/hogares/$hogarId');
      await http.delete(uri).timeout(const Duration(seconds: 4));
    } catch (_) {}

    await DatabaseHelper().softDeleteEntity('hogares', hogarId);
  }

  void _handleError(http.Response response) {
    try {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is Map) {
          throw HogarApiException(
            code: detail['error'] as String? ?? 'api_error',
            message: detail['message'] as String? ?? 'Ocurrió un error',
            data: detail['data'] as Map<String, dynamic>?,
          );
        } else if (detail is String) {
          throw HogarApiException(code: 'api_error', message: detail);
        }
      }
    } catch (e) {
      if (e is HogarApiException) rethrow;
    }
    throw HogarApiException(
      code: 'http_${response.statusCode}',
      message: 'Respuesta del servidor no válida (${response.statusCode})',
    );
  }
}
