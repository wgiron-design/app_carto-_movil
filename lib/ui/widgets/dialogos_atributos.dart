import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/models/capa_geometrica.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/colores_categoria.dart';


// ─────────────────────────────────────────────────────────────────────────────
// TIPOS DE RETORNO (DART 3 RECORDS)
// ─────────────────────────────────────────────────────────────────────────────

typedef AtributosPuntoResult = ({
  String nombre,
  int idCategoria,
  int idTipo,
  int? idEstructuraUser,
  EstadoEstructura estado,
  int nivelesCantidad,
  String notas,
});

const List<CatalogoItem> kTiposEstructuraDefault = [
  CatalogoItem(id: 1, nombre: 'Formal', descripcion: 'Estructura formal / edificación'),
  CatalogoItem(id: 2, nombre: 'Referencia Geográfica', descripcion: 'Punto de referencia geográfico'),
];

const Map<int, List<CatalogoItem>> kCategoriasEstructuraDefault = {
  1: [
    CatalogoItem(id: 1, nombre: 'Vivienda', idCategoria: 1),
    CatalogoItem(id: 2, nombre: 'Vivienda Multifamiliar', idCategoria: 1),
    CatalogoItem(id: 3, nombre: 'Vivienda y Comercio', idCategoria: 1),
    CatalogoItem(id: 4, nombre: 'Comercio o Servicio', idCategoria: 1),
    CatalogoItem(id: 5, nombre: 'Vivienda Multifamiliar y Comercio', idCategoria: 1),
    CatalogoItem(id: 6, nombre: 'Vivienda en Construcción', idCategoria: 1),
    CatalogoItem(id: 7, nombre: 'Colegios Privados', idCategoria: 1),
    CatalogoItem(id: 8, nombre: 'Institutos', idCategoria: 1),
    CatalogoItem(id: 9, nombre: 'Escuelas Oficiales', idCategoria: 1),
    CatalogoItem(id: 10, nombre: 'Iglesia Católica', idCategoria: 1),
    CatalogoItem(id: 11, nombre: 'Iglesia Evangélica', idCategoria: 1),
    CatalogoItem(id: 12, nombre: 'Iglesia Adventista', idCategoria: 1),
    CatalogoItem(id: 13, nombre: 'Iglesia Mormona', idCategoria: 1),
    CatalogoItem(id: 14, nombre: 'Iglesia Testigos de Jehová', idCategoria: 1),
    CatalogoItem(id: 15, nombre: 'Institución Gubernamental', idCategoria: 1),
    CatalogoItem(id: 16, nombre: 'Instituciones de Salud Pública (Nacional)', idCategoria: 1),
    CatalogoItem(id: 17, nombre: 'Biblioteca', idCategoria: 1),
    CatalogoItem(id: 18, nombre: 'Gasolinera', idCategoria: 1),
    CatalogoItem(id: 19, nombre: 'Industrias o Fábricas', idCategoria: 1),
    CatalogoItem(id: 20, nombre: 'Teatros o Cines', idCategoria: 1),
    CatalogoItem(id: 21, nombre: 'Bancos', idCategoria: 1),
    CatalogoItem(id: 22, nombre: 'Edificio de Apartamentos', idCategoria: 1),
    CatalogoItem(id: 23, nombre: 'Edificio Comercial', idCategoria: 1),
    CatalogoItem(id: 24, nombre: 'Edificio de Apartamentos y Comercio', idCategoria: 1),
    CatalogoItem(id: 25, nombre: 'Hotel o Pensión', idCategoria: 1),
    CatalogoItem(id: 26, nombre: 'Aeropuerto', idCategoria: 1),
    CatalogoItem(id: 27, nombre: 'Centros Comerciales', idCategoria: 1),
    CatalogoItem(id: 28, nombre: 'Mercados Municipales', idCategoria: 1),
    CatalogoItem(id: 29, nombre: 'Museos o Sitios Arqueológicos', idCategoria: 1),
    CatalogoItem(id: 30, nombre: 'Salón de Usos Múltiples', idCategoria: 1),
    CatalogoItem(id: 31, nombre: 'Universidad', idCategoria: 1),
    CatalogoItem(id: 32, nombre: 'Bodega', idCategoria: 1),
    CatalogoItem(id: 33, nombre: 'Bomberos', idCategoria: 1),
    CatalogoItem(id: 34, nombre: 'Municipalidad o Ayuntamiento', idCategoria: 1),
    CatalogoItem(id: 35, nombre: 'Reserva, Brigada o Complejo Militar', idCategoria: 1),
    CatalogoItem(id: 36, nombre: 'Policía Nacional Civil', idCategoria: 1),
    CatalogoItem(id: 37, nombre: 'Instalaciones de Salud Privada', idCategoria: 1),
    CatalogoItem(id: 38, nombre: 'Estadio', idCategoria: 1),
    CatalogoItem(id: 39, nombre: 'Asociaciones Benéficas', idCategoria: 1),
    CatalogoItem(id: 40, nombre: 'ONGs', idCategoria: 1),
    CatalogoItem(id: 41, nombre: 'Coliseos', idCategoria: 1),
    CatalogoItem(id: 42, nombre: 'Planta de Tratamiento de Agua', idCategoria: 1),
  ],
  2: [
    CatalogoItem(id: 43, nombre: 'PARQUEO', idCategoria: 2),
    CatalogoItem(id: 44, nombre: 'ANTENA TELEFONICA O RADIAL', idCategoria: 2),
    CatalogoItem(id: 45, nombre: 'PARQUE', idCategoria: 2),
    CatalogoItem(id: 46, nombre: 'PLAZA O CENTRO RECREATIVO', idCategoria: 2),
    CatalogoItem(id: 47, nombre: 'PUENTE VEHICULAR', idCategoria: 2),
    CatalogoItem(id: 48, nombre: 'POZO O TANQUE', idCategoria: 2),
    CatalogoItem(id: 49, nombre: 'GRIFO', idCategoria: 2),
    CatalogoItem(id: 50, nombre: 'CEMENTERIO', idCategoria: 2),
    CatalogoItem(id: 51, nombre: 'PILA MUNICIPAL', idCategoria: 2),
    CatalogoItem(id: 52, nombre: 'CAMPOS DE DEPORTES', idCategoria: 2),
    CatalogoItem(id: 53, nombre: 'ANTENA ELECTRICA', idCategoria: 2),
    CatalogoItem(id: 54, nombre: 'PUENTE PEATONAL', idCategoria: 2),
    CatalogoItem(id: 55, nombre: 'ALTARES MAYAS', idCategoria: 2),
    CatalogoItem(id: 56, nombre: 'GARITA DE SEGURIDAD', idCategoria: 2),
    CatalogoItem(id: 57, nombre: 'VERTEDERO MUNICIPAL', idCategoria: 2),
    CatalogoItem(id: 58, nombre: 'MUELLE O PUERTO', idCategoria: 2),
    CatalogoItem(id: 59, nombre: 'TERMINAL DE BUSES', idCategoria: 2),
  ],
};

