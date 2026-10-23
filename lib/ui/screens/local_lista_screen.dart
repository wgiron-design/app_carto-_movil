import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/services/local_service.dart';
import '../widgets/breadcrumb_bar.dart';
import 'local_form_screen.dart';
import 'hogar_lista_screen.dart';

class LocalListaScreen extends StatefulWidget {
  final String nivelId;
  final int numeroNivel;
  final int numeroLocalesEsperados;

  const LocalListaScreen({
    super.key,
    required this.nivelId,
    required this.numeroNivel,
    required this.numeroLocalesEsperados,
  });

  @override
  State<LocalListaScreen> createState() => _LocalListaScreenState();
}

class _LocalListaScreenState extends State<LocalListaScreen> {
  final _localService = LocalService();

  bool _isLoading = true;
  String? _error;
  LocalListResponse? _response;

  @override
  void initState() {
    super.initState();
    _cargarLocales();
  }

  Future<void> _cargarLocales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _localService.getLocalesByNivel(widget.nivelId);
      if (mounted) {
        setState(() {
          _response = res;
          _isLoading = false;
        });
      }
    } on LocalApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar los locales: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _abrirHogaresDeLocal(LocalResumen loc) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => HogarListaScreen(
          localId: loc.id,
          nombreLocal: loc.nombreLocal ?? 'Local',
          numeroNivel: widget.numeroNivel,
          numeroHogaresEsperados: loc.numeroHogares ?? 1,
        ),
      ),
    );
    _cargarLocales();
  }

  Future<void> _abrirFormularioNuevo() async {
    final res = _response;
    if (res == null) return;

    if (res.localesRegistrados >= res.numeroLocalesEsperados) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se ha alcanzado el límite de ${res.numeroLocalesEsperados} locales para este nivel.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => LocalFormScreen(
          nivelId: widget.nivelId,
          numeroNivel: widget.numeroNivel,
          numeroLocalActual: res.localesRegistrados + 1,
          totalLocalesEsperados: res.numeroLocalesEsperados,
        ),
      ),
    );

    if (actualizado == true) {
      await _cargarLocales();
      // Si el último local recién creado requiere hogares y no es completo, abrir automáticamente
      final resActualizado = _response;
      if (resActualizado != null && resActualizado.locales.isNotEmpty) {
        final ultimoLocal = resActualizado.locales.last;
        if (!ultimoLocal.esCompleto && ultimoLocal.numeroHogares != null && ultimoLocal.numeroHogares! > 0) {
          if (mounted) {
            await _abrirHogaresDeLocal(ultimoLocal);
          }
        }
      }
    }
  }

  Future<void> _abrirFormularioEditar(LocalResumen loc, int index) async {
    final res = _response;
    if (res == null) return;

    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => LocalFormScreen(
          nivelId: widget.nivelId,
          numeroNivel: widget.numeroNivel,
          numeroLocalActual: index + 1,
          totalLocalesEsperados: res.numeroLocalesEsperados,
          localExistente: loc,
        ),
      ),
    );

    if (actualizado == true) {
      _cargarLocales();
    }
  }

  Future<void> _eliminarLocal(LocalResumen loc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar Local'),
        content: Text('¿Está seguro de eliminar el local "${loc.nombreLocal ?? 'Local sin nombre'}"? Se eliminarán también sus hogares.'),
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
        await _localService.eliminarLocal(loc.id);
        _cargarLocales();
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
    if (res != null && res.localesRegistrados < res.numeroLocalesEsperados) {
      final salir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Registro de Locales Incompleto'),
          content: Text(
            'Ha registrado ${res.localesRegistrados} de ${res.numeroLocalesEsperados} locales esperados en este nivel.\n\n¿Desea salir de todas formas?',
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
    final int registrados = res?.localesRegistrados ?? 0;
    final int esperados = res?.numeroLocalesEsperados ?? widget.numeroLocalesEsperados;
    final double progreso = esperados > 0 ? (registrados / esperados).clamp(0.0, 1.0) : 0;

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
          title: Text('Locales del Nivel ${widget.numeroNivel}'),
          elevation: 0,
        ),
        body: Column(
          children: [
            BreadcrumbBar(
              items: [
                BreadcrumbItem(label: 'Nivel ${widget.numeroNivel}', onTap: () => Navigator.pop(context)),
                BreadcrumbItem(label: 'Locales ($registrados de $esperados)'),
              ],
            ),


            // Barra de progreso de completitud del nivel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.surfaceVariant,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progreso del Nivel $registrados/$esperados',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      Text(
                        '${(progreso * 100).toInt()}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: registrados == esperados ? Colors.greenAccent : AppTheme.secondary,
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
                        registrados == esperados ? Colors.greenAccent : AppTheme.secondary,
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
                              ElevatedButton(onPressed: _cargarLocales, child: const Text('Reintentar')),
                            ],
                          ),
                        )
                      : (res == null || res.locales.isEmpty)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.storefront_outlined, size: 64, color: AppTheme.secondary.withValues(alpha: 0.4)),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No hay locales registrados en este nivel',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Se esperan $esperados local(es). Comienza registrando el primero.',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.secondary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.add, size: 20),
                                      label: const Text('Registrar Primer Local', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      onPressed: _abrirFormularioNuevo,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: res.locales.length,
                              itemBuilder: (context, index) {
                                final loc = res.locales[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  color: AppTheme.surface,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    onTap: () => _abrirFormularioEditar(loc, index),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.secondary.withValues(alpha: 0.2),
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      loc.nombreLocal ?? 'Local ${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc.nombreTipo ?? 'Tipo #${loc.idTipo}',
                                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                          if (loc.nombreCondicion != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Condición: ${loc.nombreCondicion}',
                                              style: TextStyle(color: AppTheme.secondary.withValues(alpha: 0.8), fontSize: 12),
                                            ),
                                          ],
                                          if (loc.numeroHogares != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Hogares esperados: ${loc.numeroHogares} • Registrados: ${loc.hogaresRegistrados}',
                                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (loc.numeroHogares != null && loc.numeroHogares! > 0)
                                          IconButton(
                                            tooltip: 'Gestionar Hogares',
                                            icon: Icon(
                                              Icons.family_restroom,
                                              color: loc.esCompleto ? Colors.greenAccent : AppTheme.tertiary,
                                            ),
                                            onPressed: () => _abrirHogaresDeLocal(loc),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () => _eliminarLocal(loc),
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
                backgroundColor: AppTheme.secondary,
                onPressed: _abrirFormularioNuevo,
                icon: const Icon(Icons.add, color: Color(0xFF003731)),
                label: Text(
                  'Agregar Local (${registrados + 1}/$esperados)',
                  style: const TextStyle(color: Color(0xFF003731), fontWeight: FontWeight.bold),
                ),
              )
            : null,
      ),
    );
  }
}
