import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/services/hogar_service.dart';
import '../widgets/breadcrumb_bar.dart';
import 'hogar_form_screen.dart';

class HogarListaScreen extends StatefulWidget {
  final String localId;
  final String nombreLocal;
  final int numeroNivel;
  final int numeroHogaresEsperados;

  const HogarListaScreen({
    super.key,
    required this.localId,
    required this.nombreLocal,
    required this.numeroNivel,
    required this.numeroHogaresEsperados,
  });

  @override
  State<HogarListaScreen> createState() => _HogarListaScreenState();
}

class _HogarListaScreenState extends State<HogarListaScreen> {
  final _hogarService = HogarService();

  bool _isLoading = true;
  String? _error;
  HogarListResponse? _response;

  @override
  void initState() {
    super.initState();
    _cargarHogares();
  }

  Future<void> _cargarHogares() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _hogarService.getHogaresByLocal(widget.localId);
      if (mounted) {
        setState(() {
          _response = res;
          _isLoading = false;
        });
      }
    } on HogarApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar los hogares: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _abrirFormularioNuevo() async {
    final res = _response;
    if (res == null) return;

    if (res.hogaresRegistrados >= res.numeroHogaresEsperados) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se ha alcanzado el límite de ${res.numeroHogaresEsperados} hogares para este local.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => HogarFormScreen(
          localId: widget.localId,
          nombreLocal: res.nombreLocal,
          numeroNivel: widget.numeroNivel,
          numeroHogarActual: res.hogaresRegistrados + 1,
          totalHogaresEsperados: res.numeroHogaresEsperados,
        ),
      ),
    );

    if (actualizado == true) {
      _cargarHogares();
    }
  }

  Future<void> _abrirFormularioEditar(HogarResumen h, int index) async {
    final res = _response;
    if (res == null) return;

    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => HogarFormScreen(
          localId: widget.localId,
          nombreLocal: res.nombreLocal,
          numeroNivel: widget.numeroNivel,
          numeroHogarActual: index + 1,
          totalHogaresEsperados: res.numeroHogaresEsperados,
          hogarExistente: h,
        ),
      ),
    );

    if (actualizado == true) {
      _cargarHogares();
    }
  }

  Future<void> _eliminarHogar(HogarResumen h) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar Hogar'),
        content: Text('¿Está seguro de eliminar el hogar de "${h.jefeFamilia ?? 'Sin nombre'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await _hogarService.eliminarHogar(h.id);
        _cargarHogares();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<bool> _onWillPop() async {
    final res = _response;
    if (res != null && !res.esCompleto) {
      final salir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Registro de Hogares Incompleto'),
          content: Text(
            'Ha registrado ${res.hogaresRegistrados} de ${res.numeroHogaresEsperados} hogares esperados en este local.\n\n¿Desea salir de todas formas?',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Continuar Registrando'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salir'),
            ),
          ],
        ),
      );
      return salir ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final res = _response;
    final int registrados = res?.hogaresRegistrados ?? 0;
    final int esperados = res?.numeroHogaresEsperados ?? widget.numeroHogaresEsperados;
    final bool esCompleto = res?.esCompleto ?? false;
    final double progreso = esperados > 0 ? (registrados / esperados).clamp(0.0, 1.0) : 1.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text('Hogares: ${res?.nombreLocal ?? widget.nombreLocal}'),
          elevation: 0,
        ),
        body: Column(
          children: [
            BreadcrumbBar(
              items: [
                BreadcrumbItem(label: 'Nivel ${widget.numeroNivel}', onTap: () => Navigator.pop(context)),
                BreadcrumbItem(label: 'Local ${res?.nombreLocal ?? widget.nombreLocal}'),
                BreadcrumbItem(label: 'Hogares ($registrados de $esperados)'),
              ],
            ),

            // Barra de progreso de completitud
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.surfaceVariant,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progreso del Local $registrados/$esperados',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      Text(
                        '${(progreso * 100).toInt()}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: esCompleto ? Colors.greenAccent : AppTheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _cargarHogares, child: const Text('Reintentar')),
                            ],
                          ),
                        )
                      : (res == null || res.hogares.isEmpty)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.family_restroom_outlined, size: 64, color: AppTheme.tertiary.withValues(alpha: 0.4)),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No hay hogares registrados en este local',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Se esperan $esperados hogar(es). Comienza registrando el primero.',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.tertiary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.add, size: 20),
                                      label: const Text('Registrar Primer Hogar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      onPressed: _abrirFormularioNuevo,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: res.hogares.length,
                              itemBuilder: (context, index) {
                                final h = res.hogares[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  color: AppTheme.surface,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    onTap: () => _abrirFormularioEditar(h, index),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.tertiary.withValues(alpha: 0.2),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(color: AppTheme.tertiary, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      h.jefeFamilia ?? 'Hogar ${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (h.nombreSexo != null)
                                            Text('Sexo jefe(a): ${h.nombreSexo}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          if (h.nombreIdioma != null)
                                            Text('Idioma: ${h.nombreIdioma}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          Text('Habitantes: ${h.totalHabitantes}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                          if (!h.esValidoMatematicamente)
                                            const Text('⚠️ Suma de edades no coincide', style: TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () => _eliminarHogar(h),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.chevron_right, color: Colors.white70),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
        floatingActionButton: (registrados < esperados)
            ? FloatingActionButton.extended(
                backgroundColor: AppTheme.tertiary,
                onPressed: _abrirFormularioNuevo,
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  'Agregar Hogar (${registrados + 1}/$esperados)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            : null,
      ),
    );
  }
}