typedef AtributosLineaResult = ({
  String nombre,
  TipoCamino tipo,
  String notas,
});

typedef AtributosPoligonoResult = ({
  String nombre,
  String codigoUPM,
  String notas,
});

// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGO DE ATRIBUTOS — PUNTO / ESTRUCTURA
// ─────────────────────────────────────────────────────────────────────────────

/// Formulario de atributos para un nuevo punto (Estructura) o para editar uno existente.
class DialogoAtributosPunto extends StatefulWidget {
  final double lat;
  final double lng;

  /// Lista de tipos disponibles (Formal, Referencia…). Se pasa desde el padre
  /// para evitar una llamada de red extra al abrir el diálogo.
  final List<CatalogoItem> tipos;

  // Parámetros opcionales para modo edición / consulta
  final String? nombreInicial;
  final int? idEstructuraUserInicial;
  final int? idCategoriaInicial;
  final int? idTipoInicial;
  final EstadoEstructura? estadoInicial;
  final int? nivelesInicial;
  final String? notasIniciales;
  final bool soloLectura;
  final VoidCallback? onAbrirNiveles;

  /// URL base del backend (ej. 'http://10.0.2.2:8000'). Se pasa desde map_screen.
  final String baseUrl;

  const DialogoAtributosPunto({
    super.key,
    required this.lat,
    required this.lng,
    required this.baseUrl,
    this.tipos = const [],
    this.nombreInicial,
    this.idEstructuraUserInicial,
    this.idCategoriaInicial,
    this.idTipoInicial,
    this.estadoInicial,
    this.nivelesInicial,
    this.notasIniciales,
    this.soloLectura = false,
    this.onAbrirNiveles,
  });

