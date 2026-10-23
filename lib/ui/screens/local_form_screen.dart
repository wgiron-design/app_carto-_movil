import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/models/capa_geometrica.dart';
import '../../core/services/local_service.dart';
import '../../core/services/jerarquia_navigator_service.dart';
import '../widgets/breadcrumb_bar.dart';
import 'hogar_lista_screen.dart';

class LocalFormScreen extends StatefulWidget {
  final String nivelId;
  final int numeroNivel;
  final int numeroLocalActual;
  final int totalLocalesEsperados;
  final LocalResumen? localExistente;

  const LocalFormScreen({
    super.key,
    required this.nivelId,
    required this.numeroNivel,
    required this.numeroLocalActual,
    required this.totalLocalesEsperados,
    this.localExistente,
  });

  @override
  State<LocalFormScreen> createState() => _LocalFormScreenState();
}

class _LocalFormScreenState extends State<LocalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _localService = LocalService();

  late TextEditingController _nombreCtrl;
  late TextEditingController _descripcionCtrl;
  int _numeroHogares = 1;

  List<CatalogoItem> _tiposLocales = [];
  List<CatalogoItem> _condicionesLocales = [];

  int? _idTipo;
  int? _idCondicionLocal;

  bool _isLoadingCatalogos = true;
  bool _isSaving = false;
  String? _errorMsg;

  bool get _esEdicion => widget.localExistente != null;

  // Tipos habitacionales que requieren condición y número de hogares
  // 1: LOCAL SOLO DE HABITACION, 2: LOCAL DE HABITACION Y COMERCIO
  bool get _esHabitacional => _idTipo == 1 || _idTipo == 2;

  // Condiciones que implican habitantes presentes/ausentes
  // 1: OCUPADO CON PERSONAS PRESENTES, 2: OCUPADO CON PERSONAS AUSENTES
  bool get _requiereHogares => _esHabitacional && (_idCondicionLocal == 1 || _idCondicionLocal == 2);

  @override
  void initState() {
    super.initState();
    final loc = widget.localExistente;
    _nombreCtrl = TextEditingController(text: loc?.nombreLocal ?? 'Local ${widget.numeroLocalActual}');
    _descripcionCtrl = TextEditingController(text: loc?.descripcion ?? '');
    _numeroHogares = loc?.numeroHogares ?? 1;
    _idTipo = loc?.idTipo;
    _idCondicionLocal = loc?.idCondicionLocal;

    _cargarCatalogos();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final tipos = await _localService.getTiposLocales();
      final condiciones = await _localService.getCondicionesLocales();

      if (mounted) {
        setState(() {
          _tiposLocales = tipos;
          _condicionesLocales = condiciones;
          _idTipo ??= tipos.isNotEmpty ? tipos.first.id : null;
          _isLoadingCatalogos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Error al cargar catálogos: $e';
          _isLoadingCatalogos = false;
        });
      }
    }
  }

  Future<String?> _guardarDatos() async {
    if (!_formKey.currentState!.validate()) return null;

    final int? numHogares = _requiereHogares ? _numeroHogares : null;
    final int? idCondicion = _esHabitacional ? _idCondicionLocal : null;
    final String? desc = _descripcionCtrl.text.trim().isEmpty ? null : _descripcionCtrl.text.trim();
    final String? nom = _nombreCtrl.text.trim().isEmpty ? null : _nombreCtrl.text.trim();

    if (_esEdicion && widget.localExistente != null && numHogares != null) {
      final registrados = widget.localExistente!.hogaresRegistrados;
      if (numHogares < registrados) {
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Advertencia de Reducción'),
            content: Text(
              'Actualmente hay $registrados hogares registrados. Reducir el total esperado a $numHogares puede dejar el registro en estado excedente.\n\n¿Desea guardar de todas formas?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Guardar de todas formas'),
              ),
            ],
          ),
        );
        if (confirmar != true) return null;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      String localIdToReturn;
      if (_esEdicion) {
        final loc = await _localService.editarLocal(
          widget.localExistente!.id,
          idTipo: _idTipo,
          idCondicionLocal: idCondicion,
          nombreLocal: nom,
          numeroHogares: numHogares,
          descripcion: desc,
        );
        localIdToReturn = loc.id;
      } else {
        final loc = await _localService.crearLocal(
          widget.nivelId,
          idTipo: _idTipo!,
          idCondicionLocal: idCondicion,
          nombreLocal: nom,
          numeroHogares: numHogares,
          descripcion: desc,
        );
        localIdToReturn = loc.id;
      }

      if (mounted) setState(() => _isSaving = false);
      return localIdToReturn;
    } on LocalApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMsg = e.message;
        });
      }
      return null;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMsg = 'Error inesperado: $e';
        });
      }
      return null;
    }
  }

  Future<void> _guardar() async {
    final localId = await _guardarDatos();
    if (localId != null && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progreso = (widget.numeroLocalActual / widget.totalLocalesEsperados).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar Local' : 'Nuevo Local'),
        elevation: 0,
      ),
      body: Column(
        children: [
          BreadcrumbBar(
            items: [
              BreadcrumbItem(label: 'Nivel ${widget.numeroNivel}', onTap: () => Navigator.pop(context)),
              BreadcrumbItem(label: 'Local ${widget.numeroLocalActual} de ${widget.totalLocalesEsperados}'),
            ],
          ),
          LinearProgressIndicator(
            value: progreso,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondary),
            minHeight: 4,
          ),

          Expanded(
            child: _isLoadingCatalogos
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMsg != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],

                          // Header resumen visual
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.storefront, color: AppTheme.secondary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Local ${widget.numeroLocalActual}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Nivel ${widget.numeroNivel} • Registro ${widget.numeroLocalActual} de ${widget.totalLocalesEsperados}',
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Nombre del local
                          TextFormField(
                            controller: _nombreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre / Identificador del Local',
                              hintText: 'Ej. Local 101, Apartamento A...',
                              prefixIcon: Icon(Icons.label_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Combo Tipo de Local (FK)
                          DropdownButtonFormField<int>(
                            value: _idTipo,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de Local *',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _tiposLocales.map((t) {
                              return DropdownMenuItem<int>(
                                value: t.id,
                                child: Text(t.nombre, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _idTipo = val;
                                if (!_esHabitacional) {
                                  _idCondicionLocal = null;
                                }
                              });
                            },
                            validator: (v) => v == null ? 'Seleccione el tipo de local' : null,
                          ),
                          const SizedBox(height: 16),

                          // Combo Condición de Local (FK condicional)
                          if (_esHabitacional) ...[
                            DropdownButtonFormField<int>(
                              value: _idCondicionLocal,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Condición de Ocupación *',
                                prefixIcon: Icon(Icons.home_work_outlined),
                              ),
                              items: _condicionesLocales.map((c) {
                                return DropdownMenuItem<int>(
                                  value: c.id,
                                  child: Text(
                                    c.nombre,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _idCondicionLocal = val;
                                });
                              },
                              validator: (v) => v == null ? 'Seleccione la condición de ocupación' : null,
                            ),
                            const SizedBox(height: 16),

                             // Campo Número de Hogares (Stepper)
                             if (_requiereHogares) ...[
                               const Text(
                                 'Número de hogares',
                                 style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                               ),
                               const SizedBox(height: 8),
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                 decoration: BoxDecoration(
                                   color: AppTheme.surfaceVariant,
                                   borderRadius: BorderRadius.circular(10),
                                   border: Border.all(color: AppTheme.tertiary.withValues(alpha: 0.5)),
                                 ),
                                 child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     IconButton(
                                       icon: const Icon(Icons.remove_circle, color: AppTheme.tertiary),
                                       onPressed: _numeroHogares > 1
                                           ? () => setState(() => _numeroHogares--)
                                           : null,
                                     ),
                                     Text(
                                       '$_numeroHogares ${_numeroHogares == 1 ? 'hogar' : 'hogares'}',
                                       style: const TextStyle(
                                         fontSize: 16,
                                         fontWeight: FontWeight.bold,
                                         color: AppTheme.tertiary,
                                       ),
                                     ),
                                     IconButton(
                                       icon: const Icon(Icons.add_circle, color: AppTheme.tertiary),
                                       onPressed: () => setState(() => _numeroHogares++),
                                     ),
                                   ],
                                 ),
                               ),
                               const SizedBox(height: 16),

                               const Divider(color: Colors.white10, height: 24),

                               // Tarjeta Resumen / Navegación a Hogares de este Local
                               Builder(
                                 builder: (context) {
                                   final bool esNuevo = !_esEdicion || widget.localExistente == null;
                                   final registrados = esNuevo ? 0 : widget.localExistente!.hogaresRegistrados;
                                   final esperados = _numeroHogares;
                                   final double progreso = esperados > 0 ? (registrados / esperados).clamp(0.0, 1.0) : 0;
                                   final bool esCompleto = registrados >= esperados && esperados > 0;

                                   return Container(
                                     margin: const EdgeInsets.only(bottom: 20),
                                     padding: const EdgeInsets.all(16),
                                     decoration: BoxDecoration(
                                       color: AppTheme.surfaceVariant,
                                       borderRadius: BorderRadius.circular(12),
                                       border: Border.all(
                                         color: esCompleto
                                             ? Colors.greenAccent.withValues(alpha: 0.4)
                                             : AppTheme.tertiary.withValues(alpha: 0.3),
                                       ),
                                     ),
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                           children: [
                                             const Text(
                                               'Hogares registrados',
                                               style: TextStyle(
                                                 fontWeight: FontWeight.bold,
                                                 fontSize: 14,
                                                 color: Colors.white,
                                               ),
                                             ),
                                             Text(
                                               esNuevo ? '0 de $esperados' : '$registrados de $esperados',
                                               style: TextStyle(
                                                 fontWeight: FontWeight.bold,
                                                 fontSize: 13,
                                                 color: esCompleto ? Colors.greenAccent : AppTheme.tertiary,
                                               ),
                                             ),
                                           ],
                                         ),
                                         const SizedBox(height: 8),
                                         ClipRRect(
                                           borderRadius: BorderRadius.circular(4),
                                           child: LinearProgressIndicator(
                                             value: progreso,
                                             minHeight: 6,
                                             backgroundColor: Colors.white12,
                                             valueColor: AlwaysStoppedAnimation<Color>(
                                               esCompleto ? Colors.greenAccent : AppTheme.tertiary,
                                             ),
                                           ),
                                         ),
                                         const SizedBox(height: 16),
                                         if (esNuevo)
                                           SizedBox(
                                             width: double.infinity,
                                             child: ElevatedButton.icon(
                                               style: ElevatedButton.styleFrom(
                                                 backgroundColor: AppTheme.secondary,
                                                 foregroundColor: Colors.white,
                                                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                               ),
                                               icon: const Icon(Icons.family_restroom, size: 20),
                                               label: const Text(
                                                 'Guardar local y registrar hogares',
                                                 style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                               ),
                                               onPressed: _isSaving
                                                   ? null
                                                   : () async {
                                                       final localId = await _guardarDatos();
                                                       if (localId != null && mounted) {
                                                         await Navigator.push(
                                                           context,
                                                           MaterialPageRoute(
                                                             builder: (c) => HogarListaScreen(
                                                               localId: localId,
                                                               nombreLocal: _nombreCtrl.text.trim().isEmpty
                                                                   ? 'Local ${widget.numeroLocalActual}'
                                                                   : _nombreCtrl.text.trim(),
                                                               numeroNivel: widget.numeroNivel,
                                                               numeroHogaresEsperados: _numeroHogares,
                                                             ),
                                                           ),
                                                         );
                                                         if (mounted) Navigator.pop(context, true);
                                                       }
                                                     },
                                             ),
                                           )
                                         else
                                           InkWell(
                                             borderRadius: BorderRadius.circular(10),
                                             onTap: () async {
                                               await Navigator.push(
                                                 context,
                                                 MaterialPageRoute(
                                                   builder: (c) => HogarListaScreen(
                                                     localId: widget.localExistente!.id,
                                                     nombreLocal: _nombreCtrl.text.trim().isEmpty
                                                         ? 'Local ${widget.numeroLocalActual}'
                                                         : _nombreCtrl.text.trim(),
                                                     numeroNivel: widget.numeroNivel,
                                                     numeroHogaresEsperados: _numeroHogares,
                                                   ),
                                                 ),
                                               );
                                               if (mounted) setState(() {});
                                             },
                                             child: Container(
                                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                               decoration: BoxDecoration(
                                                 color: AppTheme.surface,
                                                 borderRadius: BorderRadius.circular(10),
                                                 border: Border.all(color: Colors.white24),
                                               ),
                                               child: Row(
                                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                 children: [
                                                   Row(
                                                     children: [
                                                       Icon(
                                                         Icons.family_restroom,
                                                         color: esCompleto ? Colors.greenAccent : AppTheme.tertiary,
                                                         size: 20,
                                                       ),
                                                       const SizedBox(width: 12),
                                                       Text(
                                                         registrados > 0
                                                             ? 'Ver hogares de este local'
                                                             : 'Aún no hay hogares ingresados',
                                                         style: const TextStyle(
                                                           fontWeight: FontWeight.w600,
                                                           fontSize: 14,
                                                           color: Colors.white,
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                   const Icon(
                                                     Icons.chevron_right,
                                                     color: Colors.white70,
                                                   ),
                                                 ],
                                               ),
                                             ),
                                           ),
                                       ],
                                     ),
                                   );
                                 },
                               ),
                             ],
                          ],

                          // Descripción (Ubicada al final antes del botón)
                          TextFormField(
                            controller: _descripcionCtrl,
                            maxLength: 150,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Descripción / Observaciones (opcional)',
                              hintText: 'Ej. Primer local a la izquierda ingresando por el pasillo principal',
                              prefixIcon: Icon(Icons.description_outlined),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceVariant),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 16),
                  label: Text(_esEdicion ? 'Guardar cambios' : 'Guardar', style: const TextStyle(fontSize: 12)),
                  onPressed: _isSaving ? null : _guardar,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.tertiary),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Guardar y Continuar →', style: TextStyle(fontSize: 11)),
                  onPressed: _isSaving ? null : () async {
                    final localIdToUse = await _guardarDatos();
                    if (localIdToUse != null && mounted) {
                      JerarquiaNavigatorService().navegarSiguienteDesdeLocal(
                        context: context,
                        estructuraId: '',
                        nombreEstructura: '',
                        nivelId: widget.nivelId,
                        numeroNivel: widget.numeroNivel,
                        localId: localIdToUse,
                        nombreLocal: _nombreCtrl.text.trim().isEmpty ? 'Local ${widget.numeroLocalActual}' : _nombreCtrl.text.trim(),
                        numeroLocalActual: widget.numeroLocalActual,
                        totalLocalesEsperados: widget.totalLocalesEsperados,
                        numeroHogaresEsperados: _requiereHogares ? _numeroHogares : null,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
