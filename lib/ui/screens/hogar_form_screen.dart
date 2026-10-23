import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/models/capa_geometrica.dart';
import '../../core/services/hogar_service.dart';
import '../widgets/breadcrumb_bar.dart';

class HogarFormScreen extends StatefulWidget {
  final String localId;
  final String nombreLocal;
  final int numeroNivel;
  final int numeroHogarActual;
  final int totalHogaresEsperados;
  final HogarResumen? hogarExistente;

  const HogarFormScreen({
    super.key,
    required this.localId,
    required this.nombreLocal,
    required this.numeroNivel,
    required this.numeroHogarActual,
    required this.totalHogaresEsperados,
    this.hogarExistente,
  });

  @override
  State<HogarFormScreen> createState() => _HogarFormScreenState();
}

class _HogarFormScreenState extends State<HogarFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hogarService = HogarService();

  late TextEditingController _jefeFamiliaCtrl;
  late TextEditingController _direccionCtrl;

  List<CatalogoItem> _catSexo = [];
  List<CatalogoItem> _catIdioma = [];

  int? _idSexo;
  int? _idIdioma;

  int _totalHabitantes = 1;
  int _p0_5 = 0;
  int _p6_11 = 0;
  int _p12_17 = 0;
  int _p18_23 = 0;
  int _p24_34 = 0;
  int _p35_44 = 0;
  int _p45_59 = 0;
  int _p60_69 = 0;
  int _p70_79 = 0;
  int _p80mas = 0;
  int _pNoEdad = 0;

  bool _isLoadingCatalogos = true;
  bool _isSaving = false;
  String? _errorMsg;

  bool get _esEdicion => widget.hogarExistente != null;

  @override
  void initState() {
    super.initState();
    final h = widget.hogarExistente;
    _jefeFamiliaCtrl = TextEditingController(text: h?.jefeFamilia ?? '');
    _direccionCtrl = TextEditingController(text: h?.direccion ?? '');
    _idSexo = h?.idSexo;
    _idIdioma = h?.idIdioma;

    if (h != null) {
      _totalHabitantes = h.totalHabitantes;
      _p0_5 = h.personas_0_5;
      _p6_11 = h.personas_6_11;
      _p12_17 = h.personas_12_17;
      _p18_23 = h.personas_18_23;
      _p24_34 = h.personas_24_34;
      _p35_44 = h.personas_35_44;
      _p45_59 = h.personas_45_59;
      _p60_69 = h.personas_60_69;
      _p70_79 = h.personas_70_79;
      _p80mas = h.personas_80_mas;
      _pNoEdad = h.personasNoEdad;
    }

    _cargarCatalogos();
  }

  @override
  void dispose() {
    _jefeFamiliaCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final sexos = await _hogarService.getSexos();
      final idiomas = await _hogarService.getIdiomas();

      if (mounted) {
        setState(() {
          _catSexo = sexos;
          _catIdioma = idiomas;
          _idSexo ??= sexos.isNotEmpty ? sexos.first.id : null;
          _idIdioma ??= idiomas.isNotEmpty ? idiomas.first.id : null;
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

  bool _tieneCambios() {
    if (_jefeFamiliaCtrl.text.trim().isNotEmpty) return true;
    if (_direccionCtrl.text.trim().isNotEmpty) return true;
    if (_totalHabitantes > 1) return true;
    if (_p0_5 + _p6_11 + _p12_17 + _p18_23 + _p24_34 + _p35_44 + _p45_59 + _p60_69 + _p70_79 + _p80mas + _pNoEdad > 0) return true;
    return false;
  }

  Future<bool> _onWillPop() async {
    if (_tieneCambios() && !_isSaving) {
      final descartar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('¿Descartar cambios?'),
          content: const Text('Ha ingresado datos en este formulario. Si sale ahora se perderán.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Continuar Editando'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      return descartar ?? false;
    }
    return true;
  }

  int get _sumaEdades {
    return _p0_5 + _p6_11 + _p12_17 + _p18_23 + _p24_34 + _p35_44 + _p45_59 + _p60_69 + _p70_79 + _p80mas + _pNoEdad;
  }

  Future<String?> _guardarDatos() async {
    if (!_formKey.currentState!.validate()) return null;

    final suma = _sumaEdades;
    if (suma > 0 && _totalHabitantes != suma) {
      setState(() {
        _errorMsg = 'No se puede guardar: La suma de personas por rango de edad ($suma) no coincide con el número total de habitantes declarado ($_totalHabitantes).';
      });
      return null;
    }

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      final String? jefe = _jefeFamiliaCtrl.text.trim().isEmpty ? null : _jefeFamiliaCtrl.text.trim();
      final String? dir = _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim();

      String hogarIdToReturn;
      if (_esEdicion) {
        final hog = await _hogarService.editarHogar(
          widget.hogarExistente!.id,
          jefeFamilia: jefe,
          idSexo: _idSexo,
          idIdioma: _idIdioma,
          direccion: dir,
          totalHabitantes: _totalHabitantes,
          p0_5: _p0_5, p6_11: _p6_11, p12_17: _p12_17, p18_23: _p18_23,
          p24_34: _p24_34, p35_44: _p35_44, p45_59: _p45_59, p60_69: _p60_69,
          p70_79: _p70_79, p80mas: _p80mas, pNoEdad: _pNoEdad,
        );
        hogarIdToReturn = hog.id;
      } else {
        final hog = await _hogarService.crearHogar(
          widget.localId,
          jefeFamilia: jefe,
          idSexo: _idSexo,
          idIdioma: _idIdioma,
          direccion: dir,
          totalHabitantes: _totalHabitantes,
          p0_5: _p0_5, p6_11: _p6_11, p12_17: _p12_17, p18_23: _p18_23,
          p24_34: _p24_34, p35_44: _p35_44, p45_59: _p45_59, p60_69: _p60_69,
          p70_79: _p70_79, p80mas: _p80mas, pNoEdad: _pNoEdad,
        );
        hogarIdToReturn = hog.id;
      }

      if (mounted) setState(() => _isSaving = false);
      return hogarIdToReturn;
    } on HogarApiException catch (e) {
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
    final hogarId = await _guardarDatos();
    if (hogarId != null && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildStepperItem(String label, int value, ValueChanged<int> onChanged, {int min = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white54, size: 22),
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Container(
                alignment: Alignment.center,
                width: 36,
                child: Text(
                  '$value',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppTheme.secondary, size: 22),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double progreso = (widget.numeroHogarActual / widget.totalHogaresEsperados).clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_esEdicion ? 'Editar Hogar' : 'Nuevo Hogar'),
          elevation: 0,
        ),
        body: Column(
          children: [
            BreadcrumbBar(
              items: [
                BreadcrumbItem(label: 'Local ${widget.nombreLocal}', onTap: () => Navigator.pop(context)),
                BreadcrumbItem(label: 'Hogar ${widget.numeroHogarActual} de ${widget.totalHogaresEsperados}'),
              ],
            ),
            LinearProgressIndicator(
              value: progreso,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.tertiary),
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
                                      color: AppTheme.tertiary.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.family_restroom, color: AppTheme.tertiary),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Hogar ${widget.numeroHogarActual}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          'Local ${widget.nombreLocal} • Registro ${widget.numeroHogarActual} de ${widget.totalHogaresEsperados}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Jefe(a) de Familia
                            TextFormField(
                              controller: _jefeFamiliaCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del Jefe(a) de Familia *',
                                hintText: 'Ej. María Morales / Juan Pérez',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese el nombre del jefe(a) de familia' : null,
                            ),
                            const SizedBox(height: 16),

                            // Combo Sexo (FK)
                            DropdownButtonFormField<int>(
                              value: _idSexo,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Sexo del Jefe(a) *',
                                prefixIcon: Icon(Icons.wc_outlined),
                              ),
                              items: _catSexo.map((s) {
                                return DropdownMenuItem<int>(
                                  value: s.id,
                                  child: Text(s.nombre, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _idSexo = val),
                              validator: (v) => v == null ? 'Seleccione el sexo' : null,
                            ),
                            const SizedBox(height: 16),

                            // Combo Idioma (FK)
                            DropdownButtonFormField<int>(
                              value: _idIdioma,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Idioma Predominante en el Hogar',
                                prefixIcon: Icon(Icons.language_outlined),
                              ),
                              items: _catIdioma.map((i) {
                                return DropdownMenuItem<int>(
                                  value: i.id,
                                  child: Text(i.nombre, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _idIdioma = val),
                            ),
                            const SizedBox(height: 16),

                            // Dirección / Referencia
                            TextFormField(
                              controller: _direccionCtrl,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Dirección / Referencia Interna (opcional)',
                                hintText: 'Ej. Apartamento 2B, al fondo a la derecha',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Stepper Total de Habitantes
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: _buildStepperItem(
                                'Total de Habitantes en el Hogar',
                                _totalHabitantes,
                                (v) => setState(() => _totalHabitantes = v),
                                min: 1,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Sección etaria colapsable (ExpansionTile)
                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                backgroundColor: AppTheme.surface,
                                collapsedBackgroundColor: AppTheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                leading: const Icon(Icons.group_outlined, color: AppTheme.secondary),
                                title: const Text(
                                  'Distribución de Habitantes por Edad',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                subtitle: const Text('Opcional — toque para expandir', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      children: [
                                        _buildStepperItem('Personas de 0 a 5 años', _p0_5, (v) => setState(() => _p0_5 = v)),
                                        _buildStepperItem('Personas de 6 a 11 años', _p6_11, (v) => setState(() => _p6_11 = v)),
                                        _buildStepperItem('Personas de 12 a 17 años', _p12_17, (v) => setState(() => _p12_17 = v)),
                                        _buildStepperItem('Personas de 18 a 23 años', _p18_23, (v) => setState(() => _p18_23 = v)),
                                        _buildStepperItem('Personas de 24 a 34 años', _p24_34, (v) => setState(() => _p24_34 = v)),
                                        _buildStepperItem('Personas de 35 a 44 años', _p35_44, (v) => setState(() => _p35_44 = v)),
                                        _buildStepperItem('Personas de 45 a 59 años', _p45_59, (v) => setState(() => _p45_59 = v)),
                                        _buildStepperItem('Personas de 60 a 69 años', _p60_69, (v) => setState(() => _p60_69 = v)),
                                        _buildStepperItem('Personas de 70 a 79 años', _p70_79, (v) => setState(() => _p70_79 = v)),
                                        _buildStepperItem('Personas de 80 años o más', _p80mas, (v) => setState(() => _p80mas = v)),
                                        _buildStepperItem('Personas con edad no especificada', _pNoEdad, (v) => setState(() => _pNoEdad = v)),
                                      ],
                                    ),
                                  ),
                                ],
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
                    onPressed: _isSaving ? null : () async {
                      final pop = await _onWillPop();
                      if (pop && context.mounted) Navigator.pop(context, false);
                    },
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
                      final hogarIdToUse = await _guardarDatos();
                      if (hogarIdToUse != null && mounted) {
                        if (widget.numeroHogarActual < widget.totalHogaresEsperados) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (c) => HogarFormScreen(
                                localId: widget.localId,
                                nombreLocal: widget.nombreLocal,
                                numeroNivel: widget.numeroNivel,
                                numeroHogarActual: widget.numeroHogarActual + 1,
                                totalHogaresEsperados: widget.totalHogaresEsperados,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Se han registrado todos los hogares de este local.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                          Navigator.pop(context, true);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
