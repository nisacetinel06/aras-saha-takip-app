import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/work_order.dart';
import '../providers/work_order_detail_provider.dart';
import '../services/api_service.dart';
import '../widgets/bento_card.dart';
import '../widgets/status_badge.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('İş Emri Detayı')),
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
                    ElevatedButton(onPressed: provider.loadDetail, child: const Text('Tekrar Dene')),
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
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _openInMaps(context, workOrder.lat, workOrder.lng),
                        icon: const Icon(Icons.directions_outlined, size: 18),
                        label: const Text('Haritada Aç'),
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
                              _EquipmentChip(code: workOrder.equipmentRef),
                            ],
                          ],
                        ),
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
    return BentoCard(
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
          Text(code, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500)),
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
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _StatusUpdateSection extends StatelessWidget {
  final WorkOrder workOrder;
  const _StatusUpdateSection({required this.workOrder});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkOrderDetailProvider>();
    final nextStatus = workOrder.status.nextStatus;
    final scheme = Theme.of(context).colorScheme;

    if (nextStatus == null) {
      return Text(
        'Bu iş emri çözülmüş durumda, daha ileri bir aşama yok.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text('Mevcut durum: ${workOrder.status.label}'),
        ),
        ElevatedButton.icon(
          onPressed: provider.isUpdating
              ? null
              : () async {
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
          icon: provider.isUpdating
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                )
              : const Icon(Icons.arrow_forward),
          label: Text('${nextStatus.label}\'a Geçir'),
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
        OutlinedButton.icon(
          onPressed: provider.isUpdating ? null : () => _showSourcePicker(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Fotoğraf Ekle'),
        ),
      ],
    );
  }
}
