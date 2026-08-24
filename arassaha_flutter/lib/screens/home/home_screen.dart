import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../models/dashboard_summary.dart';
import '../../models/maintenance_recommendation.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/completed_work_orders_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../providers/manager_message_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/onboarding/coach_mark_style.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../admin/user_edit_screen.dart';
import '../dashboard_screen.dart';
import '../equipment/qr_scanner_screen.dart';
import '../isg/isg_report_form_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../map/map_screen.dart';
import '../messages/manager_messages_screen.dart';
import '../messages/send_manager_message_screen.dart';
import '../work_orders/create_work_order_screen.dart';
import 'completed_work_orders_section.dart';

const _weekdays = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _formatToday() {
  final now = DateTime.now();
  return '${now.day} ${_months[now.month - 1]} ${now.year}, ${_weekdays[now.weekday - 1]}';
}

/// Ana Sayfa (Hub) — v3: "öne çıkanlar" tek ızgarası, GÖRSEL OLARAK ayırt
/// edilemeyen iki farklı niyeti (aksiyon başlatma vs. gezinme) tek bir kart
/// stiline sıkıştırıyordu. Şimdi ikisi BİLİNÇLİ olarak ayrı, birbirine
/// benzemeyen bölümler:
///
///   [Karşılama — kart/kenarlık YOK, büyük SAHA logosu]
///   [Özet şerit — 2-3 sayı]
///   [Hızlı İşlemler — dolu mavi, yatay kaydırmalı "aksiyon başlat" kartları]
///   [Çabuk Erişim — ince kenarlıklı, nötr "bir yere git" kartları]
///
/// Eskiden bu listenin altında bir "Tüm Modüller" butonu vardı; artık tüm
/// modüllere erişim, yalnızca bu sekmedeyken görünen bir hamburger menü
/// panelinden ([AppNavigationDrawer], bkz. main_shell.dart) sağlanıyor —
/// modül listesinin tek kaynağı home/module_entries.dart.
///
/// Kullanıcı bir bakışta "bu bana bir şey YAPTIRIR" (Hızlı İşlemler, dolu
/// renk) ile "bu beni bir yere GÖTÜRÜR" (Çabuk Erişim, çizgisel/nötr)
/// arasındaki farkı ayırt edebilmeli — bkz. UI denetimi Bölüm A. İŞ MANTIĞI
/// DEĞİŞMEDİ, yalnızca hangi eylemin hangi bölümde göründüğü ve görsel dili.
class HomeScreen extends StatefulWidget {
  /// MainShell'e "şu sekmeye, isteğe bağlı şu statü filtresiyle geç" demek
  /// için kullanılır. Sekme sırası: 0 Ana Sayfa, 1 İş Emirleri, 2 ArasAI,
  /// 3 Profil (bkz. main_shell.dart) — Harita ve Panel sekme değil, bu
  /// ekrandan doğrudan push edilir.
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  // Ana Sayfa Turu (bkz. main_shell.dart _MainShellState dokümantasyonu):
  // bu anahtarlar MainShell'de TANIMLANIR (turun diğer adımları — hamburger
  // menü, Profil sekmesi — bu ekranın DIŞINDadır, o yüzden tek sahip orası)
  // ve buraya geçirilir; HomeScreen yalnızca KENDİ 3 hedefini (karşılama,
  // Hızlı İşlemler, ArasAI) bu anahtarlarla Showcase'e sarmalar.
  final GlobalKey onboardingWelcomeKey;
  final GlobalKey onboardingQuickActionsKey;
  final GlobalKey onboardingArasAiKey;

