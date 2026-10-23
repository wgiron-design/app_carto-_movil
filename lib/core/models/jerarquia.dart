import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS JERÁRQUICOS — Paso 4
//
// Estructura de datos (sin geometría propia):
//
//  PuntoEstructura (georreferenciado — Paso 3)
//    └── Nivel          (id, estructura_id, numero)
//          └── Local    (id, nivel_id, nombre, uso)
//                └── Hogar  (id, local_id, jefe_familia)
//
// Todas las relaciones son uno-a-muchos.
// Solo el Punto tiene coordenadas geográficas.
// ─────────────────────────────────────────────────────────────────────────────

const _uuid = Uuid();

/// Representa un nivel (piso) dentro de una estructura.
class Nivel {
  final String id;
  final String idEstructura;
  final int numeroNivel;
  final int numeroLocales;
  final String? descripcion;
  final DateTime updatedAt;
  final bool syncDirty;
  final List<Local> locales;

  Nivel({
    required this.id,
    required this.idEstructura,
    required this.numeroNivel,
    this.numeroLocales = 1,
    this.descripcion,
    DateTime? updatedAt,
    this.syncDirty = true,
    List<Local>? locales,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        locales = locales ?? [];

  /// Crea un nuevo Nivel con ID autogenerado
  factory Nivel.nuevo({
    required String idEstructura,
    required int numeroNivel,
    int numeroLocales = 1,
    String? descripcion,
  }) {
    return Nivel(
      id: _uuid.v4(),
      idEstructura: idEstructura,
      numeroNivel: numeroNivel,
      numeroLocales: numeroLocales,
      descripcion: descripcion,
      syncDirty: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'id_estructura': idEstructura,
        'numero_nivel': numeroNivel,
        'numero_locales': numeroLocales,
        'descripcion': descripcion,
        'updated_at': updatedAt.toIso8601String(),
        'sync_dirty': syncDirty ? 1 : 0,
        'locales': locales.map((l) => l.toJson()).toList(),
      };

  factory Nivel.fromJson(Map<String, dynamic> json) => Nivel(
        id: json['id'] as String,
        idEstructura: (json['id_estructura'] ?? json['estructura_id'] ?? '') as String,
        numeroNivel: ((json['numero_nivel'] ?? json['numero']) as num).toInt(),
        numeroLocales: json['numero_locales'] != null ? (json['numero_locales'] as num).toInt() : 1,
        descripcion: json['descripcion'] as String?,
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
        syncDirty: json['sync_dirty'] == 1 || json['sync_dirty'] == true,
        locales: (json['locales'] as List? ?? [])
            .map((l) => Local.fromJson(l as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMapDB() {
    return {
      'id': id,
      'estructura_id': idEstructura,
      'numero': numeroNivel,
      'numero_locales': numeroLocales,
      'descripcion': descripcion,
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
    };
  }

  Nivel copyWith({int? numeroNivel, int? numeroLocales, String? descripcion, List<Local>? locales}) => Nivel(
        id: id,
        idEstructura: idEstructura,
        numeroNivel: numeroNivel ?? this.numeroNivel,
        numeroLocales: numeroLocales ?? this.numeroLocales,
        descripcion: descripcion ?? this.descripcion,
        updatedAt: DateTime.now(),
        syncDirty: true,
        locales: locales ?? this.locales,
      );

  int get totalLocales => locales.length;
  int get totalHogares => locales.fold(0, (sum, l) => sum + l.hogares.length);

  @override
  String toString() => 'Nivel #$numeroNivel ($totalLocales locales)';
}

// ─────────────────────────────────────────────────────────────────────────────

/// Representa un local (vivienda, comercio, apartamento) dentro de un nivel.
class Local {
  final String id;
  final String idNivel;
  final String? nombre;
  final int idTipo;
  final int? idCondicionLocal;
  final String? nombreTipo;
  final String? nombreCondicion;
  final int? numeroHogares;
  final String? descripcion;
  final DateTime updatedAt;
  final bool syncDirty;
  final List<Hogar> hogares;

  // Getters de compatibilidad retroactiva
  String get usoActual => nombreTipo ?? 'Tipo #$idTipo';
  String? get ocupacion => nombreCondicion;

  Local({
    required this.id,
    required this.idNivel,
    this.nombre,
    this.idTipo = 1,
    this.idCondicionLocal,
    this.nombreTipo,
    this.nombreCondicion,
    this.numeroHogares,
    this.descripcion,
    DateTime? updatedAt,
    this.syncDirty = true,
    List<Hogar>? hogares,
    String? usoActual,
    String? ocupacion,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        hogares = hogares ?? [];


  factory Local.nuevo({
    required String idNivel,
    String? nombre,
    required int idTipo,
    int? idCondicionLocal,
    String? nombreTipo,
    String? nombreCondicion,
    int? numeroHogares,
    String? descripcion,
  }) {
    return Local(
      id: _uuid.v4(),
      idNivel: idNivel,
      nombre: nombre,
      idTipo: idTipo,
      idCondicionLocal: idCondicionLocal,
      nombreTipo: nombreTipo,
      nombreCondicion: nombreCondicion,
      numeroHogares: numeroHogares,
      descripcion: descripcion,
      syncDirty: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'id_nivel': idNivel,
        'nombre_local': nombre,
        'id_tipo': idTipo,
        'id_condicion_local': idCondicionLocal,
        'nombre_tipo': nombreTipo,
        'nombre_condicion': nombreCondicion,
        'numero_hogares': numeroHogares,
        'descripcion': descripcion,
        'updated_at': updatedAt.toIso8601String(),
        'sync_dirty': syncDirty ? 1 : 0,
        'hogares': hogares.map((h) => h.toJson()).toList(),
      };

  factory Local.fromJson(Map<String, dynamic> json) => Local(
        id: json['id'] as String,
        idNivel: (json['id_nivel'] ?? json['nivel_id'] ?? '') as String,
        nombre: (json['nombre_local'] ?? json['nombre']) as String?,
        idTipo: (json['id_tipo'] as num?)?.toInt() ?? 1,
        idCondicionLocal: json['id_condicion_local'] != null ? (json['id_condicion_local'] as num).toInt() : null,
        nombreTipo: json['nombre_tipo'] as String?,
        nombreCondicion: json['nombre_condicion'] as String?,
        numeroHogares: json['numero_hogares'] != null ? (json['numero_hogares'] as num).toInt() : null,
        descripcion: json['descripcion'] as String?,
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
        syncDirty: json['sync_dirty'] == 1 || json['sync_dirty'] == true,
        hogares: (json['hogares'] as List? ?? [])
            .map((h) => Hogar.fromJson(h as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMapDB() {
    return {
      'id': id,
      'nivel_id': idNivel,
      'nombre': nombre,
      'nombre_local': nombre,
      'id_tipo': idTipo,
      'id_condicion_local': idCondicionLocal,
      'numero_hogares': numeroHogares,
      'descripcion': descripcion,
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
    };
  }

  Local copyWith({
    String? nombre,
    int? idTipo,
    int? idCondicionLocal,
    String? nombreTipo,
    String? nombreCondicion,
    int? numeroHogares,
    String? descripcion,
    List<Hogar>? hogares,
  }) => Local(
        id: id,
        idNivel: idNivel,
        nombre: nombre ?? this.nombre,
        idTipo: idTipo ?? this.idTipo,
        idCondicionLocal: idCondicionLocal ?? this.idCondicionLocal,
        nombreTipo: nombreTipo ?? this.nombreTipo,
        nombreCondicion: nombreCondicion ?? this.nombreCondicion,
        numeroHogares: numeroHogares ?? this.numeroHogares,
        descripcion: descripcion ?? this.descripcion,
        updatedAt: DateTime.now(),
        syncDirty: true,
        hogares: hogares ?? this.hogares,
      );

  int get totalHogares => hogares.length;

  @override
  String toString() => 'Local ${nombre ?? id} ($totalHogares hogares)';
}


// ─────────────────────────────────────────────────────────────────────────────

/// Representa un hogar dentro de un local.
class Hogar {
  final String id;
  final String idLocal;
  final String jefeFamilia;
  final int? idSexo;
  final int? idIdioma;
  final String? nombreSexo;
  final String? nombreIdioma;
  final String? direccion;
  final int? totalHabitantes;
  final int? personas_0_5;
  final int? personas_6_11;
  final int? personas_12_17;
  final int? personas_18_23;
  final int? personas_24_34;
  final int? personas_35_44;
  final int? personas_45_59;
  final int? personas_60_69;
  final int? personas_70_79;
  final int? personas_80_mas;
  final int? personasNoEdad;
  final DateTime updatedAt;
  final bool syncDirty;

  // Getters de compatibilidad retroactiva
  String? get sexoJefe => nombreSexo ?? (idSexo == 1 ? 'Masculino' : idSexo == 2 ? 'Femenino' : null);
  String? get idioma => nombreIdioma;

  Hogar({
    required this.id,
    required this.idLocal,
    required this.jefeFamilia,
    this.idSexo,
    this.idIdioma,
    this.nombreSexo,
    this.nombreIdioma,
    this.direccion,
    this.totalHabitantes,
    this.personas_0_5,
    this.personas_6_11,
    this.personas_12_17,
    this.personas_18_23,
    this.personas_24_34,
    this.personas_35_44,
    this.personas_45_59,
    this.personas_60_69,
    this.personas_70_79,
    this.personas_80_mas,
    this.personasNoEdad,
    DateTime? updatedAt,
    this.syncDirty = true,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory Hogar.nuevo({
    required String idLocal,
    required String jefeFamilia,
    int? idSexo,
    int? idIdioma,
    String? direccion,
  }) {
    return Hogar(
      id: _uuid.v4(),
      idLocal: idLocal,
      jefeFamilia: jefeFamilia,
      idSexo: idSexo,
      idIdioma: idIdioma,
      direccion: direccion,
      syncDirty: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'local_id': idLocal,
        'id_local': idLocal,
        'jefe_familia': jefeFamilia,
        'id_sexo': idSexo,
        'id_idioma': idIdioma,
        'nombre_sexo': nombreSexo,
        'nombre_idioma': nombreIdioma,
        'direccion': direccion,
        'total_habitantes': totalHabitantes,
        'personas_0_5': personas_0_5,
        'personas_6_11': personas_6_11,
        'personas_12_17': personas_12_17,
        'personas_18_23': personas_18_23,
        'personas_24_34': personas_24_34,
        'personas_35_44': personas_35_44,
        'personas_45_59': personas_45_59,
        'personas_60_69': personas_60_69,
        'personas_70_79': personas_70_79,
        'personas_80_mas': personas_80_mas,
        'personas_no_edad': personasNoEdad,
        'updated_at': updatedAt.toIso8601String(),
        'sync_dirty': syncDirty ? 1 : 0,
      };

  factory Hogar.fromJson(Map<String, dynamic> json) => Hogar(
        id: json['id'] as String,
        idLocal: (json['local_id'] ?? json['id_local'] ?? '') as String,
        jefeFamilia: json['jefe_familia'] as String? ?? '',
        idSexo: json['id_sexo'] != null ? (json['id_sexo'] as num).toInt() : null,
        idIdioma: json['id_idioma'] != null ? (json['id_idioma'] as num).toInt() : null,
        nombreSexo: json['nombre_sexo'] as String?,
        nombreIdioma: json['nombre_idioma'] as String?,
        direccion: json['direccion'] as String?,
        totalHabitantes: json['total_habitantes'] != null ? (json['total_habitantes'] as num).toInt() : null,
        personas_0_5: json['personas_0_5'] != null ? (json['personas_0_5'] as num).toInt() : null,
        personas_6_11: json['personas_6_11'] != null ? (json['personas_6_11'] as num).toInt() : null,
        personas_12_17: json['personas_12_17'] != null ? (json['personas_12_17'] as num).toInt() : null,
        personas_18_23: json['personas_18_23'] != null ? (json['personas_18_23'] as num).toInt() : null,
        personas_24_34: json['personas_24_34'] != null ? (json['personas_24_34'] as num).toInt() : null,
        personas_35_44: json['personas_35_44'] != null ? (json['personas_35_44'] as num).toInt() : null,
        personas_45_59: json['personas_45_59'] != null ? (json['personas_45_59'] as num).toInt() : null,
        personas_60_69: json['personas_60_69'] != null ? (json['personas_60_69'] as num).toInt() : null,
        personas_70_79: json['personas_70_79'] != null ? (json['personas_70_79'] as num).toInt() : null,
        personas_80_mas: json['personas_80_mas'] != null ? (json['personas_80_mas'] as num).toInt() : null,
        personasNoEdad: json['personas_no_edad'] != null ? (json['personas_no_edad'] as num).toInt() : null,
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
        syncDirty: json['sync_dirty'] == 1 || json['sync_dirty'] == true,
      );

  Map<String, dynamic> toMapDB() {
    return {
      'id': id,
      'local_id': idLocal,
      'jefe_familia': jefeFamilia,
      'id_sexo': idSexo,
      'id_idioma': idIdioma,
      'direccion': direccion,
      'total_habitantes': totalHabitantes,
      'personas_0_5': personas_0_5,
      'personas_6_11': personas_6_11,
      'personas_12_17': personas_12_17,
      'personas_18_23': personas_18_23,
      'personas_24_34': personas_24_34,
      'personas_35_44': personas_35_44,
      'personas_45_59': personas_45_59,
      'personas_60_69': personas_60_69,
      'personas_70_79': personas_70_79,
      'personas_80_mas': personas_80_mas,
      'personas_no_edad': personasNoEdad,
      'updated_at': updatedAt.toIso8601String(),
      'sync_dirty': syncDirty ? 1 : 0,
    };
  }

  Hogar copyWith({
    String? jefeFamilia,
    int? idSexo,
    int? idIdioma,
    String? nombreSexo,
    String? nombreIdioma,
    String? direccion,
    int? totalHabitantes,
    int? personas_0_5,
    int? personas_6_11,
    int? personas_12_17,
    int? personas_18_23,
    int? personas_24_34,
    int? personas_35_44,
    int? personas_45_59,
    int? personas_60_69,
    int? personas_70_79,
    int? personas_80_mas,
    int? personasNoEdad,
  }) =>
      Hogar(
        id: id,
        idLocal: idLocal,
        jefeFamilia: jefeFamilia ?? this.jefeFamilia,
        idSexo: idSexo ?? this.idSexo,
        idIdioma: idIdioma ?? this.idIdioma,
        nombreSexo: nombreSexo ?? this.nombreSexo,
        nombreIdioma: nombreIdioma ?? this.nombreIdioma,
        direccion: direccion ?? this.direccion,
        totalHabitantes: totalHabitantes ?? this.totalHabitantes,
        personas_0_5: personas_0_5 ?? this.personas_0_5,
        personas_6_11: personas_6_11 ?? this.personas_6_11,
        personas_12_17: personas_12_17 ?? this.personas_12_17,
        personas_18_23: personas_18_23 ?? this.personas_18_23,
        personas_24_34: personas_24_34 ?? this.personas_24_34,
        personas_35_44: personas_35_44 ?? this.personas_35_44,
        personas_45_59: personas_45_59 ?? this.personas_45_59,
        personas_60_69: personas_60_69 ?? this.personas_60_69,
        personas_70_79: personas_70_79 ?? this.personas_70_79,
        personas_80_mas: personas_80_mas ?? this.personas_80_mas,
        personasNoEdad: personasNoEdad ?? this.personasNoEdad,
        updatedAt: DateTime.now(),
        syncDirty: true,
      );


  @override
  String toString() => 'Hogar: $jefeFamilia';
}
