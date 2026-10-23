import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/progress_strip.dart';
import '../widgets/lista_jerarquica_card.dart';
import '../../core/models/capa_geometrica.dart';
import '../../core/models/jerarquia.dart';
import '../../core/services/nivel_service.dart';
import 'nivel_form_screen.dart';
import 'local_lista_screen.dart';


class NivelListaScreen extends StatefulWidget {
  final PuntoEstructura puntoEstructura;

  const NivelListaScreen({super.key, required this.puntoEstructura});

  @override
  State<NivelListaScreen> createState() => _NivelListaScreenState();
}

class _NivelListaScreenState extends State<NivelListaScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  NivelListResponse? _data;

  @override
  void initState() {
    super.initState();
    _cargarNiveles();
  }

  Future<void> _cargarNiveles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await NivelService().getNivelesByEstructura(widget.puntoEstructura.id);
      if (mounted) {
        final cantNivelesReales = widget.puntoEstructura.nivelesCantidad > 0
            ? widget.puntoEstructura.nivelesCantidad
            : data.nivelesCantidad;
        final nombreReal = (data.nombreEstructura == 'Estructura' && widget.puntoEstructura.nombre.isNotEmpty)
            ? widget.puntoEstructura.nombre
            : data.nombreEstructura;

        setState(() {
          _data = NivelListResponse(
            estructuraId: data.estructuraId,
            nombreEstructura: nombreReal,
            nivelesCantidad: cantNivelesReales,
            nivelesRegistrados: data.nivelesRegistrados,
            niveles: data.niveles,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo cargar la lista de niveles. Verifica tu conexión a la red.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _abrirLocalesDeNivel(NivelResumen nivel) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalListaScreen(
          nivelId: nivel.id,
          numeroNivel: nivel.numero,
          numeroLocalesEsperados: nivel.numeroLocales,
        ),
      ),
    );
    _cargarNiveles();
  }

  Future<void> _abrirFormulario({NivelResumen? nivelExistente, required int indexActual}) async {
    if (_data == null) return;

    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NivelFormScreen(
          estructuraId: widget.puntoEstructura.id,
          nombreEstructura: _data!.nombreEstructura,
          nivelesCantidad: _data!.nivelesCantidad,
          nivelExistente: nivelExistente,
          totalNiveles: _data!.nivelesCantidad,
          nivelIndexActual: indexActual,
        ),
      ),
    );

    if (resultado != null) {
      await _cargarNiveles();
      if (resultado is Nivel && mounted) {
        // Nivel recien creado -> Abrir la instancia de locales directamente
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LocalListaScreen(
              nivelId: resultado.id,
              numeroNivel: resultado.numeroNivel,
              numeroLocalesEsperados: resultado.numeroLocales,
            ),
          ),
        );
        _cargarNiveles();
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final nombreEst = _data?.nombreEstructura ?? widget.puntoEstructura.nombre;
    final totalMax = _data?.nivelesCantidad ?? widget.puntoEstructura.nivelesCantidad;
    final registrados = _data?.nivelesRegistrados ?? 0;
    final bool topeAlcanzado = registrados >= totalMax;

    int actualIndex = 0;
    if (_data != null && _data!.niveles.isNotEmpty) {
      final idxEnCurso = _data!.niveles.indexWhere((n) => n.localesRegistrados > 0 && n.localesRegistrados < n.numeroLocales);
      if (idxEnCurso != -1) {
        actualIndex = idxEnCurso;
      } else {
        actualIndex = (_data!.niveles.length - 1).clamp(0, totalMax - 1);
      }
    }

    final estadosList = _data?.niveles.map((n) {
      if (n.localesRegistrados == 0) return SegmentStatus.sinIniciar;
      if (n.localesRegistrados >= n.numeroLocales) return SegmentStatus.completo;
      return SegmentStatus.enCurso;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Niveles de la Estructura'),
      ),
      body: Column(
        children: [
          BreadcrumbBar(
            items: [
              BreadcrumbItem(
                label: nombreEst,
                onTap: () => Navigator.pop(context),
              ),
              BreadcrumbItem(label: 'Niveles'),
            ],
          ),
          ProgressStrip(
            total: totalMax,
            actualIndex: actualIndex,
            estados: estadosList,
          ),
          Expanded(
            child: _buildBody(topeAlcanzado),
          ),
        ],
      ),
      floatingActionButton: (_data != null)
          ? FloatingActionButton.extended(
              onPressed: topeAlcanzado
                  ? null
                  : () => _abrirFormulario(indexActual: registrados),
              icon: const Icon(Icons.add),
              label: const Text('Agregar nivel'),
              backgroundColor: topeAlcanzado ? Colors.grey : AppTheme.primary,
            )
          : null,
    );
  }

  Widget _buildBody(bool topeAlcanzado) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 64, color: AppTheme.error.withOpacity(0.7)),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _cargarNiveles,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null || _data!.niveles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear_outlined, size: 64, color: AppTheme.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('Sin niveles registrados', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Esta estructura permite registrar hasta ${_data?.nivelesCantidad ?? 1} nivel(es).',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _abrirFormulario(indexActual: 0),
              icon: const Icon(Icons.add),
              label: const Text('Añadir Primer Nivel'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
      itemCount: _data!.niveles.length + (topeAlcanzado ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _data!.niveles.length) {
          final nivel = _data!.niveles[index];
          return ListaJerarquicaCard(
            nivel: nivel,
            onEditar: () => _abrirFormulario(nivelExistente: nivel, indexActual: index),
            onContinuar: () => _abrirLocalesDeNivel(nivel),
          );

        } else {
          // Banner de aviso de tope alcanzado al final de la lista
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Has alcanzado el máximo de ${_data!.nivelesCantidad} nivel(es) configurados para esta estructura.',
                    style: TextStyle(fontSize: 12, color: AppTheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