  const HomeScreen({
    super.key,
    required this.onNavigate,
    required this.onboardingWelcomeKey,
    required this.onboardingQuickActionsKey,
    required this.onboardingArasAiKey,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('HomeScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchSummary();
      // "Önleyici Bakım Öner" Hızlı İşlemi yalnızca BEKLEYEN bir öneri
      // varsa görünür (bkz. build) — bu yüzden sayıyı bilmek için yönetici
      // ise önerileri baştan çekiyoruz. Diğer roller bu isteği hiç atmaz.
      if (context.read<AuthProvider>().isYonetici) {
        context.read<MaintenanceProvider>().fetchRecommendations(
          statusFilter: 'onerildi',
        );
      }
      // "Tamamlanan İş Emirlerim" bölümü yalnızca teknisyene gösterilir (bkz.
      // build) — diğer roller bu isteği hiç atmaz.
      if (context.read<AuthProvider>().isTeknisyen) {
        context.read<CompletedWorkOrdersProvider>().loadInitial();
      }
      // "Yöneticiden Mesajlar" Çabuk Erişim kartındaki okunmamış rozeti için
      // — yönetici bu mesajların ALICISI olmadığı için (bkz. sınıf
      // dokümantasyonu, TEK YÖNLÜ model) bu isteği hiç atmaz.
      if (!context.read<AuthProvider>().isYonetici) {
        context.read<ManagerMessageProvider>().fetchMyMessages();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dashboardProvider = context.watch<DashboardProvider>();
    final summary = dashboardProvider.summary;
    final unreadMessageCount = context.watch<ManagerMessageProvider>().unreadCount;
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<UserProvider>().myProfile;
    final pendingMaintenanceCount = auth.isYonetici
        ? context
              .watch<MaintenanceProvider>()
              .recommendations
              .where(
                (r) => r.status == MaintenanceRecommendationStatus.onerildi,
              )
              .length
        : 0;

    final acilCount = summary?.priorityBreakdown[WorkOrderPriority.acil] ?? 0;

    void goToCreateWorkOrder() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateWorkOrderScreen()));

    void goToMap() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MapScreen()));

