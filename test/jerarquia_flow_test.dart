import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:carto_digital/core/models/capa_geometrica.dart';
import 'package:carto_digital/core/models/jerarquia.dart';
import 'package:carto_digital/core/services/hogar_service.dart';

void main() {
  group('Validación de Modelos y Serialización Front-End (Ingreso y Edición)', () {
    test('Ciclo de vida Estructura (PuntoEstructura) - Creación, Edición y GeoJSON', () {
      final puntoNuevo = PuntoEstructura.nuevo(
        coordenadas: const LatLng(16.1228, -90.6151),
        nombre: 'Estructura Inicial',
        idCategoria: 1,
        idTipo: 1,
        idEstructuraUser: 100,
        estado: EstadoEstructura.presente,
        nivelesCantidad: 2,
        notas: 'Nota inicial',
      );

      expect(puntoNuevo.nombre, 'Estructura Inicial');
      expect(puntoNuevo.nivelesCantidad, 2);
      expect(puntoNuevo.syncDirty, true);

      // Edición de datos alfanuméricos
      final puntoEditado = puntoNuevo.copyWith(
        nombre: 'Estructura Editada',
        nivelesCantidad: 3,
        notas: 'Nota editada',
        idCategoria: 2,
      );

      expect(puntoEditado.nombre, 'Estructura Editada');
      expect(puntoEditado.nivelesCantidad, 3);
      expect(puntoEditado.notas, 'Nota editada');

      // Conversión a GeoJSON para envío a PostGIS (features.py)
      final geoJson = puntoEditado.toGeoJson();
      expect(geoJson['type'], 'Feature');
      expect(geoJson['id'], puntoEditado.id);
      expect(geoJson['properties']['nombre'], 'Estructura Editada');
      expect(geoJson['properties']['niveles_cantidad'], 3);
      expect(geoJson['properties']['id_categoria'], 2);
      expect(geoJson['properties']['id_tipo'], 1);
    });

    test('Ciclo de vida Nivel - Creación, Edición y Mapeo DB', () {
      final nivel = Nivel.nuevo(
        idEstructura: 'est-uuid-1',
        numeroNivel: 1,
        numeroLocales: 4,
        descripcion: 'Planta Baja',
      );

      expect(nivel.numeroNivel, 1);
      expect(nivel.numeroLocales, 4);
      expect(nivel.descripcion, 'Planta Baja');

      // Edición
      final nivelEditado = nivel.copyWith(
        numeroLocales: 5,
        descripcion: 'Planta Baja Ampliada',
      );

      expect(nivelEditado.numeroLocales, 5);
      expect(nivelEditado.descripcion, 'Planta Baja Ampliada');

      // Mapeo SQLite DB
      final mapDB = nivelEditado.toMapDB();
      expect(mapDB['id'], nivel.id);
      expect(mapDB['estructura_id'], 'est-uuid-1');
      expect(mapDB['numero'], 1);
      expect(mapDB['numero_locales'], 5);
      expect(mapDB['descripcion'], 'Planta Baja Ampliada');
      expect(mapDB['sync_dirty'], 1);
    });

    test('Ciclo de vida Local - Creación, Edición y Mapeo DB', () {
      final local = Local.nuevo(
        idNivel: 'niv-uuid-1',
        nombre: 'Local 101',
        idTipo: 1,
        idCondicionLocal: 1,
        numeroHogares: 2,
        descripcion: 'Frente al pasillo',
      );

      expect(local.nombre, 'Local 101');
      expect(local.idTipo, 1);
      expect(local.numeroHogares, 2);

      // Edición
      final localEditado = local.copyWith(
        nombre: 'Local 101 Comercial',
        numeroHogares: 3,
        descripcion: 'Frente al pasillo - Ampliado',
      );

      expect(localEditado.nombre, 'Local 101 Comercial');
      expect(localEditado.numeroHogares, 3);
      expect(localEditado.descripcion, 'Frente al pasillo - Ampliado');

      // Mapeo SQLite DB
      final mapDB = localEditado.toMapDB();
      expect(mapDB['nivel_id'], 'niv-uuid-1');
      expect(mapDB['nombre_local'], 'Local 101 Comercial');
      expect(mapDB['numero_hogares'], 3);
      expect(mapDB['sync_dirty'], 1);
    });

    test('Ciclo de vida Hogar y HogarResumen - Validación matemática y consistencia', () {
      final hogar = Hogar.nuevo(
        idLocal: 'loc-uuid-1',
        jefeFamilia: 'María García',
        idSexo: 2,
        idIdioma: 1,
        direccion: 'Interior 3B',
      );

      expect(hogar.jefeFamilia, 'María García');
      expect(hogar.idSexo, 2);
      expect(hogar.sexoJefe, 'Femenino');

      // Simulación de respuesta JSON del backend (con id_tipo y id_tipo_local unificados)
      final backendResponse = {
        'id': 'hog-123',
        'local_id': 'loc-uuid-1',
        'jefe_familia': 'María García',
        'id_sexo': 2,
        'nombre_sexo': 'Femenino',
        'id_idioma': 1,
        'nombre_idioma': 'Español',
        'direccion': 'Interior 3B',
        'total_habitantes': 3,
        'personas_0_5': 1,
        'personas_6_11': 0,
        'personas_12_17': 0,
        'personas_18_23': 0,
        'personas_24_34': 2,
        'personas_35_44': 0,
        'personas_45_59': 0,
        'personas_60_69': 0,
        'personas_70_79': 0,
        'personas_80_mas': 0,
        'personas_no_edad': 0,
        'updated_at': '2026-09-07T18:00:00.000Z',
      };

      final resumen = HogarResumen.fromJson(backendResponse);
      expect(resumen.jefeFamilia, 'María García');
      expect(resumen.totalHabitantes, 3);
      expect(resumen.sumaEdades, 3);
      expect(resumen.esValidoMatematicamente, true);

      // Parseo de lista con id_tipo estandarizado
      final listResponseJson = {
        'local_id': 'loc-uuid-1',
        'nombre_local': 'Local Comercial',
        'id_tipo': 1,
        'id_tipo_local': 1,
        'id_condicion_local': 1,
        'numero_hogares_esperados': 2,
        'hogares_registrados': 1,
        'hogares': [backendResponse],
      };

      final listResp = HogarListResponse.fromJson(listResponseJson);
      expect(listResp.idTipo, 1);
      expect(listResp.numeroHogaresEsperados, 2);
      expect(listResp.hogaresRegistrados, 1);
      expect(listResp.esCompleto, false); // 1 < 2 esperados
    });
  });
}
