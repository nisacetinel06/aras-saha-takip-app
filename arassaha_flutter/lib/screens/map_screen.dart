import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';
import '../widgets/status_badge.dart';
import 'work_order_detail_screen.dart';

/// Harita sekmesi içeriği: iş emirlerinin gerçek lat/lng konumlarını
/// OpenStreetMap üzerinde gösterir. Her pin backend'deki gerçek bir kayda
/// karşılık gelir — sahte/örnek pin yoktur (bkz. ARCHITECTURE.md Temel Kalite
/// İlkesi).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();

  List<WorkOrder> _workOrders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final orders = await _apiService.getWorkOrders();
      if (!mounted) return;
      setState(() => _workOrders = orders);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  LatLng get _initialCenter {
    if (_workOrders.isEmpty) {
      return const LatLng(39.9, 41.27); // Veri yokken Erzurum civarı (varsayılan)
    }
    final avgLat = _workOrders.map((w) => w.lat).reduce((a, b) => a + b) / _workOrders.length;
    final avgLng = _workOrders.map((w) => w.lng).reduce((a, b) => a + b) / _workOrders.length;
    return LatLng(avgLat, avgLng);
  }

  void _showWorkOrderSheet(WorkOrder workOrder) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(workOrder.title, style: Theme.of(sheetContext).textTheme.headlineSmall),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status: workOrder.status),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Text(workOrder.locationName, style: TextStyle(color: scheme.onSurfaceVariant))),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => WorkOrderDetailScreen(workOrderId: workOrder.id)),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Detaya Git'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading && _workOrders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _workOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: scheme.error),
              const SizedBox(height: 12),
              Text('Harita verisi yüklenemedi: $_errorMessage', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Tekrar Dene')),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _initialCenter, initialZoom: 7),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.arasedas.arassaha_flutter',
            ),
            MarkerLayer(
              markers: _workOrders.map((wo) {
                return Marker(
                  point: LatLng(wo.lat, wo.lng),
                  width: 42,
                  height: 42,
                  child: GestureDetector(
                    onTap: () => _showWorkOrderSheet(wo),
                    child: Icon(
                      Icons.location_on,
                      color: statusColor(context, wo.status),
                      size: 42,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'map_refresh_fab',
            onPressed: _load,
            child: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}