    void goToDashboard() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(onNavigate: widget.onNavigate),
      ),
    );

    void goToMaintenance() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MaintenanceRecommendationsScreen(),
      ),
    );

    void goToQrScanner() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrScannerScreen()));

    void goToIsgForm() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const IsgReportFormScreen()));

    void goToAddUser() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UserEditScreen()));

    void goToSendManagerMessage() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SendManagerMessageScreen()),
    );

    void goToManagerMessages() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManagerMessagesScreen()),
    );

    // Hızlı İşlemler: kullanıcının doğrudan bir eylem BAŞLATACAĞI girişler
    // (bir şey oluşturma/gönderme) — role göre SABİT liste.
    final List<_ActionData> quickActions;
    if (auth.isYonetici) {
      quickActions = [
        if (pendingMaintenanceCount > 0)
          _ActionData(
            icon: Icons.build_circle_outlined,
            label: 'Önleyici Bakım Öner',
            onTap: goToMaintenance,
          ),
        _ActionData(
          icon: Icons.person_add_alt_outlined,
          label: 'Yeni Kullanıcı Ekle',
          onTap: goToAddUser,
        ),
        _ActionData(
          icon: Icons.campaign_outlined,
          label: 'Çalışanlara Mesaj Gönder',
          onTap: goToSendManagerMessage,
        ),
      ];
    } else if (auth.isDispecer) {
      quickActions = [
        _ActionData(
          icon: Icons.add_circle_outline,
          label: 'Yeni İş Emri Ata',
          onTap: goToCreateWorkOrder,
        ),
      ];
    } else {
      quickActions = [
        _ActionData(
          icon: Icons.report_problem_outlined,
          label: 'Arıza Bildir',
          onTap: goToQrScanner,
        ),
        _ActionData(
          icon: Icons.health_and_safety_outlined,
          label: 'İSG Bildirimi Gönder',
          onTap: goToIsgForm,
        ),
      ];
    }

    // Çabuk Erişim: kullanıcının bir ekranı/listeyi GÖRÜNTÜLEMEK için gittiği
    // girişler — role göre SABİT liste. Not: "Bildirimler" BİLİNÇLİ olarak
    // burada YOK — AppTopBar'daki zil zaten aynı işleve tek giriş noktası
    // (bkz. UI denetimi B.4).
    final List<_AccessData> quickAccess;
    if (auth.isYonetici) {
      quickAccess = [
        _AccessData(
          icon: Icons.bar_chart_outlined,
          title: 'Panel',
          subtitle: 'Grafikler ve özet göstergeler',
          onTap: goToDashboard,
        ),
        _AccessData(
          icon: Icons.assignment_outlined,
          title: 'İş Emirleri',
          subtitle: summary != null ? '${summary.openCount} Açık' : null,
          onTap: () => widget.onNavigate(1),
        ),
        _AccessData(
          icon: Icons.build_circle_outlined,
          title: 'Bakım Planlama',
          subtitle: 'Kestirimci bakım önerileri',
          onTap: goToMaintenance,
        ),
        _AccessData(
          icon: Icons.smart_toy_outlined,
          title: 'ArasAI',
          subtitle: 'Sorularını doğal dilde sor',
          onTap: () => widget.onNavigate(2),
        ),
      ];
    } else if (auth.isDispecer) {
      quickAccess = [
        _AccessData(
          icon: Icons.assignment_outlined,
          title: 'Tüm İş Emirleri',
          subtitle: summary != null ? '${summary.openCount} Açık' : null,
          onTap: () => widget.onNavigate(1),
        ),
        _AccessData(
          icon: Icons.location_on_outlined,
          title: 'Harita',
          subtitle: 'Konum görünümü',
          onTap: goToMap,
        ),
        _AccessData(
          icon: Icons.mail_outline,
          title: 'Yöneticiden Mesajlar',
          badgeCount: unreadMessageCount,
          onTap: goToManagerMessages,
        ),
        _AccessData(
          icon: Icons.smart_toy_outlined,
          title: 'ArasAI',
          subtitle: 'Sorularını doğal dilde sor',
          onTap: () => widget.onNavigate(2),
        ),
      ];
    } else {
      quickAccess = [
        _AccessData(
          icon: Icons.assignment_outlined,
          title: 'Görevlerim',
          subtitle: summary != null ? '${summary.openCount} Açık' : null,
          onTap: () => widget.onNavigate(1),
        ),
        _AccessData(
          icon: Icons.location_on_outlined,
          title: 'Harita',
          subtitle: 'Konum görünümü',
          onTap: goToMap,
        ),
        _AccessData(
          icon: Icons.mail_outline,
          title: 'Yöneticiden Mesajlar',
          badgeCount: unreadMessageCount,
          onTap: goToManagerMessages,
        ),
        _AccessData(
          icon: Icons.smart_toy_outlined,
          title: 'ArasAI',
          subtitle: 'Sorularını doğal dilde sor',
          onTap: () => widget.onNavigate(2),
        ),
      ];
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: context.read<DashboardProvider>().fetchSummary,
          child: ListView(
            // UI denetimi B.1: üstteki gereksiz boşluk azaltıldı (md -> sm),
            // karşılama artık kenarlıksız/kartsız, doğrudan sayfa zemininde.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl + 56,
            ),
            children: [
              Showcase(
                key: widget.onboardingWelcomeKey,
                // Yalnızca "İleri"/"Geç"/"Geri" butonları ilerletsin — hedefe
                // veya zemine (barrier) dokunmanın varsayılan olarak turu
                // sessizce ilerletmesi (showcaseview'ın kütüphane
                // davranışı) SAHADA, eldivenli/kazara bir dokunuşla turun
                // fark edilmeden atlanmasına yol açardı.
                disableDefaultTargetGestures: true,
                title: 'Merhaba!',
                description:
                    'Burada rolünüzü ve günlük özet bilgilerinizi görürsünüz.',
                tooltipBackgroundColor: CoachMarkStyle.background(context),
                textColor: CoachMarkStyle.foreground(context),
                tooltipBorderRadius: CoachMarkStyle.borderRadius,
                titleTextStyle: CoachMarkStyle.title(context),
                descTextStyle: CoachMarkStyle.description(context),
                tooltipActionConfig: CoachMarkStyle.actionConfig,
                tooltipActions: CoachMarkStyle.homeTourActions(
                  context,
                  isFirstStep: true,
                ),
                targetPadding: const EdgeInsets.all(AppSpacing.sm),
                child: _GreetingRow(
                  name: auth.currentUser?.name ?? '',
                  role: auth.currentUser?.role ?? '',
                  roleLabel: auth.roleLabel,
                  photoPath: myProfile?.photoPath,
                  initials:
                      myProfile?.initials ??
                      (auth.currentUser?.name.isNotEmpty == true
                          ? auth.currentUser!.name[0].toUpperCase()
                          : '?'),
                  onAvatarTap: () => widget.onNavigate(3),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _StatsRow(
                summary: summary,
                errorMessage: dashboardProvider.errorMessage,
                onRetry: dashboardProvider.fetchSummary,
                acilCount: acilCount,
                isTeknisyen: auth.isTeknisyen,
                isYonetici: auth.isYonetici,
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Hızlı İşlemler',
                style: AppTextStyles.headingMedium(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.sm),
              Showcase(
                key: widget.onboardingQuickActionsKey,
                disableDefaultTargetGestures: true,
                title: 'Hızlı İşlemler',
                description:
                    'Arıza bildirmek veya iş emri oluşturmak gibi sık '
                    'kullandığınız işlemlere buradan tek dokunuşla '
                    'ulaşırsınız.',
                tooltipBackgroundColor: CoachMarkStyle.background(context),
                textColor: CoachMarkStyle.foreground(context),
                tooltipBorderRadius: CoachMarkStyle.borderRadius,
                titleTextStyle: CoachMarkStyle.title(context),
                descTextStyle: CoachMarkStyle.description(context),
                tooltipActionConfig: CoachMarkStyle.actionConfig,
                tooltipActions: CoachMarkStyle.homeTourActions(
                  context,
                  isFirstStep: false,
                ),
                child: SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: quickActions.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, i) =>
                        _QuickActionCard(data: quickActions[i]),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Çabuk Erişim',
                style: AppTextStyles.headingMedium(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GridView.count(
                    crossAxisCount: responsiveGridColumns(constraints.maxWidth),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisExtent: 68,
                    children: [
                      // ArasAI girişi, her rolün quickAccess listesinde AYNI
                      // sabit başlıkla ('ArasAI') var olduğu için Turun 3.
                      // adımını buraya, string eşleşmesiyle sarmalıyoruz —
                      // ayrı bir özel liste/index tutmaktan daha az kırılgan.
                      for (final a in quickAccess)
                        if (a.title == 'ArasAI')
                          Showcase(
                            key: widget.onboardingArasAiKey,
                            disableDefaultTargetGestures: true,
                            title: 'ArasAI',
                            description:
                                "'Erzurum'da kaç açık arıza var?' gibi "
                                'soruları buraya yazarak anında cevap '
                                'alabilirsiniz.',
                            tooltipBackgroundColor: CoachMarkStyle.background(
                              context,
                            ),
                            textColor: CoachMarkStyle.foreground(context),
                            tooltipBorderRadius: CoachMarkStyle.borderRadius,
                            titleTextStyle: CoachMarkStyle.title(context),
                            descTextStyle: CoachMarkStyle.description(
                              context,
                            ),
                            tooltipActionConfig: CoachMarkStyle.actionConfig,
                            tooltipActions: CoachMarkStyle.homeTourActions(
                              context,
                              isFirstStep: false,
                            ),
                            child: _QuickAccessTile(data: a),
                          )
                        else
                          _QuickAccessTile(data: a),
                    ],
                  );
                },
              ),

              // Yalnızca teknisyen: dispeçer/yönetici için "tamamladığım iş
              // emirleri" kavramı yok (onlar iş emri ÇÖZMEZ, atar/izler) —
              // bkz. UI denetimi/görev bağlamı.
              if (auth.isTeknisyen) ...[
                const SizedBox(height: AppSpacing.lg),
                const CompletedWorkOrdersSection(),
              ],
            ],
          ),
        ),
      ),
      // "Yeni İş Emri Ata" yalnızca dispeçer/yönetici içindir — teknisyen bu
      // FAB'ı hiç görmez (backend zaten POST /api/workorders'ı requireRole
      // ile engelliyor, bkz. routes/workOrders.js).
      floatingActionButton: auth.canCreateWorkOrders
          ? FloatingActionButton.extended(
              onPressed: goToCreateWorkOrder,
              icon: const Icon(Icons.add),
              label: const Text('Yeni İş Emri Ata'),
            )
          : null,
    );
  }
}

