import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../models/work_order.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/cache_service.dart';
import '../../services/offline_queue_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — Ayarlar ekranı.
///
/// Uygulama tercihlerini (tema, bildirimler) VE çevrimdışı altyapının
/// gözlemlenebilirliğini (önbellek yönetimi, bekleyen senkronizasyon
/// işlemleri) TEK bir ekranda toplar. "Çıkış Yap" BİLEREK burada
/// TEKRARLANMAZ — bu, Profil ekranında (Modül 8) zaten var, tek bir yerde
/// tutarlı olsun diye (bkz. profile_screen.dart).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Ayarlar'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: const [
            _SectionLabel('Görünüm'),
            _ThemeSection(),
            SizedBox(height: AppSpacing.lg),
            _SectionLabel('Bildirimler'),
            _NotificationsSection(),
            SizedBox(height: AppSpacing.lg),
            _SectionLabel('Önbellek Yönetimi'),
            _CacheSection(),
            SizedBox(height: AppSpacing.lg),
            _SectionLabel('Bekleyen İşlemler'),
            _PendingActionsSection(),
            SizedBox(height: AppSpacing.lg),
            _SectionLabel('Hakkında'),
            _AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4),
      child: Text(
        text,
        style: AppTextStyles.headingMedium(color: scheme.onSurface),
      ),
    );
  }
}

/// Görünüm — Açık / Koyu / Cihaza Göre. Modül 2'deki basit güneş/ay
/// toggle'ının (bkz. widgets/app_top_bar.dart ThemeToggleButton) YERİNE
/// geçmez — o hızlı bir kısayol olarak kalır, bu üçüncü (sistem) seçeneği
/// ekler. İkisi de AYNI [ThemeProvider]'ı okur/yazar — tek gerçek kaynak.
class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ThemeOptionTile(
            icon: Icons.light_mode_outlined,
            label: 'Açık',
            selected: themeProvider.mode == ThemeMode.light,
            onTap: () => themeProvider.setMode(ThemeMode.light),
          ),
          const Divider(height: 1),
          _ThemeOptionTile(
            icon: Icons.dark_mode_outlined,
            label: 'Koyu',
            selected: themeProvider.mode == ThemeMode.dark,
            onTap: () => themeProvider.setMode(ThemeMode.dark),
          ),
          const Divider(height: 1),
          _ThemeOptionTile(
            icon: Icons.phone_android_outlined,
            label: 'Cihaza Göre',
            selected: themeProvider.mode == ThemeMode.system,
            onTap: () => themeProvider.setMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

/// Bildirimler — Modül 6'daki polling/yerel bildirimleri açıp kapatır.
/// Kapatılırsa NotificationProvider.stopPolling() ÇAĞRILIR (yalnızca tercih
/// saklanmakla kalmaz) — aksi halde kullanıcı "kapattım" sanırken arka
/// planda polling/yerel bildirim üretmeye devam ederdi.
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return AppCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_outlined),
        title: const Text('Bildirimler'),
        subtitle: const Text(
          'Kapatılırsa yeni iş emri/bildirim kontrolü durur',
        ),
        value: settings.notificationsEnabled,
        onChanged: (value) async {
          await context.read<SettingsProvider>().setNotificationsEnabled(
            value,
          );
          if (!context.mounted) return;
          final notificationProvider = context.read<NotificationProvider>();
          if (value) {
            notificationProvider.startPolling();
          } else {
            notificationProvider.stopPolling();
          }
        },
      ),
    );
  }
}

/// Önbellek Yönetimi — Hive'daki `cache_box`'ı temizler (Modül 17 Okuma
/// Önbelleği). Bekleyen senkronizasyon işlemlerine (`pending_actions_box`)
/// KESİNLİKLE dokunmaz — bkz. OfflineQueueService.clearAll() üstündeki not;
/// kullanıcı "sıfırdan başla" derken gönderilmeyi bekleyen gerçek bir işi
/// kaybetmemeli.
class _CacheSection extends StatelessWidget {
  const _CacheSection();

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Önbelleği Temizle'),
        content: const Text(
          'Çevrimdışı görüntüleme için saklanan tüm veriler silinecek. '
          'Bağlantı olmadan açılan ekranlar bu işlemden sonra boş görünebilir. '
          'Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Temizle',
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await CacheService.clear();
    messenger.showSnackBar(const SnackBar(content: Text('Önbellek temizlendi.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.storage_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Çevrimdışı Önbellek'),
                const SizedBox(height: 2),
                Text(
                  'Sorun yaşarsan sıfırdan başlamak için kullan',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: 'Temizle',
            variant: AppButtonVariant.destructive,
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
    );
  }
}

/// Bekleyen İşlemler — Çevrimdışı Yazma Kuyruğu (Modül 17). Kuyruk
/// OfflineQueueService (bir ChangeNotifier) olduğu için `context.watch` ile
/// otomatik güncellenir: bir işlem senkronize olup kuyruktan silindiği an
/// bu bölüm de otomatik yeniden çizilir, elle bir "yenile" gerekmez.
class _PendingActionsSection extends StatelessWidget {
  const _PendingActionsSection();

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<OfflineQueueService>();
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final scheme = Theme.of(context).colorScheme;
    final pending = queue.pending;

    if (pending.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success(context)),
            const SizedBox(width: AppSpacing.sm + 4),
            const Expanded(child: Text('Bekleyen senkronizasyon işlemi yok')),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_problem_outlined, color: AppColors.warning(context)),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Text(
                  '${pending.length} işlem senkronizasyon bekliyor',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          Column(
            children: [
              for (int i = 0; i < pending.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                _PendingActionRow(action: pending[i]),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: isOnline ? 'Şimdi Senkronize Et' : 'Bağlantı yok',
              icon: Icons.sync,
              isLoading: queue.isProcessing,
              onPressed: isOnline
                  ? () => OfflineQueueService.instance.processQueue()
                  : null,
            ),
          ),
          if (!isOnline) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Bağlantı geldiğinde bu işlemler otomatik gönderilecek.',
              style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingActionRow extends StatelessWidget {
  final PendingAction action;
  const _PendingActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = WorkOrderStatus.fromJson(action.payload['status'] as String);
    final title = action.payload['work_order_title'] as String? ?? 'İş emri';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Durum: ${status.label} · ${formatRelativeTime(action.createdAt)}',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ArasSaha — Aras EDAŞ Staj Projesi',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    final text = info != null
                        ? 'Sürüm ${info.version} (${info.buildNumber})'
                        : 'Sürüm bilgisi alınıyor...';
                    return Text(
                      text,
                      style: AppTextStyles.caption(
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
