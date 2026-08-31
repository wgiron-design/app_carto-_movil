import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/capa_registro.dart';
import '../models/capa_geometrica.dart';

class PostGISService {
  static final PostGISService _instance = PostGISService._internal();
  factory PostGISService() => _instance;
  PostGISService._internal();

  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  late String baseUrl = defaultBaseUrl;

  /// Token JWT del usuario autenticado en sesión
  String? authToken;

  Map<String, String> get _authHeaders => {
    if (authToken != null && authToken!.trim().isNotEmpty)
      'Authorization': 'Bearer ${authToken!.trim()}',
  };

  void setBaseUrl(String url) {
    baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Intenta conectar con el servidor backend probando alternativas si la URL por defecto falla
  Future<bool> probeAndFixBaseUrl() async {
    final candidates = {
      baseUrl,
      defaultBaseUrl,
      'http://localhost:8000',
      'http://10.0.2.2:8000',
      'http://127.0.0.1:8000',
    };

    for (final candidate in candidates) {
      try {
        final res = await http.get(Uri.parse('$candidate/')).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          setBaseUrl(candidate);
          debugPrint('[PostGISService] Servidor backend encontrado en: $candidate');
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Obtiene únicamente las capas marcadas como activas en PostGIS
  Future<List<CapaRegistro>> getCapasActivas() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/capas')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => CapaRegistro.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('[PostGISService] Error obteniendo capas activas: $e');
    }
    return [];
  }

  /// Descarga estructuras (Puntos) GeoJSON desde PostGIS
  Future<List<PuntoEstructura>> getEstructuras() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/capas/estructuras/features')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = (data['features'] as List? ?? []);
        return features.map((f) => PuntoEstructura.fromGeoJson(f)).toList();
      }
    } catch (e) {
      debugPrint('[PostGISService] Error obteniendo estructuras: $e');
    }
    return [];
  }

  /// Descarga caminos (Líneas) GeoJSON desde PostGIS
  Future<List<LineaCamino>> getCaminos() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/capas/caminos/features')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = (data['features'] as List? ?? []);
        return features.map((f) => LineaCamino.fromGeoJson(f)).toList();
      }
    } catch (e) {
      debugPrint('[PostGISService] Error obteniendo caminos: $e');
    }
    return [];
  }

  /// Descarga UPMs (Polígonos) GeoJSON desde PostGIS (filtrado por usuario y rol autenticado)
  Future<List<PoligonoUPM>> getUPMs() async {
    try {
      final headers = _authHeaders;
      final response = await http.get(
        Uri.parse('$baseUrl/api/capas/upms/features'),
        headers: headers.isNotEmpty ? headers : null,
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = (data['features'] as List? ?? []);
        return features.map((f) => PoligonoUPM.fromGeoJson(f)).toList();
      } else {
        debugPrint('[PostGISService] Error HTTP ${response.statusCode} obteniendo UPMs: ${response.body}');
      }
    } catch (e) {
      debugPrint('[PostGISService] Error obteniendo UPMs: $e');
    }
    return [];
  }

  /// Crea o actualiza una feature en PostGIS.
  /// Retorna `true` si se guardó correctamente.
  /// En caso de error, registra detalles en consola para depuración.
  Future<bool> guardarFeature(String tabla, Map<String, dynamic> featureGeoJson) async {
    final url = '$baseUrl/api/capas/$tabla/features';
    try {
      debugPrint('[PostGISService] POST $url → id=${featureGeoJson['id']}');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(featureGeoJson),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[PostGISService] ✅ Guardado OK en $tabla (${response.statusCode})');
        return true;
      } else {
        debugPrint('[PostGISService] ❌ Error HTTP ${response.statusCode} en $tabla: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[PostGISService] ❌ Excepción guardando en $tabla ($url): $e');
      return false;
    }
  }

  /// Soft-delete de una feature por ID en PostGIS.
  /// Marca deleted_at en el servidor en lugar de borrar físicamente.
  Future<bool> eliminarFeature(String tabla, String id, {String? updatedBy}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/capas/$tabla/features/$id')
          .replace(queryParameters: updatedBy != null ? {'updated_by': updatedBy} : null);
      final response = await http.delete(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[PostGISService] Error eliminando (soft-delete) feature $id de $tabla: $e');
      return false;
    }
  }

  /// Envía la sincronización de geometrías offline y jerarquía (Batch Sync)
  Future<bool> sincronizarOfflineBatch({
    required List<PuntoEstructura> puntos,
    required List<LineaCamino> lineas,
    required List<PoligonoUPM> poligonos,
    List<Map<String, dynamic>>? niveles,
    List<Map<String, dynamic>>? locales,
    List<Map<String, dynamic>>? hogares,
    String? userId,
    String? deviceId,
  }) async {
    try {
      final payload = {
        'puntos': puntos.map((p) => p.toGeoJson()).toList(),
        'lineas': lineas.map((l) => l.toGeoJson()).toList(),
        'poligonos': poligonos.map((p) => p.toGeoJson()).toList(),
        'niveles': niveles ?? [],
        'locales': locales ?? [],
        'hogares': hogares ?? [],
        if (userId != null) 'user_id': userId,
        if (deviceId != null) 'device_id': deviceId,
      };

      debugPrint('[PostGISService] Enviando batch sync con ${puntos.length} puntos, ${lineas.length} líneas, ${poligonos.length} polígonos, ${(niveles ?? []).length} niveles, ${(locales ?? []).length} locales, ${(hogares ?? []).length} hogares');

      final response = await http.post(
        Uri.parse('$baseUrl/api/sync'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[PostGISService] Respuesta batch sync: status=${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[PostGISService] Error en sincronización por lote: $e');
      return false;
    }
  }

  /// Obtiene el conteo de registros en PostGIS para las 3 tablas.
  /// Retorna null si hay un error de conexión.
  Future<Map<String, int>?> contarElementosEnPostGIS() async {
    try {
      final headers = _authHeaders.isNotEmpty ? _authHeaders : null;
      final futuresCount = await Future.wait([
        http.get(Uri.parse('$baseUrl/api/capas/estructuras/count')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('$baseUrl/api/capas/caminos/count')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('$baseUrl/api/capas/upms/count'), headers: headers).timeout(const Duration(seconds: 5)),
      ]);

      if (futuresCount.every((r) => r.statusCode == 200)) {
        return {
          'puntos': json.decode(futuresCount[0].body)['count'] as int,
          'lineas': json.decode(futuresCount[1].body)['count'] as int,
          'poligonos': json.decode(futuresCount[2].body)['count'] as int,
        };
      }

      // Fallback a /features si /count no retorna 200
      final futuresFeatures = await Future.wait([
        http.get(Uri.parse('$baseUrl/api/capas/estructuras/features')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('$baseUrl/api/capas/caminos/features')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('$baseUrl/api/capas/upms/features'), headers: headers).timeout(const Duration(seconds: 6)),
      ]);

      if (futuresFeatures.every((r) => r.statusCode == 200)) {
        return {
          'puntos': (json.decode(futuresFeatures[0].body)['features'] as List? ?? []).length,
          'lineas': (json.decode(futuresFeatures[1].body)['features'] as List? ?? []).length,
          'poligonos': (json.decode(futuresFeatures[2].body)['features'] as List? ?? []).length,
        };
      }
      return null;
    } catch (e) {
      debugPrint('[PostGISService] Error contando elementos: $e');
      return null;
    }
  }
}