/// Karşılama satırı: avatar + isim + rol rozeti + bugünün tarihi + SAHA
/// logosu — BİLEREK herhangi bir Card/kenarlık İÇİNDE değil, doğrudan sayfa
/// zemininde (bkz. UI denetimi B.1). Logo, önceki sürüme göre belirgin
/// şekilde büyütüldü ve daraltılmış iç boşlukla (bkz. UI denetimi B.2) daha
/// çok yer kaplıyor — Ana Sayfa'daki TEK logo burası (bkz. main_shell.dart,
/// üst bar Ana Sayfa sekmesinde logo göstermez). Avatara dokununca Profil
/// sekmesine (index 3) geçilir.
class _GreetingRow extends StatelessWidget {
  final String name;
  final String role;
  final String roleLabel;
  final String? photoPath;
  final String initials;
  final VoidCallback onAvatarTap;

  const _GreetingRow({
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.photoPath,
    required this.initials,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: UserAvatar(
            photoPath: photoPath,
            initials: initials,
            role: role,
            radius: 28,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merhaba, $name',
                style: AppTextStyles.headingMedium(color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              RoleBadge(role: role, label: roleLabel),
              const SizedBox(height: 6),
              Text(
                _formatToday(),
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // UI denetimi B.2: yükseklik 26 -> 42 (~%60 büyütme), iç boşluk
        // daraltıldı — logo artık belirgin şekilde daha büyük ve net.
        const AppLogo(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        ),
      ],
    );
  }
}

/// Özet şerit: SADECE 2-3 sayı — "açık iş/görev sayısı", "bugün tamamlanan"
/// her role, "kritik uyarı sayısı" yalnızca yöneticiye.
class _StatsRow extends StatelessWidget {
  final DashboardSummary? summary;
  final String? errorMessage;
  final VoidCallback onRetry;
  final int acilCount;
  final bool isTeknisyen;
  final bool isYonetici;

  const _StatsRow({
    required this.summary,
    required this.errorMessage,
    required this.onRetry,
    required this.acilCount,
    required this.isTeknisyen,
    required this.isYonetici,
  });

  @override
  Widget build(BuildContext context) {
    if (summary == null && errorMessage != null) {
      return AppCard(
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Özet bilgiler yüklenemedi',
          subtitle: errorMessage!,
          onPrimaryAction: onRetry,
          primaryActionLabel: 'Tekrar Dene',
          primaryActionVariant: AppButtonVariant.secondary,
        ),
      );
    }

    if (summary == null) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.assignment_outlined,
            value: '${summary!.openCount}',
            label: isTeknisyen ? 'Açık Görevlerim' : 'Açık İş Emirleri',
            color: AppColors.primary(context),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.check_circle_outline,
            value: '${summary!.resolvedTodayCount}',
            label: 'Bugün Tamamlanan',
            color: AppColors.success(context),
          ),
        ),
        if (isYonetici) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatTile(
              icon: Icons.warning_amber_rounded,
              value: '$acilCount',
              label: 'Kritik Uyarı',
              color: AppColors.danger(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                  maxLines: 2,
                ),
              ),
              Icon(icon, size: 18, color: scheme.onSurface),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            value,
            style: AppTextStyles.headingMedium(
              color: scheme.onSurface,
            ).copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}

