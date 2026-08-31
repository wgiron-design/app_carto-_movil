import 'package:flutter/material.dart';

/// Paleta curada de colores para las categorías de estructuras (`estructuras.id_categoria`).
/// 
/// Regla estricta: NO se utiliza ningún matiz de ROJO (reservado para ausente / alertas)
/// ni de AMARILLO (reservado para selección).
/// Todos los colores son de las gamas Azul, Verde, Cian, Turquesa, Añil, Violeta, Púrpura,
/// Magenta frío y Gris azulado / Pizarra.

const Map<int, Color> kColoresPorCategoria = {
  // ── Tipo 1: Estructuras Formales (IDs 1 al 42) ─────────────────────────────
  1: Color(0xFF0288D1),  // Vivienda: Azul cielo intenso
  2: Color(0xFF00897B),  // Vivienda Multifamiliar: Verde azulado / Teal
  3: Color(0xFF7B1FA2),  // Vivienda y Comercio: Púrpura profundo
  4: Color(0xFF00ACC1),  // Comercio o Servicio: Cian vibrante
  5: Color(0xFF3949AB),  // Vivienda Multifamiliar y Comercio: Añil / Indigo
  6: Color(0xFF607D8B),  // Vivienda en Construcción: Gris azulado / Slate
  7: Color(0xFF2E7D32),  // Colegios Privados: Verde bosque
  8: Color(0xFF0097A7),  // Institutos: Azul cian oscuro
  9: Color(0xFF43A047),  // Escuelas Oficiales: Verde medio
  10: Color(0xFF512DA8), // Iglesia Católica: Violeta oscuro
  11: Color(0xFF8E24AA), // Iglesia Evangélica: Púrpura brillante
  12: Color(0xFF9C27B0), // Iglesia Adventista: Magenta / Púrpura
  13: Color(0xFF303F9F), // Iglesia Mormona: Añil oscuro
  14: Color(0xFF6A1B9A), // Iglesia Testigos de Jehová: Púrpura ciruela
  15: Color(0xFF1976D2), // Institución Gubernamental: Azul real
  16: Color(0xFF00796B), // Instituciones de Salud Pública: Verde esmeralda oscuro
  17: Color(0xFF5C6BC0), // Biblioteca: Azul índigo suave
  18: Color(0xFF0277BD), // Gasolinera: Azul océano
  19: Color(0xFF455A64), // Industrias o Fábricas: Pizarra oscuro
  20: Color(0xFF4A148C), // Teatros o Cines: Violeta real
  21: Color(0xFF00838F), // Bancos: Cian petróleo
  22: Color(0xFF1565C0), // Edificio de Apartamentos: Azul zafiro
  23: Color(0xFF00695C), // Edificio Comercial: Verde azulado profundo
  24: Color(0xFF651FFF), // Edificio de Apartamentos y Comercio: Violeta eléctrico
  25: Color(0xFF26A69A), // Hotel o Pensión: Menta turquesa
  26: Color(0xFF29B6F6), // Aeropuerto: Celeste luminoso
  27: Color(0xFF7E57C2), // Centros Comerciales: Lavanda oscuro
  28: Color(0xFF1B5E20), // Mercados Municipales: Verde pino oscuro
  29: Color(0xFF78909C), // Museos o Sitios Arqueológicos: Piedra pizarra
  30: Color(0xFF5E35B1), // Salón de Usos Múltiples: Púrpura medio
  31: Color(0xFF283593), // Universidad: Azul marino profundo
  32: Color(0xFF37474F), // Bodega: Acero carbón
  33: Color(0xFF311B92), // Bomberos: Púrpura medianoche (sin rojo)
  34: Color(0xFF0D47A1), // Municipalidad o Ayuntamiento: Azul cobalto
  35: Color(0xFF33691E), // Complejo Militar: Verde oliva frío
  36: Color(0xFF1A237E), // Policía Nacional Civil: Azul noche
  37: Color(0xFF00BFA5), // Salud Privada: Verde agua brillante
  38: Color(0xFF388E3C), // Estadio: Verde pasto
  39: Color(0xFF26C6DA), // Asociaciones Benéficas: Cian claro
  40: Color(0xFF42A5F5), // ONGs: Azul claro luminoso
  41: Color(0xFF7B1FA2), // Coliseos: Púrpura imperial
  42: Color(0xFF00E5FF), // Planta de Tratamiento de Agua: Aguamarina brillante

  // ── Tipo 2: Referencias Geográficas (IDs 43 al 59) ─────────────────────────
  43: Color(0xFF546E7A), // PARQUEO: Gris azulado neutro
  44: Color(0xFF7C4DFF), // ANTENA TELEFÓNICA O RADIAL: Púrpura neón
  45: Color(0xFF00C853), // PARQUE: Verde esmeralda vivo
  46: Color(0xFF00E676), // PLAZA O CENTRO RECREATIVO: Verde menta vivo
  47: Color(0xFF90A4AE), // PUENTE VEHICULAR: Plata pizarra
  48: Color(0xFF00B0FF), // POZO O TANQUE: Azul cian agua
  49: Color(0xFF40C4FF), // GRIFO: Celeste agua
  50: Color(0xFF263238), // CEMENTERIO: Pizarra muy oscuro
  51: Color(0xFF18FFFF), // PILA MUNICIPAL: Cian turquesa eléctrico
  52: Color(0xFF66BB6A), // CAMPOS DE DEPORTES: Verde campo
  53: Color(0xFF2979FF), // ANTENA ELÉCTRICA: Azul eléctrico
  54: Color(0xFFB0BEC5), // PUENTE PEATONAL: Acero claro
  55: Color(0xFF8E24AA), // ALTARES MAYAS: Púrpura místico
  56: Color(0xFF1E88E5), // GARITA DE SEGURIDAD: Azul institucional
  57: Color(0xFF004D40), // VERTEDERO MUNICIPAL: Verde azul petróleo
  58: Color(0xFF0288D1), // MUELLE O PUERTO: Azul ultramar
  59: Color(0xFF1565C0), // TERMINAL DE BUSES: Azul transporte
};

