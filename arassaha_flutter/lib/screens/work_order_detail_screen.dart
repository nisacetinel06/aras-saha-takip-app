import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/equipment.dart' show EquipmentType;
import '../models/equipment_risk.dart' show RiskLevel;
import '../models/material.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/maintenance_provider.dart';
import '../providers/material_provider.dart';
import '../providers/risk_provider.dart';
import '../providers/work_order_detail_provider.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/material_picker_field.dart';
import '../widgets/status_badge.dart';
import '../widgets/work_order_card.dart' show formatRelativeTime;
import 'equipment/equipment_detail_screen.dart';

class WorkOrderDetailScreen extends StatelessWidget {
  final int workOrderId;

  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        AnalyticsService.logScreenView('WorkOrderDetailScreen');
        // Malzeme / Yedek Parça Stok Takibi (Modül 13) — "Kullanılan
        // Malzemeler" bölümü kendi verisini iş emri detayının yüklenmesini
        // BEKLEMEDEN çekebilir (workOrderId zaten burada biliniyor, ekipman
        // ilişkisine bağlı değil) — bkz. _MaterialsSection.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<MaterialProvider>().fetchWorkOrderMaterials(workOrderId);
        });
        return WorkOrderDetailProvider(workOrderId)..loadDetail();
      },
      child: const _WorkOrderDetailBody(),
    );
  }
}

class _WorkOrderDetailBody extends StatelessWidget {
  const _WorkOrderDetailBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'İş Emri Detayı'),
      body: SafeArea(
        top: false,
        child: Consumer<WorkOrderDetailProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.workOrder == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage != null && provider.workOrder == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(provider.errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: provider.loadDetail,
                      ),
                    ],
                  ),
                ),
              );
            }

            final workOrder = provider.workOrder!;
            return RefreshIndicator(
              onRefresh: provider.loadDetail,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    workOrder.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      StatusBadge(status: workOrder.status),
                      PriorityBadge(priority: workOrder.priority),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SectionCard(
                    title: 'Açıklama',
                    icon: Icons.description_outlined,
                    child: _QuoteBox(text: workOrder.description),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Konum',
                    icon: Icons.location_on_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          icon: Icons.place_outlined,
                          text: workOrder.locationName,
                        ),
                        const SizedBox(height: 4),
                        _InfoRow(
                          icon: Icons.map_outlined,
                          text:
                              'Lat: ${workOrder.lat.toStringAsFixed(5)}, Lng: ${workOrder.lng.toStringAsFixed(5)}',
                          mono: true,
                        ),
                        const SizedBox(height: 10),
                        AppButton(
                          label: 'Haritada Aç',
                          icon: Icons.directions_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => _openInMaps(
                            context,
                            workOrder.lat,
                            workOrder.lng,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Atanan Personel',
                    icon: Icons.badge_outlined,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InitialsAvatar(name: workOrder.assignedUser?.name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workOrder.assignedUser?.name ??
                                    'Henüz atanmadı',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (workOrder.assignedUser != null)
                                Text(
                                  workOrder.assignedUser!.role,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              if (workOrder.equipmentRef.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                // Modül 4 (Ekipman) ile gerçek, İKİ YÖNLÜ bağlantı:
                                // Ekipman Detayı geçmiş arızalarını gösterirken
                                // (Modül 4), burada da bu iş emrinin bağlı olduğu
                                // ekipmanın tipi + QR kodu gösterilip dokununca
                                // doğrudan Ekipman Detayı'na gidilir.
                                workOrder.equipmentId != null
                                    ? InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EquipmentDetailScreen(
                                                  equipmentId:
                                                      workOrder.equipmentId!,
                                                ),
                                          ),
                                        ),
                                        child: _EquipmentChip(
                                          code: workOrder.equipmentRef,
                                          type: workOrder.equipmentType,
                                        ),
                                      )
                                    : _EquipmentChip(
                                        code: workOrder.equipmentRef,
                                        type: workOrder.equipmentType,
                                      ),
                                // Kestirimci Bakım Planlama (Modül 12) bağlamı:
                                // bu bir ARIZA iş emri ise (önleyici bakımdan
                                // dönüştürülmüş bir iş emri zaten kendisi bir
                                // öneriyi temsil ettiği için burada tekrar
                                // gösterilmez), bağlı ekipmanın risk skoruna göre
                                // neden bir bakım önerisi olup olmadığını açıklayan
                                // küçük bir not gösterilir.
                                if (workOrder.equipmentId != null &&
                                    workOrder.sourceType ==
                                        WorkOrderSourceType.ariza)
                                  _RiskContextNote(
                                    equipmentId: workOrder.equipmentId!,
                                  ),
                              ],
                            ],
                          ),
                        ),
                        // Yeniden atama — yalnızca dispeçer/yönetici (Modül 7 devamı,
                        // bkz. ARCHITECTURE.md). Teknisyen bu ikonu hiç görmez.
                        if (context.watch<AuthProvider>().canCreateWorkOrders)
                          IconButton(
                            tooltip: 'Atanan Kişiyi Değiştir',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () =>
                                _showReassignSheet(context, workOrder),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Durum Güncelle',
                    icon: Icons.sync_alt,
                    child: _StatusUpdateSection(workOrder: workOrder),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Fotoğraflar',
                    icon: Icons.photo_library_outlined,
                    child: _PhotoSection(workOrder: workOrder),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Kullanılan Malzemeler',
                    icon: Icons.inventory_2_outlined,
                    child: _MaterialsSection(workOrder: workOrder),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showReassignSheet(BuildContext context, WorkOrder workOrder) {
    final provider = context.read<WorkOrderDetailProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ReassignSheet(
        provider: provider,
        currentAssignedUserId: workOrder.assignedUser?.id,
      ),
    );
  }

  Future<void> _openInMaps(BuildContext context, double lat, double lng) async {
    final messenger = ScaffoldMessenger.of(context);
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      final opened = await launchUrl(
        geoUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Harita uygulaması açılamadı.')),
      );
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _QuoteBox extends StatelessWidget {
  final String text;
  const _QuoteBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Text(text, style: const TextStyle(height: 1.4)),
    );
  }
}

