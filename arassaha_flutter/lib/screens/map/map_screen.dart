import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/work_order.dart';
import '../../models/work_order_map_pin.dart';
import '../../providers/map_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/status_badge.dart';
import '../equipment/equipment_detail_screen.dart';
import '../work_order_detail_screen.dart';

/// Harita ekranı: iş emirlerinin gerçek lat/lng konumlarını OpenStreetMap
/// üzerinde gösterir. Her pin backend'deki gerçek bir kayda karşılık gelir —
/// sahte/örnek pin yoktur (bkz. ARCHITECTURE.md Temel Kalite İlkesi). Ana
/// Sayfa revizyonundan önce MainShell'in kalıcı bir sekmesiydi; artık Ana
/// Sayfa'nın "öne çıkanlar" kartından ya da "Tüm Modüller" ekranından normal
/// bir sayfa olarak PUSH ediliyor — bu yüzden (WorkOrderListScreen'in AKSİNE)
/// kendi Scaffold/AppBar'ı vardır. Belirli bir statü filtresiyle açılmak
/// istendiğinde, çağıran taraf bu ekranı push etmeden ÖNCE
/// `MapProvider.fetchMapData(statusFilter: ...)` çağırır (bkz.
/// dashboard_screen.dart._openMap, assistant_chat_screen.dart._handleNavigation).
///
/// Not (dark mode): OpenStreetMap tile'ları her zaman açık renkli gelir —
/// bu, harita tile katmanı için bir sınırlamadır ve bu prototipte değiştirilmedi.
/// İstenirse dark modda tile katmanının üzerine hafif koyu bir ColorFiltered/
/// Container overlay eklenerek karartma efekti verilebilir; filtre çubuğu,
/// bilgi balonu ve butonlar zaten colorScheme üzerinden dark/light uyumludur.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  static const LatLng _regionCenter = LatLng(39.90, 41.27);
  static const double _regionZoom = 7.3;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MapScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapProvider>().fetchMapData();
    });
  }

  void _recenter() {
    _mapController.move(_regionCenter, _regionZoom);
  }

  void _showPinSheet(WorkOrderMapPin pin) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 4,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // İmza öğesi: durum şeridi — kart/liste/dashboard ile aynı görsel dil.
                AppCard(
                  statusStripeColor: statusColor(sheetContext, pin.status),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pin.title,
                        style: Theme.of(sheetContext).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          StatusBadge(status: pin.status),
                          PriorityBadge(priority: pin.priority),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: AppButton(
                          label: 'Detaya Git',
                          icon: Icons.arrow_forward,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    WorkOrderDetailScreen(workOrderId: pin.id),
                              ),
                            );
                          },
                        ),
                      ),
                      // Modül 4 (Ekipman) ile bağlantı: pin bir ekipmana bağlıysa
                      // doğrudan Ekipman Detayı'na gidilebilir (modüller arası bütünlük).
                      if (pin.equipmentId != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            label: 'Ekipman Detayını Gör',
                            icon: Icons.inventory_2_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EquipmentDetailScreen(
                                    equipmentId: pin.equipmentId!,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Marker _buildMarker(WorkOrderMapPin pin) {
    final isUrgent = pin.priority == WorkOrderPriority.acil;
    // B2 (dokunma alanı): öncekinden (36/46dp) büyütüldü, 48dp hedefine
    // yaklaştırıldı. Pinleri TAM 48dp yapmadık BİLİNÇLİ olarak — bir işten
    // yoğun bir bölgede yan yana duran pin'ler arasındaki dokunma alanı
    // çakışması (skill'in "Touch Spacing" kuralı) haritada birbirine yakın
    // arızalar arasında yanlış pin'e dokunmaya yol açar; 44/48dp bu iki
    // kural (hedef büyüklüğü vs. bitişik hedef çakışması) arasında bir denge.
    final size = isUrgent ? 48.0 : 44.0;
    final pinColor = statusColor(context, pin.status);
    return Marker(
      point: LatLng(pin.lat, pin.lng),
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showPinSheet(pin),
        child: Stack(
          alignment: const Alignment(0, -0.35),
          children: [
            Icon(Icons.location_on, color: pinColor, size: size),
            // Acil öncelikli işler için pin üzerinde küçük bir ünlem ikonu —
            // haritaya bakınca hangi arızaların en kritik olduğu anında ayırt edilir.
            if (isUrgent)
              Icon(
                Icons.priority_high,
                color: accessibleOnColor(pinColor),
                size: size * 0.34,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MapProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Harita'),
      body: Column(
        children: [
          _MapFilterBar(provider: provider),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: _regionCenter,
                    initialZoom: _regionZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.arasedas.arassaha_flutter',
                    ),
                    MarkerLayer(
                      markers: provider.mapMarkers.map(_buildMarker).toList(),
                    ),
                  ],
                ),
                if (provider.isLoading)
                  const Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: _LoadingChip(),
                  ),
                if (provider.errorMessage != null)
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: _ErrorBanner(
                      message: provider.errorMessage!,
                      onRetry: () => provider.fetchMapData(),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'map_recenter_fab',
                    tooltip: 'Erzurum merkezine dön',
                    onPressed: _recenter,
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashboard ve Görevler sekmesindeki filtre çubuğuyla aynı görsel stili
/// (ChoiceChip satırı) kullanır — modüller arası tutarlılık için.
class _MapFilterBar extends StatelessWidget {
  final MapProvider provider;
  const _MapFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final filters = <String, WorkOrderStatus?>{
      'Tümü': null,
      'Açık': WorkOrderStatus.acik,
      'Yolda': WorkOrderStatus.yolda,
      'Sahada': WorkOrderStatus.sahada,
      'Çözüldü': WorkOrderStatus.cozuldu,
    };

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = provider.statusFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              // Veri seti küçük (≈15 kayıt) olduğu için backend'e tekrar istek
              // atmak yerine mevcut liste istemci tarafında filtrelenir.
              onSelected: (_) => provider.setStatusFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LoadingChip extends StatelessWidget {
  const _LoadingChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Konum verileri yükleniyor...',
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: scheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Konum verileri yüklenemedi',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
            ),
            child: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}