/// Paleta circular de respaldo para cualquier ID de categoría no mapeado explícitamente.
/// Garantiza 0% rojo y 0% amarillo.
const List<Color> kPaletaColoresCategorias = [
  Color(0xFF0288D1),
  Color(0xFF00897B),
  Color(0xFF7B1FA2),
  Color(0xFF00ACC1),
  Color(0xFF3949AB),
  Color(0xFF43A047),
  Color(0xFF512DA8),
  Color(0xFF0097A7),
  Color(0xFF1976D2),
  Color(0xFF2E7D32),
  Color(0xFF8E24AA),
  Color(0xFF00BFA5),
  Color(0xFF5C6BC0),
  Color(0xFF26A69A),
  Color(0xFF1565C0),
  Color(0xFF651FFF),
  Color(0xFF00E676),
  Color(0xFF42A5F5),
  Color(0xFF7E57C2),
  Color(0xFF00E5FF),
  Color(0xFF388E3C),
  Color(0xFF2979FF),
  Color(0xFF607D8B),
  Color(0xFF26C6DA),
];

/// Nombres descriptivos de las categorías estándar
const Map<int, String> kNombreCategoriasDefault = {
  1: 'Vivienda',
  2: 'Vivienda Multifamiliar',
  3: 'Vivienda y Comercio',
  4: 'Comercio o Servicio',
  5: 'Vivienda Multifamiliar y Comercio',
  6: 'Vivienda en Construcción',
  7: 'Colegios Privados',
  8: 'Institutos',
  9: 'Escuelas Oficiales',
  10: 'Iglesia Católica',
  11: 'Iglesia Evangélica',
  12: 'Iglesia Adventista',
  13: 'Iglesia Mormona',
  14: 'Iglesia Testigos de Jehová',
  15: 'Institución Gubernamental',
  16: 'Instituciones de Salud Pública',
  17: 'Biblioteca',
  18: 'Gasolinera',
  19: 'Industrias o Fábricas',
  20: 'Teatros o Cines',
  21: 'Bancos',
  22: 'Edificio de Apartamentos',
  23: 'Edificio Comercial',
  24: 'Edificio Apartamentos y Comercio',
  25: 'Hotel o Pensión',
  26: 'Aeropuerto',
  27: 'Centros Comerciales',
  28: 'Mercados Municipales',
  29: 'Museos o Sitios Arqueológicos',
  30: 'Salón de Usos Múltiples',
  31: 'Universidad',
  32: 'Bodega',
  33: 'Bomberos',
  34: 'Municipalidad o Ayuntamiento',
  35: 'Reserva, Brigada o Militar',
  36: 'Policía Nacional Civil',
  37: 'Salud Privada',
  38: 'Estadio',
  39: 'Asociaciones Benéficas',
  40: 'ONGs',
  41: 'Coliseos',
  42: 'Planta Tratamiento de Agua',
  43: 'Parqueo',
  44: 'Antena Telefónica / Radial',
  45: 'Parque',
  46: 'Plaza o Centro Recreativo',
  47: 'Puente Vehicular',
  48: 'Pozo o Tanque',
  49: 'Grifo',
  50: 'Cementerio',
  51: 'Pila Municipal',
  52: 'Campos de Deportes',
  53: 'Antena Eléctrica',
  54: 'Puente Peatonal',
  55: 'Altares Mayas',
  56: 'Garita de Seguridad',
  57: 'Vertedero Municipal',
  58: 'Muelle o Puerto',
  59: 'Terminal de Buses',
};

/// Obtiene el color correspondiente a un `id_categoria` de estructura.
/// 
/// Garantiza que el color resultante no sea ni rojo ni amarillo.
Color getColorPorCategoriaEstructura(int idCategoria) {
  final color = kColoresPorCategoria[idCategoria];
  if (color != null) return color;
  final idx = idCategoria.abs() % kPaletaColoresCategorias.length;
  return kPaletaColoresCategorias[idx];
}

/// Obtiene el nombre legible de la categoría según su ID.
String getNombreCategoriaEstructura(int idCategoria, {String? nombreFallback}) {
  if (nombreFallback != null && nombreFallback.trim().isNotEmpty) {
    return nombreFallback;
  }
  return kNombreCategoriasDefault[idCategoria] ?? 'Categoría #$idCategoria';
}