class _ActionData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionData({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Hızlı İşlemler kartı: dolu (filled) birincil mavi zemin, ikon ÜSTTE +
/// metin ALTTA — "bir şey yapmaya davet eden", dikkat çekici bir görsel dil.
/// Çabuk Erişim'in ([_QuickAccessTile]) ince/nötr stilinden BİLİNÇLİ olarak
/// tamamen farklı (bkz. UI denetimi Bölüm A) — kullanıcı bir bakışta bunun
/// bir aksiyon başlatıcı olduğunu anlamalı.
class _QuickActionCard extends StatelessWidget {
  final _ActionData data;
  const _QuickActionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(context);
    final onPrimary = accessibleOnColor(primary);

    return SizedBox(
      width: 132,
      child: Material(
        color: primary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: data.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + 2,
              vertical: AppSpacing.sm + 4,
            ),
            // FittedBox: iki satıra saran uzun etiketlerde (örn. "Yeni
            // Kullanıcı Ekle") font metriklerine bağlı birkaç piksellik
            // taşmayı GARANTİ olarak önler — sabit yükseklikli kartın
            // içeriği gerekirse hafifçe küçültülür, asla taşmaz.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(data.icon, color: onPrimary, size: 26),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    data.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessData {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Bildirim ziliyle (bkz. widgets/app_top_bar.dart NotificationBellButton)
  /// AYNI desende bir okunmamış-sayısı rozeti — 0 iken hiç gösterilmez.
  final int badgeCount;

  const _AccessData({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });
}

/// Çabuk Erişim kartı: ince kenarlıklı (outline), nötr/beyaz zemin, ikon
/// SOLDA + metin SAĞDA — sade/çizgisel bir görsel dil. [_QuickActionCard]'ın
/// dolu/renkli stilinden BİLİNÇLİ olarak farklı: bu bir gezinme linki,
/// "bir şey yapmaz", yalnızca bir ekrana götürür.
class _QuickAccessTile extends StatelessWidget {
  final _AccessData data;
  const _QuickAccessTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 4,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(data.icon, size: 20, color: scheme.onSurfaceVariant),
                  if (data.badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger(context),
                            borderRadius: BorderRadius.circular(
                              AppRadius.pill,
                            ),
                            border: Border.all(
                              color: scheme.surfaceContainerLowest,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            data.badgeCount > 9 ? '9+' : '${data.badgeCount}',
                            style: TextStyle(
                              color: accessibleOnColor(
                                AppColors.danger(context),
                              ),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle!,
                        style: AppTextStyles.caption(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
