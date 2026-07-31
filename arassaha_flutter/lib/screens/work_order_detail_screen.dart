import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/work_order_detail_provider.dart';
import '../services/api_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/status_badge.dart';
import 'equipment/equipment_detail_screen.dart';

class WorkOrderDetailScreen extends StatelessWidget {
  final int workOrderId;

  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkOrderDetailProvider(workOrderId)..loadDetail(),
      child: const _WorkOrderDetailBody(),
    );
  }
}

class _WorkOrderDetailBody extends StatelessWidget {
  const _WorkOrderDetailBody();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('İş Emri Detayı'),
        actions: [
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<WorkOrderDetailProvider>(
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
                    Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(provider.errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    AppButton(label: 'Tekrar Dene', onPressed: provider.loadDetail),
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
                Text(workOrder.title, style: Theme.of(context).textTheme.headlineMedium),
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
                      _InfoRow(icon: Icons.place_outlined, text: workOrder.locationName),
                      const SizedBox(height: 4),
                      _InfoRow(
                        icon: Icons.map_outlined,
                        text: 'Lat: ${workOrder.lat.toStringAsFixed(5)}, Lng: ${workOrder.lng.toStringAsFixed(5)}',
                        mono: true,
                      ),
                      const SizedBox(height: 10),
                      AppButton(
                        label: 'Haritada Aç',
                        icon: Icons.directions_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _openInMaps(context, workOrder.lat, workOrder.lng),
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
                              workOrder.assignedUser?.name ?? 'Henüz atanmadı',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (workOrder.assignedUser != null)
                              Text(
                                workOrder.assignedUser!.role,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            if (workOrder.equipmentRef.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              // Modül 4 (Ekipman) ile gerçek bağlantı: equipmentId
                              // doluysa kod, Ekipman Detay ekranına giden bir
                              // bağlantı olarak gösterilir.
                              workOrder.equipmentId != null
                                  ? InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => EquipmentDetailScreen(equipmentId: workOrder.equipmentId!),
                                        ),
                                      ),
                                      child: _EquipmentChip(code: workOrder.equipmentRef),
                                    )
                                  : _EquipmentChip(code: workOrder.equipmentRef),
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
                          onPressed: () => _showReassignSheet(context, workOrder),
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
              ],
            ),
          );
        },
      ),
    );
  }

  void _showReassignSheet(BuildContext context, WorkOrder workOrder) {
    final provider = context.read<WorkOrderDetailProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ReassignSheet(provider: provider, currentAssignedUserId: workOrder.assignedUser?.id),
    );
  }

  Future<void> _openInMaps(BuildContext context, double lat, double lng) async {
    final messenger = ScaffoldMessenger.of(context);
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    try {
      final opened = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
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

  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
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
        color: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Text(text, style: const TextStyle(height: 1.4)),
    );
  }
}

class _EquipmentChip extends StatelessWidget {
  final String code;
  const _EquipmentChip({required this.code});

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
          Icon(Icons.qr_code_2_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(code, style: AppTextStyles.dataMono(color: scheme.onSurfaceVariant).copyWith(fontSize: 12)),
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
      child: Text(_initials, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold)),
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
              ? Text(text, style: AppTextStyles.dataMono(color: scheme.onSurface))
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
  WorkOrderStatus.yolda: _NextStatusAction('Yolda', Icons.directions_car_outlined),
  WorkOrderStatus.sahada: _NextStatusAction('Sahadayım', Icons.location_on_outlined),
  WorkOrderStatus.cozuldu: _NextStatusAction('Çözüldü', Icons.check_circle_outline),
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
                  SnackBar(content: Text('Durum "${nextStatus.label}" olarak güncellendi.')),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(provider.errorMessage ?? 'Durum güncellenemedi.')),
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

    final XFile? file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;

    final success = await provider.addPhoto(File(file.path));
    if (success) {
      messenger.showSnackBar(const SnackBar(content: Text('Fotoğraf eklendi.')));
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Fotoğraf eklenemedi.')),
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
            child: Text('Henüz fotoğraf eklenmemiş.', style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: workOrder.photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
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
                      child: Icon(Icons.image_not_supported_outlined, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Fotoğraf Ekle',
          icon: Icons.add_a_photo_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: provider.isUpdating ? null : () => _showSourcePicker(context),
        ),
      ],
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
  const _ReassignSheet({required this.provider, required this.currentAssignedUserId});

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
      final technicians = await ApiService().getUsers(roleFilter: 'teknisyen', activeOnly: true);
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
        SnackBar(content: Text('İş emri ${_selectedTechnician!.name} kişisine atandı.')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(widget.provider.errorMessage ?? 'Atama değiştirilemedi.')),
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
          Text('Atanan Kişiyi Değiştir', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
          else if (_loadError != null) ...[
            Text(_loadError!, style: TextStyle(color: scheme.error, fontSize: 13)),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Tekrar Dene', variant: AppButtonVariant.secondary, onPressed: _loadTechnicians),
          ] else ...[
            DropdownButtonFormField<AssignedUser>(
              initialValue: _selectedTechnician,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Teknisyen seçin', isDense: true),
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
