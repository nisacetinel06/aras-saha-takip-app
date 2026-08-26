import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../screens/home/module_entries.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'role_badge.dart';
import 'user_avatar.dart';

/// Ana Sayfa'nın hamburger menü paneli (eskiden "Tüm Modüller" butonu + ayrı
/// arama ekranıydı — bkz. module_entries.dart dokümantasyonu). [MainShell]
/// tarafından yalnızca Ana Sayfa sekmesindeyken `endDrawer` olarak takılır;
/// modül listesi TEK kaynaktan ([buildModuleEntries]) beslenir, burada ayrıca
/// kopyalanmaz.
class AppNavigationDrawer extends StatelessWidget {
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  const AppNavigationDrawer({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<UserProvider>().myProfile;
    final entries = buildModuleEntries(auth, onNavigate);
    const categories = ['Operasyon', 'Yönetim', 'Sistem'];

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            _DrawerHeader(
              name: auth.currentUser?.name ?? '',
              role: auth.currentUser?.role ?? '',
              roleLabel: auth.roleLabel,
              sicilNo: myProfile?.sicilNo,
              photoPath: myProfile?.photoPath,
              initials:
                  myProfile?.initials ??
                  (auth.currentUser?.name.isNotEmpty == true
                      ? auth.currentUser!.name[0].toUpperCase()
                      : '?'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                children: [
                  for (final category in categories)
                    if (entries.any((e) => e.category == category)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.xs,
                        ),
                        child: Text(
                          category,
                          style:
                              AppTextStyles.caption(
                                color: scheme.onSurfaceVariant,
                              ).copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ),
                      for (final entry in entries.where(
                        (e) => e.category == category,
                      ))
                        _DrawerModuleTile(entry: entry),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final String name;
  final String role;
  final String roleLabel;
  final String? sicilNo;
  final String? photoPath;
  final String initials;

  const _DrawerHeader({
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.sicilNo,
    required this.photoPath,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(
            photoPath: photoPath,
            initials: initials,
            role: role,
            radius: 26,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTextStyles.headingMedium(color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                RoleBadge(role: role, label: roleLabel),
                if (sicilNo != null && sicilNo!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Sicil No: $sicilNo',
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerModuleTile extends StatelessWidget {
  final ModuleEntry entry;
  const _DrawerModuleTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = entry.color(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: entry.screenBuilder));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: isDark ? 0.28 : 0.15),
                child: Icon(entry.icon, size: 18, color: color),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      entry.subtitle,
                      style: AppTextStyles.caption(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
