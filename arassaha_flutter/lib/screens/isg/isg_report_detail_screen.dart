import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/isg_report.dart';
import '../../providers/isg_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

// bekliyor=turuncu/sarı, incelendi=mavi, çözüldü=yeşil — isg_report_list_screen.dart
// içindeki _statusColor ile aynı eşleme; her ekran kendi küçük kopyasını
// tutar (Ekipman modülündeki liste/detay ekranlarıyla aynı desen).
Color _statusColor(BuildContext context, IsgStatus status) {
  switch (status) {
    case IsgStatus.bekliyor:
      return AppColors.warning(context);
    case IsgStatus.incelendi:
      return AppColors.primary(context);
    case IsgStatus.cozuldu:
      return AppColors.success(context);
  }
}

/// İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — bildirim detay ekranı.
///
/// Fotoğraf, backend'in diskinde gerçekten saklanan bir dosyaya işaret eder
/// (varsa) — bu yüzden `Image.network` ile gösterilir; seed verisindeki
/// bazı eski kayıtların fotoğrafı yoktur (bkz. seed.js yorumu), bu durumda
/// net bir boş durum mesajı gösterilir, kırık resim ikonu değil.
class IsgReportDetailScreen extends StatefulWidget {
  final int reportId;
  const IsgReportDetailScreen({super.key, required this.reportId});

  @override
  State<IsgReportDetailScreen> createState() => _IsgReportDetailScreenState();
}

class _IsgReportDetailScreenState extends State<IsgReportDetailScreen> {
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IsgProvider>().fetchReportDetail(widget.reportId);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(IsgStatus newStatus) async {
    final provider = context.read<IsgProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final success = await provider.updateReportStatus(
      widget.reportId,
      newStatus,
      reviewerNote: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(success ? 'Durum "${newStatus.label}" olarak güncellendi.' : (provider.detailErrorMessage ?? 'Güncellenemedi.')),
      ),
    );
    if (success) _noteController.clear();
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final provider = context.watch<IsgProvider>();
    final report = provider.selectedReport?.id == widget.reportId ? provider.selectedReport : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İSG Bildirim Detayı'),
        actions: [
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (report == null && provider.detailErrorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: AppSpacing.sm + 4),
                    Text(provider.detailErrorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Tekrar Dene',
                      onPressed: () => provider.fetchReportDetail(widget.reportId),
                    ),
                  ],
                ),
              ),
            );
          }

          if (report == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchReportDetail(widget.reportId),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    Icon(report.category.icon, size: 26, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(report.category.label, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    _StatusPill(status: report.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _SectionCard(
                  title: 'Fotoğraf',
                  icon: Icons.photo_outlined,
                  child: _PhotoPreview(photoPath: report.photoPath),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Açıklama',
                  icon: Icons.description_outlined,
                  child: Text(report.description, style: const TextStyle(height: 1.4)),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Konum ve Bildirim Bilgisi',
                  icon: Icons.location_on_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(
                        icon: Icons.place_outlined,
                        label: 'Konum',
                        value: report.locationName?.isNotEmpty == true ? report.locationName! : 'Belirtilmemiş',
                      ),
                      _InfoRow(
                        icon: Icons.map_outlined,
                        label: 'Koordinat',
                        value: '${report.lat.toStringAsFixed(5)}, ${report.lng.toStringAsFixed(5)}',
                        mono: true,
                      ),
                      _InfoRow(
                        icon: Icons.person_outline,
                        label: 'Bildiren',
                        value: report.reportedBy?.name ?? 'Bilinmiyor',
                      ),
                      _InfoRow(
                        icon: Icons.event_outlined,
                        label: 'Bildirim Tarihi',
                        value: _formatDateTime(report.createdAt),
                      ),
                      if (report.reviewedAt != null)
                        _InfoRow(
                          icon: Icons.fact_check_outlined,
                          label: 'İnceleme Tarihi',
                          value: _formatDateTime(report.reviewedAt!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                if (report.reviewerNote?.isNotEmpty == true) ...[
                  _SectionCard(
                    title: 'İnceleme Notu',
                    icon: Icons.notes_outlined,
                    child: Text(report.reviewerNote!, style: const TextStyle(height: 1.4)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                _SectionCard(
                  title: 'Durum Güncelle',
                  icon: Icons.sync_alt,
                  child: _StatusUpdateSection(
                    report: report,
                    noteController: _noteController,
                    onUpdate: _updateStatus,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final String? photoPath;
  const _PhotoPreview({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (photoPath == null || photoPath!.isEmpty) {
      return Container(
        width: double.infinity,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: scheme.onSurfaceVariant, size: 32),
            const SizedBox(height: 6),
            Text('Bu bildirime fotoğraf eklenmemiş.', style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        ApiService.photoUrl(photoPath!),
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 220,
            alignment: Alignment.center,
            color: scheme.surfaceContainerHigh,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          height: 140,
          alignment: Alignment.center,
          color: scheme.surfaceContainerHigh,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant, size: 32),
              const SizedBox(height: 6),
              Text('Fotoğraf yüklenemedi.', style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IsgStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        status.label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
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
          const SizedBox(height: AppSpacing.sm + 4),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;
  const _InfoRow({required this.icon, required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: mono
                ? Text(value, style: AppTextStyles.dataMono(color: scheme.onSurface))
                : Text(value, style: TextStyle(color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// Bekliyor -> İncelendi -> Çözüldü akışı (Modül 1'deki durum güncelleme
/// bölümüyle aynı desen — bkz. work_order_detail_screen.dart).
class _StatusUpdateSection extends StatelessWidget {
  final IsgReport report;
  final TextEditingController noteController;
  final ValueChanged<IsgStatus> onUpdate;
  const _StatusUpdateSection({required this.report, required this.noteController, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IsgProvider>();
    final scheme = Theme.of(context).colorScheme;
    final nextStatus = report.status.nextStatus;

    if (nextStatus == null) {
      return Text(
        'Bu bildirim çözüldü olarak işaretlenmiş, daha ileri bir aşama yok.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    final actionLabel = nextStatus == IsgStatus.incelendi ? 'İncelendi Olarak İşaretle' : 'Çözüldü Olarak İşaretle';
    final actionIcon = nextStatus == IsgStatus.incelendi ? Icons.fact_check_outlined : Icons.check_circle_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mevcut durum: ${report.status.label}'),
        const SizedBox(height: AppSpacing.sm + 4),
        TextField(
          controller: noteController,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'İnceleme notu ekleyin (opsiyonel)...', isDense: true),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: actionLabel,
            icon: actionIcon,
            isLoading: provider.isUpdatingStatus,
            onPressed: () => onUpdate(nextStatus),
          ),
        ),
      ],
    );
  }
}
