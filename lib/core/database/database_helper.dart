import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';
import 'package:carto_digital/core/models/capa_geometrica.dart';
import 'package:carto_digital/core/models/jerarquia.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  final Uuid uuid = const Uuid();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath;
    try {
      Directory? extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        dbPath = join(extDir.path, 'carto_digital.sqlite');
      } else {
        Directory docDir = await getApplicationDocumentsDirectory();
        dbPath = join(docDir.path, 'carto_digital.sqlite');
      }
    } catch (e) {
      Directory docDir = await getApplicationDocumentsDirectory();
      dbPath = join(docDir.path, 'carto_digital.sqlite');
    }

    return await openDatabase(
      dbPath,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
      onOpen: (db) async {
        await _seedCatalogos(db);
      },
    );
  }

  Future<void> _seedCatalogos(Database db) async {
    try {
      // 1. Asegurar registro dummy en upm para default_upm
      await db.execute('''
        INSERT OR IGNORE INTO upm (id, nombre, updated_at, sync_dirty, sync_version)
        VALUES ('default_upm', 'UPM por defecto', datetime('now'), 0, 0)
      ''');

      // 2. Tipos de estructura (FORMAL y REFERENCIA, igual que Postgres)
      await db.execute('''
        INSERT OR IGNORE INTO cat_estructuras_tipo (id, nombre) VALUES
        (1, 'FORMAL'),
        (2, 'REFERENCIA')
      ''');

      // 3. Categorías de estructura — catálogo completo (59 registros, igual que Postgres)
      // TIPO 1 = FORMAL (id 1-42)
      final categoriasSQL = [
        "(1,  'Vivienda', 1)",
        "(2,  'Vivienda Multifamiliar', 1)",
        "(3,  'Vivienda y Comercio', 1)",
        "(4,  'Comercio o Servicio', 1)",
        "(5,  'Vivienda Multifamiliar y Comercio', 1)",
        "(6,  'Vivienda en Construcción', 1)",
        "(7,  'Colegios Privados', 1)",
        "(8,  'Institutos', 1)",
        "(9,  'Escuelas Oficiales', 1)",
        "(10, 'Iglesia Católica', 1)",
        "(11, 'Iglesia Evangélica', 1)",
        "(12, 'Iglesia Adventista', 1)",
        "(13, 'Iglesia Mormona', 1)",
        "(14, 'Iglesia Testigos de Jehová', 1)",
        "(15, 'Institución Gubernamental', 1)",
        "(16, 'Instituciones de Salud Pública (Nacional)', 1)",
        "(17, 'Biblioteca', 1)",
        "(18, 'Gasolinera', 1)",
        "(19, 'Industrias o Fábricas', 1)",
        "(20, 'Teatros o Cines', 1)",
        "(21, 'Bancos', 1)",
        "(22, 'Edificio de Apartamentos', 1)",
        "(23, 'Edificio Comercial', 1)",
        "(24, 'Edificio de Apartamentos y Comercio', 1)",
        "(25, 'Hotel o Pensión', 1)",
        "(26, 'Aeropuerto', 1)",
        "(27, 'Centros Comerciales', 1)",
        "(28, 'Mercados Municipales', 1)",
        "(29, 'Museos o Sitios Arqueológicos', 1)",
        "(30, 'Salón de Usos Múltiples', 1)",
        "(31, 'Universidad', 1)",
        "(32, 'Bodega', 1)",
        "(33, 'Bomberos', 1)",
        "(34, 'Municipalidad o Ayuntamiento', 1)",
        "(35, 'Reserva, Brigada o Complejo Militar', 1)",
        "(36, 'Policía Nacional Civil', 1)",
        "(37, 'Instalaciones de Salud Privada', 1)",
        "(38, 'Estadio', 1)",
        "(39, 'Asociaciones Benéficas', 1)",
        "(40, 'ONGs', 1)",
        "(41, 'Coliseos', 1)",
        "(42, 'Planta de Tratamiento de Agua', 1)",
        // TIPO 2 = REFERENCIA (id 43-59)
        "(43, 'PARQUEO', 2)",
        "(44, 'ANTENA TELEFONICA O RADIAL', 2)",
        "(45, 'PARQUE', 2)",
        "(46, 'PLAZA O CENTRO RECREATIVO', 2)",
        "(47, 'PUENTE VEHICULAR', 2)",
        "(48, 'POZO O TANQUE', 2)",
        "(49, 'GRIFO', 2)",
        "(50, 'CEMENTERIO', 2)",
        "(51, 'PILA MUNICIPAL', 2)",
        "(52, 'CAMPOS DE DEPORTES', 2)",
        "(53, 'ANTENA ELECTRICA', 2)",
        "(54, 'PUENTE PEATONAL', 2)",
        "(55, 'ALTARES MAYAS', 2)",
        "(56, 'GARITA DE SEGURIDAD', 2)",
        "(57, 'VERTEDERO MUNICIPAL', 2)",
        "(58, 'MUELLE O PUERTO', 2)",
        "(59, 'TERMINAL DE BUSES', 2)",
      ];

      // Insertar de a lotes para evitar SQLite max compound-select
      for (final row in categoriasSQL) {
        await db.execute(
          'INSERT OR IGNORE INTO cat_estructuras_categoria (id, nombre, tipo) VALUES $row',
        );
      }
    } catch (e) {
      // Evitar que un error en seed bloquee la app
    }
  }


  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE niveles ADD COLUMN numero_locales INTEGER DEFAULT 1');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE locales ADD COLUMN uso_actual TEXT');
      await db.execute('ALTER TABLE locales ADD COLUMN ocupacion TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE locales ADD COLUMN numero_hogares INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN total_habitantes INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN idioma TEXT');
      await db.execute('ALTER TABLE hogares ADD COLUMN sexo_jefe TEXT');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_0_5 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_6_11 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_12_17 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_18_23 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_24_34 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_35_44 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_45_59 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_60_69 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_70_79 INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_80_mas INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN personas_no_edad INTEGER');
    }
    if (oldVersion < 5) {
      // Campos de auditoría y sincronización offline
      for (final table in ['estructuras', 'caminos', 'upm']) {
        await db.execute('ALTER TABLE $table ADD COLUMN created_by TEXT');
        await db.execute('ALTER TABLE $table ADD COLUMN updated_by TEXT');
        await db.execute('ALTER TABLE $table ADD COLUMN device_id TEXT');
        await db.execute('ALTER TABLE $table ADD COLUMN sync_version INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $table ADD COLUMN deleted_at TEXT');
      }
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cat_estructuras_categoria (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          descripcion TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cat_estructuras_tipo (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          id_categoria INTEGER,
          descripcion TEXT,
          FOREIGN KEY (id_categoria) REFERENCES cat_estructuras_categoria (id)
        )
      ''');
      await db.execute('ALTER TABLE estructuras RENAME TO estructuras_old');
      await db.execute('''
        CREATE TABLE estructuras (
          id TEXT PRIMARY KEY,
          upm_id TEXT,
          geom_wkt TEXT,
          x REAL,
          y REAL,
          nombre TEXT,
          notas TEXT,
          id_categoria INTEGER DEFAULT 1,
          id_tipo INTEGER DEFAULT 1,
          estado TEXT,
          niveles_cantidad INTEGER,
          updated_at TEXT,
          sync_dirty INTEGER DEFAULT 1,
          created_by TEXT,
          updated_by TEXT,
          device_id TEXT,
          sync_version INTEGER DEFAULT 0,
          deleted_at TEXT,
          FOREIGN KEY (upm_id) REFERENCES upm (id) ON DELETE CASCADE,
          FOREIGN KEY (id_categoria) REFERENCES cat_estructuras_categoria (id),
          FOREIGN KEY (id_tipo) REFERENCES cat_estructuras_tipo (id)
        )
      ''');
      await db.execute('''
        INSERT INTO estructuras (id, upm_id, geom_wkt, x, y, nombre, notas, id_categoria, id_tipo, estado, niveles_cantidad, updated_at, sync_dirty, created_by, updated_by, device_id, sync_version, deleted_at)
        SELECT id, upm_id, geom_wkt, x, y, nombre, notas, 1, 1, estado, niveles_cantidad, updated_at, sync_dirty, created_by, updated_by, device_id, sync_version, deleted_at FROM estructuras_old
      ''');
      await db.execute('DROP TABLE estructuras_old');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE hogares ADD COLUMN id_sexo INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN id_idioma INTEGER');
      await db.execute('ALTER TABLE hogares ADD COLUMN direccion TEXT');
      for (final table in ['niveles', 'locales', 'hogares']) {
        await db.execute('ALTER TABLE $table ADD COLUMN sync_version INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $table ADD COLUMN deleted_at TEXT');
      }
    }
    if (oldVersion < 8) {
      for (final col in ['nombre', 'codigo_upm', 'notas']) {
        try {
          await db.execute('ALTER TABLE upm ADD COLUMN $col TEXT');
        } catch (_) {}
      }
      for (final col in ['nombre', 'tipo', 'notas']) {
        try {
          await db.execute('ALTER TABLE caminos ADD COLUMN $col TEXT');
        } catch (_) {}
      }
    }
    if (oldVersion < 9) {
      // Eliminar tablas virtuales rtree que no están soportadas en el SQLite de Android
      for (final t in ['upm_index', 'caminos_index', 'estructuras_index']) {
        try {
          await db.execute('DROP TABLE IF EXISTS $t');
        } catch (_) {}
      }
      // Crear índices normales equivalentes
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_upm_bbox ON upm (min_x, max_x, min_y, max_y)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_caminos_bbox ON caminos (min_x, max_x, min_y, max_y)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_estructuras_xy ON estructuras (x, y)'); } catch (_) {}
      // Agregar columna tipo a cat_estructuras_categoria si no existe
      try { await db.execute('ALTER TABLE cat_estructuras_categoria ADD COLUMN tipo INTEGER'); } catch (_) {}
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE upm (
        id TEXT PRIMARY KEY,
        geom_wkt TEXT,
        nombre TEXT,
        codigo_upm TEXT,
        notas TEXT,
        min_x REAL,
        max_x REAL,
        min_y REAL,
        max_y REAL,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        created_by TEXT,
        updated_by TEXT,
        device_id TEXT,
        sync_version INTEGER DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    
    // Índice normal en columnas de bounding box (rtree no disponible en Android)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_upm_bbox ON upm (min_x, max_x, min_y, max_y)');

    await db.execute('''
      CREATE TABLE caminos (
        id TEXT PRIMARY KEY,
        geom_wkt TEXT,
        nombre TEXT,
        tipo TEXT,
        notas TEXT,
        min_x REAL,
        max_x REAL,
        min_y REAL,
        max_y REAL,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        created_by TEXT,
        updated_by TEXT,
        device_id TEXT,
        sync_version INTEGER DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    
    // Índice normal en columnas de bounding box (rtree no disponible en Android)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_caminos_bbox ON caminos (min_x, max_x, min_y, max_y)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cat_estructuras_categoria (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        tipo INTEGER,
        descripcion TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cat_estructuras_tipo (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        id_categoria INTEGER,
        descripcion TEXT,
        FOREIGN KEY (id_categoria) REFERENCES cat_estructuras_categoria (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE estructuras (
        id TEXT PRIMARY KEY,
        upm_id TEXT,
        geom_wkt TEXT,
        x REAL,
        y REAL,
        nombre TEXT,
        notas TEXT,
        id_categoria INTEGER NOT NULL DEFAULT 1,
        id_tipo INTEGER NOT NULL DEFAULT 1,
        estado TEXT,
        niveles_cantidad INTEGER,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        created_by TEXT,
        updated_by TEXT,
        device_id TEXT,
        sync_version INTEGER DEFAULT 0,
        deleted_at TEXT,
        FOREIGN KEY (upm_id) REFERENCES upm (id) ON DELETE CASCADE,
        FOREIGN KEY (id_categoria) REFERENCES cat_estructuras_categoria (id),
        FOREIGN KEY (id_tipo) REFERENCES cat_estructuras_tipo (id)
      )
    ''');
    
    // Índice normal en columna de coordenadas (rtree no disponible en Android)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_estructuras_xy ON estructuras (x, y)');

    await db.execute('''
      CREATE TABLE niveles (
        id TEXT PRIMARY KEY,
        estructura_id TEXT,
        numero INTEGER,
        numero_locales INTEGER DEFAULT 1,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        FOREIGN KEY (estructura_id) REFERENCES estructuras (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE locales (
        id TEXT PRIMARY KEY,
        nivel_id TEXT,
        nombre TEXT,
        uso_actual TEXT,
        ocupacion TEXT,
        numero_hogares INTEGER,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        FOREIGN KEY (nivel_id) REFERENCES niveles (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE hogares (
        id TEXT PRIMARY KEY,
        local_id TEXT,
        jefe_familia TEXT,
        sexo_jefe TEXT,
        idioma TEXT,
        total_habitantes INTEGER,
        personas_0_5 INTEGER,
        personas_6_11 INTEGER,
        personas_12_17 INTEGER,
        personas_18_23 INTEGER,
        personas_24_34 INTEGER,
        personas_35_44 INTEGER,
        personas_45_59 INTEGER,
        personas_60_69 INTEGER,
        personas_70_79 INTEGER,
        personas_80_mas INTEGER,
        personas_no_edad INTEGER,
        updated_at TEXT,
        sync_dirty INTEGER DEFAULT 1,
        FOREIGN KEY (local_id) REFERENCES locales (id) ON DELETE CASCADE
      )
    ''');
  }

  String _now() => DateTime.now().toIso8601String();

  Future<void> insertEntity(String table, Map<String, dynamic> data) async {
    final db = await database;
    if (!data.containsKey('id') || data['id'] == null) {
      data['id'] = uuid.v4();
    }
    data['updated_at'] = _now();
    data['sync_dirty'] = 1;
    int count = await db.update(table, data, where: 'id = ?', whereArgs: [data['id']]);
    if (count == 0) {
      await db.insert(table, data);
    }
  }

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    final db = await database;
    // Retornar solo registros no eliminados (soft-delete)
    return await db.query(table, where: 'deleted_at IS NULL');
  }

  Future<void> deleteEntity(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-delete: marca deleted_at y sync_dirty=1 en lugar de borrar físicamente.
  /// El registro se sincroniza con el servidor en el próximo batch sync.
  Future<void> softDeleteEntity(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // OPERACIONES ESPECÍFICAS DE ESTRUCTURAS Y JERARQUÍA
  // ─────────────────────────────────────────────────────────────────────────────

  /// Actualiza únicamente los atributos de una estructura en SQLite (nombre, categoría, tipo, estado, niveles_cantidad, notas)
  /// sin tocar ni borrar sus niveles, locales y hogares hijos.
  Future<void> actualizarEstructuraAtributos(PuntoEstructura estructura, {String upmId = 'default_upm'}) async {
    try {
      final db = await database;
      // Asegurar que exista el registro padre en upm
      await db.execute('''
        INSERT OR IGNORE INTO upm (id, nombre, updated_at, sync_dirty, sync_version)
        VALUES (?, 'UPM por defecto', datetime('now'), 0, 0)
      ''', [upmId]);

      final estMap = estructura.toMapDB(upmId);
      int countEst = await db.update('estructuras', estMap, where: 'id = ?', whereArgs: [estructura.id]);
      if (countEst == 0) {
        await db.insert('estructuras', estMap);
      }
      debugPrint('[DatabaseHelper] ✅ Estructura "${estructura.nombre}" (${estructura.id}) actualizada en SQLite con sync_dirty=1');
    } catch (e, stack) {
      debugPrint('[DatabaseHelper] ❌ Error en actualizarEstructuraAtributos: $e\n$stack');
      rethrow;
    }
  }

  /// Guarda una estructura con toda su jerarquía (Niveles, Locales, Hogares)
  Future<void> saveEstructuraCompleta(PuntoEstructura estructura, {String upmId = 'default_upm'}) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        // Asegurar que exista el registro padre en upm
        await txn.execute('''
          INSERT OR IGNORE INTO upm (id, nombre, updated_at, sync_dirty, sync_version)
          VALUES (?, 'UPM por defecto', datetime('now'), 0, 0)
        ''', [upmId]);

        // 1. Guardar estructura (Upsert seguro)
        final estMap = estructura.toMapDB(upmId);
        int countEst = await txn.update('estructuras', estMap, where: 'id = ?', whereArgs: [estructura.id]);
        if (countEst == 0) await txn.insert('estructuras', estMap);

        // 2. Solo limpiar/actualizar niveles si estructura.niveles no está vacío
        if (estructura.niveles.isNotEmpty) {
          final nivelIds = estructura.niveles.map((n) => n.id).toList();
          await txn.delete('niveles', 
              where: 'estructura_id = ? AND id NOT IN (${List.filled(nivelIds.length, '?').join(', ')})', 
              whereArgs: [estructura.id, ...nivelIds]);

          for (var nivel in estructura.niveles) {
            final nivelMap = nivel.toMapDB();
            int countNiv = await txn.update('niveles', nivelMap, where: 'id = ?', whereArgs: [nivel.id]);
            if (countNiv == 0) await txn.insert('niveles', nivelMap);

            if (nivel.locales.isNotEmpty) {
              final localIds = nivel.locales.map((l) => l.id).toList();
              await txn.delete('locales', 
                  where: 'nivel_id = ? AND id NOT IN (${List.filled(localIds.length, '?').join(', ')})', 
                  whereArgs: [nivel.id, ...localIds]);

              for (var local in nivel.locales) {
                final localMap = local.toMapDB();
                int countLoc = await txn.update('locales', localMap, where: 'id = ?', whereArgs: [local.id]);
                if (countLoc == 0) await txn.insert('locales', localMap);

                if (local.hogares.isNotEmpty) {
                  final hogarIds = local.hogares.map((h) => h.id).toList();
                  await txn.delete('hogares', 
                      where: 'local_id = ? AND id NOT IN (${List.filled(hogarIds.length, '?').join(', ')})', 
                      whereArgs: [local.id, ...hogarIds]);

                  for (var hogar in local.hogares) {
                    final hogarMap = hogar.toMapDB();
                    int countHog = await txn.update('hogares', hogarMap, where: 'id = ?', whereArgs: [hogar.id]);
                    if (countHog == 0) await txn.insert('hogares', hogarMap);
                  }
                }
              }
            }
          }
        }
      });
      debugPrint('[DatabaseHelper] ✅ Estructura completa guardada en SQLite: ${estructura.id}');
    } catch (e, stack) {
      debugPrint('[DatabaseHelper] ❌ Error en saveEstructuraCompleta: $e\n$stack');
      rethrow;
    }
  }

  /// Recupera todas las estructuras y reconstruye su jerarquía de objetos
  Future<List<PuntoEstructura>> getEstructuras({String? upmId}) async {
    final db = await database;
    
    // Obtener estructuras
    final estMaps = (upmId != null && upmId != 'default_upm')
        ? await db.query('estructuras', where: 'upm_id = ? AND deleted_at IS NULL', whereArgs: [upmId])
        : await db.query('estructuras', where: 'deleted_at IS NULL');
    if (estMaps.isEmpty) return [];

    final estIds = estMaps.map((e) => e['id'] as String).toList();
    
    // Obtener todos los niveles
    final nivelesMaps = await db.query('niveles', 
      where: 'estructura_id IN (${List.filled(estIds.length, '?').join(', ')})',
      whereArgs: estIds);
    final nivelIds = nivelesMaps.map((n) => n['id'] as String).toList();

    // Obtener todos los locales
    List<Map<String, dynamic>> localesMaps = [];
    if (nivelIds.isNotEmpty) {
      localesMaps = await db.query('locales',
        where: 'nivel_id IN (${List.filled(nivelIds.length, '?').join(', ')})',
        whereArgs: nivelIds);
    }
    final localIds = localesMaps.map((l) => l['id'] as String).toList();

    // Obtener todos los hogares
    List<Map<String, dynamic>> hogaresMaps = [];
    if (localIds.isNotEmpty) {
      hogaresMaps = await db.query('hogares',
        where: 'local_id IN (${List.filled(localIds.length, '?').join(', ')})',
        whereArgs: localIds);
    }

    // Mapear Hogares por Local
    final Map<String, List<Hogar>> hogaresPorLocal = {};
    for (var hMap in hogaresMaps) {
      final hogar = Hogar(
        id: hMap['id'] as String,
        idLocal: hMap['local_id'] as String,
        jefeFamilia: hMap['jefe_familia'] as String? ?? '',
        idSexo: hMap['id_sexo'] != null ? (hMap['id_sexo'] as num).toInt() : null,
        idIdioma: hMap['id_idioma'] != null ? (hMap['id_idioma'] as num).toInt() : null,
        direccion: hMap['direccion'] as String?,
        totalHabitantes: hMap['total_habitantes'] != null ? (hMap['total_habitantes'] as num).toInt() : null,
        personas_0_5: hMap['personas_0_5'] != null ? (hMap['personas_0_5'] as num).toInt() : null,
        personas_6_11: hMap['personas_6_11'] != null ? (hMap['personas_6_11'] as num).toInt() : null,
        personas_12_17: hMap['personas_12_17'] != null ? (hMap['personas_12_17'] as num).toInt() : null,
        personas_18_23: hMap['personas_18_23'] != null ? (hMap['personas_18_23'] as num).toInt() : null,
        personas_24_34: hMap['personas_24_34'] != null ? (hMap['personas_24_34'] as num).toInt() : null,
        personas_35_44: hMap['personas_35_44'] != null ? (hMap['personas_35_44'] as num).toInt() : null,
        personas_45_59: hMap['personas_45_59'] != null ? (hMap['personas_45_59'] as num).toInt() : null,
        personas_60_69: hMap['personas_60_69'] != null ? (hMap['personas_60_69'] as num).toInt() : null,
        personas_70_79: hMap['personas_70_79'] != null ? (hMap['personas_70_79'] as num).toInt() : null,
        personas_80_mas: hMap['personas_80_mas'] != null ? (hMap['personas_80_mas'] as num).toInt() : null,
        personasNoEdad: hMap['personas_no_edad'] != null ? (hMap['personas_no_edad'] as num).toInt() : null,
        updatedAt: DateTime.parse(hMap['updated_at'] as String),
        syncDirty: hMap['sync_dirty'] == 1,
      );
      hogaresPorLocal.putIfAbsent(hogar.idLocal, () => []).add(hogar);
    }
    // Mapear Locales por Nivel
    final Map<String, List<Local>> localesPorNivel = {};
    for (var lMap in localesMaps) {

      final local = Local(
        id: lMap['id'] as String,
        idNivel: lMap['nivel_id'] as String,
        nombre: (lMap['nombre_local'] ?? lMap['nombre']) as String?,
        idTipo: (lMap['id_tipo'] as num?)?.toInt() ?? 1,
        idCondicionLocal: lMap['id_condicion_local'] != null ? (lMap['id_condicion_local'] as num).toInt() : null,
        numeroHogares: lMap['numero_hogares'] != null ? (lMap['numero_hogares'] as num).toInt() : null,
        descripcion: lMap['descripcion'] as String?,
        updatedAt: DateTime.parse(lMap['updated_at'] as String),
        syncDirty: lMap['sync_dirty'] == 1,
        hogares: hogaresPorLocal[lMap['id']] ?? [],
      );
      localesPorNivel.putIfAbsent(local.idNivel, () => []).add(local);
    }

    // Mapear Niveles por Estructura
    final Map<String, List<Nivel>> nivelesPorEstructura = {};
    for (var nMap in nivelesMaps) {
      final nivel = Nivel(
        id: nMap['id'] as String,
        idEstructura: nMap['estructura_id'] as String,
        numeroNivel: (nMap['numero'] as num).toInt(),
        numeroLocales: (nMap['numero_locales'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.parse(nMap['updated_at'] as String),
        syncDirty: nMap['sync_dirty'] == 1,
        locales: localesPorNivel[nMap['id']] ?? [],
      );
      nivelesPorEstructura.putIfAbsent(nivel.idEstructura, () => []).add(nivel);
    }

    // Ensamblar Estructuras
    List<PuntoEstructura> estructuras = [];
    for (var estMap in estMaps) {
      final estructura = PuntoEstructura(
        id: estMap['id'] as String,
        coordenadas: LatLng(
          estMap['y'] as double,
          estMap['x'] as double,
        ),
        nombre: estMap['nombre'] as String? ?? '',
        idCategoria: (estMap['id_categoria'] as num?)?.toInt() ?? 1,
        idTipo: (estMap['id_tipo'] as num?)?.toInt() ?? 1,
        nombreCategoria: estMap['nombre_categoria'] as String?,
        nombreTipo: estMap['nombre_tipo'] as String?,
        estado: EstadoEstructura.values.firstWhere(
          (e) => e.name == estMap['estado'],
          orElse: () => EstadoEstructura.presente,
        ),
        nivelesCantidad: (estMap['niveles_cantidad'] as num?)?.toInt() ?? 1,
        notas: estMap['notas'] as String? ?? '',
        updatedAt: DateTime.parse(estMap['updated_at'] as String),
        syncDirty: estMap['sync_dirty'] == 1,
        createdBy: estMap['created_by'] as String?,
        updatedBy: estMap['updated_by'] as String?,
        deviceId: estMap['device_id'] as String?,
        syncVersion: (estMap['sync_version'] as num?)?.toInt() ?? 0,
        deletedAt: estMap['deleted_at'] != null ? DateTime.parse(estMap['deleted_at'] as String) : null,
        niveles: nivelesPorEstructura[estMap['id']] ?? [],
      );
      estructuras.add(estructura);
    }
    return estructuras;
  }

  /// Reemplaza completamente los registros locales de SQLite con los descargados desde el servidor Postgres
  Future<void> reemplazarTodoDesdeServidor({
    required List<PuntoEstructura> estructuras,
    required List<LineaCamino> caminos,
    required List<PoligonoUPM> upms,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Limpiar tablas locales
      await txn.delete('hogares');
      await txn.delete('locales');
      await txn.delete('niveles');
      await txn.delete('estructuras');
      await txn.delete('caminos');
      await txn.delete('upm');

      // 2. Insertar UPMs
      for (var u in upms) {
        final map = u.toMapDB();
        map['sync_dirty'] = 0;
        await txn.insert('upm', map);
      }

      // Asegurar default_upm si no existe
      await txn.execute('''
        INSERT OR IGNORE INTO upm (id, nombre, updated_at, sync_dirty, sync_version)
        VALUES ('default_upm', 'UPM por defecto', datetime('now'), 0, 0)
      ''');

      // 3. Insertar Caminos
      for (var c in caminos) {
        final map = c.toMapDB();
        map['sync_dirty'] = 0;
        await txn.insert('caminos', map);
      }

      // 4. Insertar Estructuras y su jerarquía
      for (var est in estructuras) {
        final estMap = est.toMapDB('default_upm');
        estMap['sync_dirty'] = 0;
        await txn.insert('estructuras', estMap);

        for (var nivel in est.niveles) {
          final nMap = nivel.toMapDB();
          nMap['sync_dirty'] = 0;
          await txn.insert('niveles', nMap);

          for (var local in nivel.locales) {
            final lMap = local.toMapDB();
            lMap['sync_dirty'] = 0;
            await txn.insert('locales', lMap);

            for (var hogar in local.hogares) {
              final hMap = hogar.toMapDB();
              hMap['sync_dirty'] = 0;
              await txn.insert('hogares', hMap);
            }
          }
        }
      }
    });
  }
}