class _EquipmentChip extends StatelessWidget {
  final String code;
  final EquipmentType? type;
  const _EquipmentChip({required this.code, this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type?.icon ?? Icons.qr_code_2_outlined,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          if (type != null) ...[
            Text(
              type!.label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '·',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            code,
            style: AppTextStyles.dataMono(
              color: scheme.onSurfaceVariant,
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _riskAdjective(RiskLevel level) {
  switch (level) {
    case RiskLevel.dusuk:
      return 'düşük';
    case RiskLevel.orta:
      return 'orta';
    case RiskLevel.yuksek:
      return 'yüksek';
  }
}

/// Kestirimci Bakım Planlama (Modül 12) bağlam notu — "acil" bir ARIZA iş
/// emrinin bağlı olduğu ekipman için neden bir bakım önerisi olup olmadığını
/// açıklar. Bu iki kavram KASITLI olarak bağımsızdır: bir iş emrinin önceliği
/// (dispeçerin seçtiği) ile bağlı ekipmanın risk skoru (Modül 9'un geçmiş
/// yaş/bakım/arıza verisinden hesapladığı) aynı şey değildir — örn. ani bir
/// fırtına hasarı "acil" olabilir ama o ekipmanın risk skoru düşük olabilir,
/// çünkü risk modeli anlık olayları değil yapısal geçmişi öngörür.
class _RiskContextNote extends StatefulWidget {
  final int equipmentId;
  const _RiskContextNote({required this.equipmentId});

  @override
  State<_RiskContextNote> createState() => _RiskContextNoteState();
}

class _RiskContextNoteState extends State<_RiskContextNote> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RiskProvider>().fetchEquipmentRisk(widget.equipmentId);
      context.read<MaintenanceProvider>().fetchRecommendations(
        statusFilter: 'onerildi',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final risk = context.watch<RiskProvider>().riskFor(widget.equipmentId);
    if (risk == null) return const SizedBox.shrink();

    final hasRecommendation =
        context.watch<MaintenanceProvider>().recommendationForEquipment(
          widget.equipmentId,
        ) !=
        null;
    final scheme = Theme.of(context).colorScheme;

    final String text;
    if (risk.riskLevel == RiskLevel.dusuk) {
      text =
          'Bu ekipmanın risk skoru düşük (${risk.riskScore}) — kestirimci bakım önerisi bulunmuyor.';
    } else if (hasRecommendation) {
      text =
          'Bu ekipmanın risk skoru ${_riskAdjective(risk.riskLevel)} (${risk.riskScore}) — bekleyen bir bakım önerisi var.';
    } else {
      text =
          'Bu ekipmanın risk skoru ${_riskAdjective(risk.riskLevel)} (${risk.riskScore}) ancak henüz bir bakım önerisi oluşturulmamış.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String? name;
  const _InitialsAvatar({required this.name});

  String get _initials {
    if (name == null || name!.trim().isEmpty) return '?';
    final parts = name!.trim().split(RegExp(r'\s+'));
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        _initials,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool mono;
  const _InfoRow({required this.icon, required this.text, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: mono
              ? Text(
                  text,
                  style: AppTextStyles.dataMono(color: scheme.onSurface),
                )
              : Text(text),
        ),
      ],
    );
  }
}

/// Bir sonraki statüye geçiş için sabit, kısa etiket + ikon — değişken
/// uzunluktaki "${status}'a Geçir" metni dar ekranlarda taşmaya (RenderFlex
/// overflow) yol açıyordu. Bkz. DESIGN_SYSTEM.md A.4.
class _NextStatusAction {
  final String label;
  final IconData icon;
  const _NextStatusAction(this.label, this.icon);
}

const _nextStatusActions = <WorkOrderStatus, _NextStatusAction>{
  WorkOrderStatus.yolda: _NextStatusAction(
    'Yolda',
    Icons.directions_car_outlined,
  ),
  WorkOrderStatus.sahada: _NextStatusAction(
    'Sahadayım',
    Icons.location_on_outlined,
  ),
  WorkOrderStatus.cozuldu: _NextStatusAction(
    'Çözüldü',
    Icons.check_circle_outline,
  ),
};

class _StatusUpdateSection extends StatelessWidget {
  final WorkOrder workOrder;
  const _StatusUpdateSection({required this.workOrder});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkOrderDetailProvider>();
    final nextStatus = workOrder.status.nextStatus;
    final scheme = Theme.of(context).colorScheme;

    // Yönetici sahada çalışmadığı için durumu bizzat değiştiremez, yalnızca
    // takip eder — bu yüzden ona aksiyon butonu değil, sadece bilgilendirme
    // metni gösterilir (backend de aynı kuralı PATCH /:id/status'ta
    // requireRole ile zorunlu kılıyor, bkz. AuthProvider.canUpdateWorkOrderStatus).
    final canUpdate = context.watch<AuthProvider>().canUpdateWorkOrderStatus;

    if (nextStatus == null) {
      return Text(
        'Bu iş emri çözülmüş durumda, daha ileri bir aşama yok.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    if (!canUpdate) {
      return Text(
        'Mevcut durum: ${workOrder.status.label}',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    final action = _nextStatusActions[nextStatus]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mevcut durum: ${workOrder.status.label}'),
        const SizedBox(height: AppSpacing.sm + 4),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: action.label,
            icon: action.icon,
            isLoading: provider.isUpdating,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final success = await provider.updateStatus(nextStatus);
              if (success) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Durum "${nextStatus.label}" olarak güncellendi.',
                    ),
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      provider.errorMessage ?? 'Durum güncellenemedi.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _PhotoSection extends StatelessWidget {
  final WorkOrder workOrder;
  const _PhotoSection({required this.workOrder});

  Future<void> _pickAndUpload(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<WorkOrderDetailProvider>();

    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (file == null) return;

    final success = await provider.addPhoto(File(file.path));
    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf eklendi.')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Fotoğraf eklenemedi.'),
        ),
      );
    }
  }

  void _showSourcePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera ile Çek'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndUpload(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndUpload(context, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkOrderDetailProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (workOrder.photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Henüz fotoğraf eklenmemiş.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          // C1 (responsive grid): bkz. home_screen.dart modül ızgarasındaki
          // aynı not — telefonda 3, tablette 4-5 sütun.
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: workOrder.photos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: responsiveGridColumns(
                  constraints.maxWidth,
                  minColumns: 3,
                ),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final photo = workOrder.photos[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: scheme.surfaceContainerHigh,
                    // Fotoğraf backend'in diskinde gerçekten saklanır ve buradan
                    // ağ üzerinden çekilir; bu sayede başka bir cihazdan (örn.
                    // saha amirinin telefonundan) açıldığında da görüntülenir.
                    child: Image.network(
                      ApiService.photoUrl(photo.photoPath),
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Fotoğraf Ekle',
          icon: Icons.add_a_photo_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: provider.isUpdating
              ? null
              : () => _showSourcePicker(context),
        ),
      ],
    );
  }
}

/// Malzeme / Yedek Parça Stok Takibi (Modül 13) — "Kullanılan Malzemeler"
/// bölümü. Kayıt (Malzeme Ekle) giriş yapmış HERKESE açıktır (teknisyen
/// dahil — sahada malzemeyi kullanan kişi odur); silme yalnızca dispeçer/
/// yönetici (backend requireRole ile de zorunlu kılınır, bkz. routes/materials.js).
class _MaterialsSection extends StatelessWidget {
  final WorkOrder workOrder;
  const _MaterialsSection({required this.workOrder});

  void _showAddMaterialSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddMaterialSheet(
        workOrderId: workOrder.id,
        equipmentTypeHint: workOrder.equipmentType?.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialProvider>();
    final scheme = Theme.of(context).colorScheme;
    // İş emri oluşturma yetkisiyle AYNI rol seti (dispeçer/yönetici) —
    // teknisyen bu ikonu hiç görmez.
    final canDelete = context.watch<AuthProvider>().canCreateWorkOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.isLoadingWorkOrderMaterials &&
            provider.workOrderMaterials.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (provider.workOrderMaterialsErrorMessage != null)
          Text(
            provider.workOrderMaterialsErrorMessage!,
            style: TextStyle(color: scheme.error, fontSize: 13),
          )
        else if (provider.workOrderMaterials.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Henüz malzeme kaydedilmedi.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < provider.workOrderMaterials.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _MaterialUsageRow(
                  usage: provider.workOrderMaterials[i],
                  workOrderId: workOrder.id,
                  canDelete: canDelete,
                ),
              ],
            ],
          ),
        const SizedBox(height: AppSpacing.sm + 4),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Malzeme Ekle',
            icon: Icons.add_box_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => _showAddMaterialSheet(context),
          ),
        ),
      ],
    );
  }
}