  bool get esModoEdicion => nombreInicial != null;

  @override
  State<DialogoAtributosPunto> createState() => _DialogoAtributosPuntoState();
}

class _DialogoAtributosPuntoState extends State<DialogoAtributosPunto> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _idUserCtrl;
  late final TextEditingController _notasCtrl;

  late int _idTipo;
  late int _idCategoria;
  List<CatalogoItem> _categoriasFiltradas = [];
  bool _cargandoCategorias = false;

  late EstadoEstructura _estado;
  late int _niveles;

  List<CatalogoItem> get _listaTipos =>
      widget.tipos.isNotEmpty ? widget.tipos : kTiposEstructuraDefault;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreInicial ?? '');
    _idUserCtrl = TextEditingController(text: widget.idEstructuraUserInicial?.toString() ?? '');
    _notasCtrl  = TextEditingController(text: widget.notasIniciales ?? '');
    _estado  = widget.estadoInicial ?? EstadoEstructura.presente;
    _niveles = widget.nivelesInicial ?? 1;

    _idTipo = widget.idTipoInicial ?? _listaTipos.first.id;
    _idCategoria = widget.idCategoriaInicial ?? 1;
    _categoriasFiltradas = List<CatalogoItem>.from(
        kCategoriasEstructuraDefault[_idTipo] ?? kCategoriasEstructuraDefault[1]!);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarCategorias(_idTipo, preseleccionarId: _idCategoria);
    });
  }

  /// Llama a GET /api/capas/catalogos/estructuras/categorias?tipo={tipo}
  /// y actualiza el estado del combo de categoría.
  Future<void> _cargarCategorias(int tipo, {int? preseleccionarId}) async {
    setState(() {
      _cargandoCategorias = true;
      _categoriasFiltradas = List<CatalogoItem>.from(
          kCategoriasEstructuraDefault[tipo] ?? kCategoriasEstructuraDefault[1]!);
      if (preseleccionarId != null &&
          _categoriasFiltradas.any((c) => c.id == preseleccionarId)) {
        _idCategoria = preseleccionarId;
      } else if (!_categoriasFiltradas.any((c) => c.id == _idCategoria)) {
        _idCategoria = _categoriasFiltradas.first.id;
      }
    });

    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/capas/catalogos/estructuras/categorias?tipo=$tipo',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 3));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final lista = (jsonDecode(resp.body) as List)
            .map((e) => CatalogoItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (lista.isNotEmpty) {
          setState(() {
            _categoriasFiltradas = lista;
            _cargandoCategorias  = false;
            if (preseleccionarId != null &&
                lista.any((c) => c.id == preseleccionarId)) {
              _idCategoria = preseleccionarId;
            } else if (!lista.any((c) => c.id == _idCategoria)) {
              _idCategoria = lista.first.id;
            }
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _cargandoCategorias = false;
      });
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _idUserCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esModoEdicion = widget.esModoEdicion;
    final soloLectura   = widget.soloLectura;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(
              icon: soloLectura
                  ? Icons.info_outline
                  : (esModoEdicion ? Icons.edit_location_alt : Icons.place),
              titulo: soloLectura
                  ? 'Atributos de Estructura'
                  : (esModoEdicion ? 'Editar Estructura' : 'Nueva Estructura'),
              subtitulo:
                  'Lat: ${widget.lat.toStringAsFixed(6)}  '
                  'Lng: ${widget.lng.toStringAsFixed(6)}',
              color: soloLectura
                  ? const Color(0xFF4FC3F7)
                  : (esModoEdicion ? const Color(0xFFFFB74D) : const Color(0xFF4FC3F7)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Nombre ───────────────────────────────────────────────
                    TextFormField(
                      controller: _nombreCtrl,
                      autofocus: !soloLectura,
                      readOnly: soloLectura,
                      decoration: const InputDecoration(
                        labelText: 'Nombre / Identificador *',
                        hintText: 'ej. Casa 001, Comercio Norte...',
                        prefixIcon: Icon(Icons.label_outline, size: 18),
                      ),
                      validator: (v) =>
                          (!soloLectura && (v == null || v.trim().isEmpty))
                              ? 'Requerido'
                              : null,
                    ),

                    const SizedBox(height: 14),

                    // ── ID de Estructura (id_estructura_user para etiqueta) ──
                    TextFormField(
                      controller: _idUserCtrl,
                      readOnly: soloLectura,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ID Estructura (Etiqueta en mapa)',
                        hintText: 'ej. 1, 42, 105...',
                        prefixIcon: Icon(Icons.tag, size: 18),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Tipo (combo 1 — controla la carga del combo 2) ───────
                    Text('Tipo de Estructura *',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _listaTipos.any((t) => t.id == _idTipo)
                          ? _idTipo
                          : _listaTipos.first.id,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.home_work_outlined, size: 18),
                      ),
                      hint: const Text('Selecciona un tipo'),
                      items: _listaTipos.map((t) {
                        return DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(t.nombre,
                              style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: soloLectura
                          ? null
                          : (v) {
                              if (v == null || v == _idTipo) return;
                              setState(() => _idTipo = v);
                              // Repoblar categorías al cambiar tipo; resetear selección
                              _cargarCategorias(v);
                            },
                      validator: (v) => (!soloLectura && v == null)
                          ? 'Seleccione un tipo'
                          : null,
                    ),

                    const SizedBox(height: 14),

                    // ── Categoría (combo 2 — dependiente del tipo) ────────────
                    Text('Categoría de Estructura *',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _buildComboCategorias(soloLectura),

                    const SizedBox(height: 14),

                    // ── Estado y Niveles ─────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estado',
                                  style:
                                      Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<EstadoEstructura>(
                                value: _estado,
                                items: EstadoEstructura.values.map((e) {
                                  return DropdownMenuItem(
                                      value: e,
                                      child: Text(e.label,
                                          style: const TextStyle(
                                              fontSize: 13)));
                                }).toList(),
                                onChanged: soloLectura
                                    ? null
                                    : (v) => setState(() => _estado = v!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Niveles (1-10)',
                                  style:
                                      Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<int>(
                                value: _niveles,
                                items:
                                    List.generate(10, (i) => i + 1).map((n) {
                                  return DropdownMenuItem(
                                      value: n,
                                      child: Text('$n',
                                          style: const TextStyle(
                                              fontSize: 13)));
                                }).toList(),
                                onChanged: soloLectura
                                    ? null
                                    : (v) => setState(() => _niveles = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Notas ─────────────────────────────────────────────────
                    TextFormField(
                      controller: _notasCtrl,
                      maxLines: 2,
                      readOnly: soloLectura,
                      decoration: const InputDecoration(
                        labelText: 'Notas (opcional)',
                        prefixIcon: Icon(Icons.notes, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(
              onCancelar: () => Navigator.pop(context, null),
              onConfirmar: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context, (
                  nombre: _nombreCtrl.text.trim(),
                  idCategoria: _idCategoria,
                  idTipo: _idTipo,
                  idEstructuraUser: int.tryParse(_idUserCtrl.text.trim()),
                  estado: _estado,
                  nivelesCantidad: _niveles,
                  notas: _notasCtrl.text.trim(),
                ) as AtributosPuntoResult);
              },
              labelConfirmar: esModoEdicion ? 'Guardar Cambios' : 'Ingresar información',
              soloLectura: soloLectura,
              onAbrirNiveles: widget.onAbrirNiveles,
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el dropdown de categorías
  Widget _buildComboCategorias(bool soloLectura) {
    return DropdownButtonFormField<int>(
      value: _categoriasFiltradas.any((c) => c.id == _idCategoria)
          ? _idCategoria
          : (_categoriasFiltradas.isNotEmpty ? _categoriasFiltradas.first.id : null),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.category_outlined, size: 18),
        suffixIcon: _cargandoCategorias
            ? const SizedBox(
                width: 16,
                height: 16,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: const Text('Selecciona una categoría'),
      isExpanded: true,
      items: _categoriasFiltradas.map((c) {
        final color = getColorPorCategoriaEstructura(c.id);
        return DropdownMenuItem<int>(
          value: c.id,
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1),
                ),
              ),
              Expanded(
                child: Text(
                  c.nombre,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: soloLectura ? null : (v) {
        if (v != null) setState(() => _idCategoria = v);
      },
      validator: (v) => (!soloLectura && v == null)
          ? 'Seleccione una categoría'
          : null,
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGO DE ATRIBUTOS — LÍNEA / CAMINO
// ─────────────────────────────────────────────────────────────────────────────

class DialogoAtributosLinea extends StatefulWidget {
  final int numVertices;
  final double longitudM;
  final String? nombreInicial;
  final TipoCamino? tipoInicial;
  final bool soloLectura;

  const DialogoAtributosLinea({
    super.key,
    required this.numVertices,
    required this.longitudM,
    this.nombreInicial,
    this.tipoInicial,
    this.soloLectura = false,
  });

  bool get esModoEdicion => nombreInicial != null;

  @override
  State<DialogoAtributosLinea> createState() => _DialogoAtributosLineaState();
}

class _DialogoAtributosLineaState extends State<DialogoAtributosLinea> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descripcionCtrl;
  TipoCamino? _tipo;

  @override
  void initState() {
    super.initState();
    _descripcionCtrl = TextEditingController(text: widget.nombreInicial);
    _tipo = widget.tipoInicial;
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final soloLectura = widget.soloLectura;
    final esModoEdicion = widget.esModoEdicion;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(
              icon: soloLectura ? Icons.info_outline : Icons.polyline,
              titulo: soloLectura 
                  ? 'Atributos de Línea / Camino' 
                  : (esModoEdicion ? 'Editar Línea / Camino' : 'Nueva Línea / Camino'),
              subtitulo:
                  '${widget.numVertices} vértices · '
                  '${(widget.longitudM / 1000).toStringAsFixed(3)} km',
              color: const Color(0xFFFFB74D),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Dirección / Descripción (multilínea) ──
                    TextFormField(
                      controller: _descripcionCtrl,
                      autofocus: !soloLectura,
                      readOnly: soloLectura,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Dirección / Descripción',
                        hintText: 'ej. Camino principal hacia la escuela,\nAcceso norte, Entrada al caserío...',
                        prefixIcon: Icon(Icons.description_outlined, size: 18),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Tipo de Camino (ComboBox obligatorio) ──
                    DropdownButtonFormField<TipoCamino>(
                      value: _tipo,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Camino *',
                        prefixIcon: Icon(Icons.route_outlined, size: 18),
                      ),
                      items: TipoCamino.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text('${t.simbolo}  ${t.label}'),
                        );
                      }).toList(),
                      onChanged: soloLectura ? null : (v) => setState(() => _tipo = v),
                      validator: (v) =>
                          (!soloLectura && v == null) ? 'Seleccione un tipo de camino' : null,
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(
              onCancelar: () => Navigator.pop(context, null),
              onConfirmar: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context, (
                  nombre: _descripcionCtrl.text.trim(),
                  tipo: _tipo!,
                  notas: '',
                ) as AtributosLineaResult);
              },
              labelConfirmar: esModoEdicion ? 'Guardar Cambios' : 'Guardar Línea',
              soloLectura: soloLectura,
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGO DE ATRIBUTOS — POLÍGONO / UPM
// ─────────────────────────────────────────────────────────────────────────────

class DialogoAtributosPoligono extends StatefulWidget {
  final int numVertices;
  final double areaMCuad;
  final String? nombreInicial;
  final String? codigoUPMInicial;
  final bool soloLectura;

  const DialogoAtributosPoligono({
    super.key,
    required this.numVertices,
    required this.areaMCuad,
    this.nombreInicial,
    this.codigoUPMInicial,
    this.soloLectura = false,
  });

  bool get esModoEdicion => nombreInicial != null;

  @override
  State<DialogoAtributosPoligono> createState() =>
      _DialogoAtributosPoligonoState();
}

class _DialogoAtributosPoligonoState extends State<DialogoAtributosPoligono> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _codigoCtrl;
  final _notasCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreInicial ?? '');
    _codigoCtrl = TextEditingController(text: widget.codigoUPMInicial ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areaHa = widget.areaMCuad / 10000;
    final soloLectura = widget.soloLectura;
    final esModoEdicion = widget.esModoEdicion;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(
              icon: soloLectura ? Icons.info_outline : Icons.pentagon,
              titulo: soloLectura 
                  ? 'Atributos de UPM' 
                  : (esModoEdicion ? 'Editar UPM' : 'Nueva UPM'),
              subtitulo:
                  '${widget.numVertices} vértices · '
                  '${areaHa.toStringAsFixed(4)} ha',
              color: const Color(0xFFA5D6A7),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      autofocus: !soloLectura,
                      readOnly: soloLectura,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la UPM *',
                        hintText: 'ej. UPM-001, Sector Norte...',
                        prefixIcon: Icon(Icons.label_outline, size: 18),
                      ),
                      validator: (v) =>
                          (!soloLectura && (v == null || v.trim().isEmpty)) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _codigoCtrl,
                      readOnly: soloLectura,
                      decoration: const InputDecoration(
                        labelText: 'Código UPM (opcional)',
                        hintText: 'ej. 01-02-003',
                        prefixIcon: Icon(Icons.qr_code, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _notasCtrl,
                      maxLines: 2,
                      readOnly: soloLectura,
                      decoration: const InputDecoration(
                        labelText: 'Notas (opcional)',
                        prefixIcon: Icon(Icons.notes, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(
              onCancelar: () => Navigator.pop(context, null),
              onConfirmar: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context, (
                  nombre: _nombreCtrl.text.trim(),
                  codigoUPM: _codigoCtrl.text.trim(),
                  notas: _notasCtrl.text.trim(),
                ) as AtributosPoligonoResult);
              },
              labelConfirmar: esModoEdicion ? 'Guardar Cambios' : 'Guardar UPM',
              soloLectura: soloLectura,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS COMPARTIDOS ENTRE DIÁLOGOS
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildHeader({
  required IconData icon,
  required String titulo,
  required String subtitulo,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceVariant,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(bottom: BorderSide(color: color.withOpacity(0.3), width: 1)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitulo,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildFooter({
  required VoidCallback onCancelar,
  required VoidCallback onConfirmar,
  required String labelConfirmar,
  bool soloLectura = false,
  VoidCallback? onAbrirNiveles,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
    decoration: const BoxDecoration(
      color: AppTheme.surfaceVariant,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onAbrirNiveles != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: const Text('Gestionar Niveles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.white,
              ),
              onPressed: onAbrirNiveles,
            ),
          ),
          const SizedBox(height: 10),
        ],
        soloLectura
            ? SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onCancelar,
                  child: const Text('Cerrar'),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancelar,
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onConfirmar,
                      child: Text(labelConfirmar),
                    ),
                  ),
                ],
              ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────


class _ChipSelector extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final Color color;
  final VoidCallback onTap;

  const _ChipSelector({
    required this.label,
    required this.seleccionado,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: seleccionado ? color.withOpacity(0.15) : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: seleccionado ? color : const Color(0xFF2D4054),
            width: seleccionado ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: seleccionado ? color : AppTheme.onSurface.withOpacity(0.7),
            fontSize: 12,
            fontWeight:
                seleccionado ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