class _MaterialUsageRow extends StatelessWidget {
  final WorkOrderMaterialUsage usage;
  final int workOrderId;
  final bool canDelete;
  const _MaterialUsageRow({
    required this.usage,
    required this.workOrderId,
    required this.canDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<MaterialProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Malzeme Kaydını Sil'),
        content: Text(
          '${usage.materialName} (${formatMaterialQuantity(usage.quantityUsed)} ${usage.materialUnit.label}) '
          'kullanım kaydını silmek istediğinize emin misiniz? Düşülen stok geri eklenecek.',
        ),
        actions: [
          AppButton(
            label: 'Vazgeç',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'Sil',
            variant: AppButtonVariant.destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.removeMaterialUsage(workOrderId, usage.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Malzeme kaydı silindi, stok geri eklendi.'
              : (provider.submitErrorMessage ?? 'Kayıt silinemedi.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${usage.materialName} · ${formatMaterialQuantity(usage.quantityUsed)} ${usage.materialUnit.label}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${usage.recordedByName} · ${formatRelativeTime(usage.createdAt)}',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (canDelete)
          // B2 (dokunma alanı): varsayılan IconButton 48x48 dp dokunma
          // alanını KISITLAYAN constraints/padding override'ı kaldırıldı —
          // ikon görsel olarak küçük kalsa da tıklanabilir alan artık tam
          // 48x48 dp (bkz. widgets/app_button.dart'taki AYNI minimum kural).
          IconButton(
            tooltip: 'Sil',
            icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
            onPressed: () => _confirmDelete(context),
          ),
      ],
    );
  }
}

/// "Malzeme Ekle" alt sayfası: [MaterialPickerField] ile malzeme seçimi +
/// kullanılan miktar girişi + Ekle butonu. Stok yetersizse backend'in net
/// hata mesajı ("Yetersiz stok: mevcut X birim, istenen Y birim") olduğu
/// gibi kırmızı bir uyarı olarak gösterilir.
class _AddMaterialSheet extends StatefulWidget {
  final int workOrderId;
  final String? equipmentTypeHint;
  const _AddMaterialSheet({
    required this.workOrderId,
    required this.equipmentTypeHint,
  });

  @override
  State<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<_AddMaterialSheet> {
  final _quantityController = TextEditingController();
  MaterialItem? _selectedMaterial;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  double? get _parsedQuantity =>
      double.tryParse(_quantityController.text.replaceAll(',', '.'));

  bool get _canSubmit {
    final qty = _parsedQuantity;
    return _selectedMaterial != null &&
        qty != null &&
        qty > 0 &&
        !_isSubmitting;
  }

  Future<void> _submit() async {
    final material = _selectedMaterial;
    final qty = _parsedQuantity;
    if (material == null || qty == null || qty <= 0) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final provider = context.read<MaterialProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.recordMaterialUsage(
      widget.workOrderId,
      material.id,
      qty,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Malzeme kullanımı kaydedildi.')),
      );
    } else {
      setState(
        () => _errorMessage =
            provider.submitErrorMessage ?? 'Malzeme kullanımı kaydedilemedi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Malzeme Ekle',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          MaterialPickerField(
            equipmentTypeHint: widget.equipmentTypeHint,
            onSelected: (material) => setState(() {
              _selectedMaterial = material;
              _errorMessage = null;
            }),
          ),
          if (_selectedMaterial != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText:
                    'Kullanılan Miktar (${_selectedMaterial!.unit.label})',
                isDense: true,
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Ekle',
              icon: Icons.add,
              isLoading: _isSubmitting,
              onPressed: _canSubmit ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Atanan Kişiyi Değiştir" alt sayfası — yalnızca dispeçer/yönetici erişir
/// (bkz. WorkOrderDetailScreen "Değiştir" ikonu). Yalnızca AKTİF
/// teknisyenleri listeler (pasif bir teknisyene yeni iş yüklenmez, backend
/// de bunu ayrıca doğrular — bkz. PATCH /api/workorders/:id/assign).
class _ReassignSheet extends StatefulWidget {
  final WorkOrderDetailProvider provider;
  final int? currentAssignedUserId;
  const _ReassignSheet({
    required this.provider,
    required this.currentAssignedUserId,
  });

  @override
  State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  List<AssignedUser> _technicians = [];
  AssignedUser? _selectedTechnician;
  bool _isLoading = true;
  String? _loadError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final technicians = await ApiService().getUsers(
        roleFilter: 'teknisyen',
        activeOnly: true,
      );
      if (!mounted) return;
      AssignedUser? current;
      for (final t in technicians) {
        if (t.id == widget.currentAssignedUserId) {
          current = t;
          break;
        }
      }
      setState(() {
        _technicians = technicians;
        _selectedTechnician = current;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedTechnician == null) return;
    setState(() => _isSubmitting = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final success = await widget.provider.reassign(_selectedTechnician!.id);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'İş emri ${_selectedTechnician!.name} kişisine atandı.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.provider.errorMessage ?? 'Atama değiştirilemedi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atanan Kişiyi Değiştir',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_loadError != null) ...[
            Text(
              _loadError!,
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Tekrar Dene',
              variant: AppButtonVariant.secondary,
              onPressed: _loadTechnicians,
            ),
          ] else ...[
            DropdownButtonFormField<AssignedUser>(
              initialValue: _selectedTechnician,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'Teknisyen seçin',
                isDense: true,
              ),
              items: _technicians
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) => setState(() => _selectedTechnician = t),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Ata',
                icon: Icons.check,
                isLoading: _isSubmitting,
                onPressed: _selectedTechnician != null ? _submit : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
