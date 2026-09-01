import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../models/dashboard_summary.dart';
import '../../models/maintenance_recommendation.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/completed_work_orders_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../providers/manager_message_provider.dart';
import '../../providers/qr_generation_provider.dart';
import '../../providers/sos_provider.dart';
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
import '../../widgets/sos_button.dart';
import '../../widgets/user_avatar.dart';
import '../admin/user_edit_screen.dart';
import '../dashboard_screen.dart';
import '../equipment/qr_generation_screen.dart';
import '../equipment/qr_scanner_screen.dart';
import '../feedback/feedback_list_screen.dart';
import '../isg/isg_report_form_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../map/map_screen.dart';
import '../messages/manager_messages_screen.dart';
import '../messages/send_manager_message_screen.dart';
import '../profile/my_performance_screen.dart';
import '../sos/sos_alerts_screen.dart';
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
      // Acil Durum (SOS) Modülü — "SOS Uyarıları" kartındaki aktif bildirim
      // rozeti için (bkz. build). Yalnızca dispeçer/yönetici bu isteği atar;
      // teknisyen bu ekranı hiç görmediği için (backend zaten
      // requireRole('dispecer', 'yonetici') ile korur) gereksiz bir istek atılmaz.
      final auth = context.read<AuthProvider>();
      if (auth.isYonetici || auth.isDispecer) {
        context.read<SosProvider>().fetchActiveAlerts();
      }
      // "QR Kod Üret" Çabuk Erişim kartındaki basılmamış-etiket rozeti için
      // — yalnızca yönetici bu kartı görür (bkz. build), diğer roller bu
      // isteği hiç atmaz.
      if (auth.isYonetici) {
        context.read<QrGenerationProvider>().fetchUnprintedCount();
      }
      // "Öneri/Şikayet" Çabuk Erişim kartındaki bekleyen-sayısı rozeti için
      // — yalnızca yönetici bu rozeti görür (bkz. build, GET /api/feedback
      // teknisyen/dispeçer için zaten yalnızca KENDİ bildirimlerini
      // döndürüyor, bu yüzden onlara ayrı bir "bekleyen" rozeti anlamlı
      // değil — bkz. görev talimatı madde 7).
      if (auth.isYonetici) {
        context.read<FeedbackProvider>().fetchPendingCount();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();
    final summary = dashboardProvider.summary;
    final unreadMessageCount = context
        .watch<ManagerMessageProvider>()
        .unreadCount;
    final sosActiveCount = context.watch<SosProvider>().activeCount;
    final unprintedQrCount =
        context.watch<QrGenerationProvider>().unprintedCount ?? 0;
    final pendingFeedbackCount =
        context.watch<FeedbackProvider>().pendingCount ?? 0;
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

    void goToSendManagerMessage() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SendManagerMessageScreen()));

    void goToManagerMessages() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManagerMessagesScreen()));

    void goToSosAlerts() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SosAlertsScreen()));

    void goToQrGeneration() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrGenerationScreen()));

    void goToMyPerformance() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyPerformanceScreen()));

    void goToFeedbackList() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FeedbackListScreen()));

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
          icon: Icons.qr_code_2,
          title: 'QR Kod Üret',
          subtitle: 'Basılmamış ekipman etiketleri',
          badgeCount: unprintedQrCount,
          onTap: goToQrGeneration,
        ),
        // Öneri / Şikayet Kutusu (Modül 17) — yönetici TÜM bildirimleri
        // görür (bkz. routes/feedback.js GET /), bu yüzden burada TEK rol
        // için anlamlı olan bekleyen-sayısı rozetini taşır (bkz. görev
        // talimatı madde 7, initState'teki fetchPendingCount).
        _AccessData(
          icon: Icons.feedback_outlined,
          title: 'Öneri / Şikayet',
          subtitle: 'Çalışan bildirimlerini incele',
          badgeCount: pendingFeedbackCount,
          onTap: goToFeedbackList,
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
        // Dispeçer SADECE KENDİ gönderdiği öneri/şikayetleri görür (bkz.
        // routes/feedback.js GET /) — bu yüzden rozet YOK, yalnızca yönetici
        // versiyonunda (yukarısı) bekleyen sayısı anlamlıdır.
        _AccessData(
          icon: Icons.feedback_outlined,
          title: 'Öneri / Şikayet',
          subtitle: 'Öneri veya şikayet bildir',
          onTap: goToFeedbackList,
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
        // Performansım (Modül 16) — yalnızca teknisyen görünümünde: dispeçer/
        // yönetici iş emri ÇÖZMEZ (atar/izler), bu yüzden "tamamladığım iş"
        // kavramı yalnızca teknisyen için anlamlı (bkz. build() altındaki
        // CompletedWorkOrdersSection ile AYNI rol gerekçesi).
        _AccessData(
          icon: Icons.bar_chart_outlined,
          title: 'Performansım',
          subtitle: 'Tamamlama özetin ve trendin',
          onTap: goToMyPerformance,
        ),
        // Öneri / Şikayet Kutusu (Modül 17) — teknisyen SADECE KENDİ
        // gönderdiklerini görür (bkz. routes/feedback.js GET /), dispeçer
        // versiyonuyla AYNI gerekçeyle rozet YOK.
        _AccessData(
          icon: Icons.feedback_outlined,
          title: 'Öneri / Şikayet',
          subtitle: 'Öneri veya şikayet bildir',
          onTap: goToFeedbackList,
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
                style: AppTextStyles.caption(
                  color: AppColors.textSecondary(context),
                ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
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
                    itemBuilder: (context, i) => SizedBox(
                      width: 132,
                      child: AppButton(
                        variant: AppButtonVariant.compactAction,
                        icon: quickActions[i].icon,
                        label: quickActions[i].label,
                        onPressed: quickActions[i].onTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Çabuk Erişim',
                style: AppTextStyles.caption(
                  color: AppColors.textSecondary(context),
                ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Acil Durum (SOS) Modülü — SADECE dispeçer/yönetici (bildirimi
              // ALAN taraf). Bu, SosButton (gerçek tek-dokunuş tetikleyici,
              // sayfanın TEK dolu-kırmızı öğesi) ile AYNI dolu-blok stilini
              // kullanıyordu — ama bu kart yalnızca SosAlertsScreen'e giden
              // bir GEZİNME linki, bir aksiyon tetiklemiyor. İki dolu-kırmızı
              // blok aynı sayfada aynı ağırlıkta durunca kırmızının anlamı
              // sulanıyordu. Artık _QuickAccessTile ile AYNI kart dilini
              // (AppCard) kullanıyor; aktif bildirim varken sol şerit + hafif
              // kırmızı ton + küçük rozetle işaretleniyor, yokken diğer
              // Çabuk Erişim kartlarından ayırt edilemiyor.
              if (auth.isYonetici || auth.isDispecer) ...[
                _SosAlertsAccessCard(
                  activeCount: sosActiveCount,
                  onTap: goToSosAlerts,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
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
                            descTextStyle: CoachMarkStyle.description(context),
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

              // Acil Durum (SOS) Modülü — sayfanın EN ALTINDA, kendi başına
              // duran bir şerit (bkz. widgets/sos_button.dart). BİLİNÇLİ
              // olarak TÜM rollere gösterilir: backend POST /api/sos-alerts
              // hiçbir rol kısıtlaması UYGULAMAZ ("her rol acil durum
              // bildirebilmeli", bkz. routes/sosAlerts.js) — bu UI kararı
              // backend'in izin modeliyle tutarlı tutuldu.
              const SizedBox(height: AppSpacing.lg),
              const SosButton(),
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

/// Özet şerit kartı: ortalanmış içerik, ÜSTTE büyük sayı, ALTTA küçük etiket
/// — referans düzenle birebir (bkz. görev talimatı madde 3). İkon (metrik
/// rengiyle) sayının üstünde, küçük bir ipucu olarak kalır; sayı/etiket
/// sırası ESKİDEN tersti (etiket+ikon üstte, sayı altta), buradaki tek
/// değişiklik BU sıralama — veri/renk mantığı aynı (bkz. _StatsRow).
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppTextStyles.headingMedium(
              color: scheme.onSurface,
            ).copyWith(fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTextStyles.caption(
              color: AppColors.textSecondary(context),
            ),
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

/// Acil Durum (SOS) Modülü — bkz. yukarısı build() içindeki kullanım notu.
///
/// BİLİNÇLİ olarak diğer TÜM Çabuk Erişim kartlarıyla (_QuickAccessTile) AYNI
/// kart dilini (AppCard, `flat: true`) konuşur — bir aksiyon tetiklemez,
/// yalnızca SosAlertsScreen'e götürür. Tek fark, aktif bir bildirim varken
/// kartın AppCard'ın zaten var olan "durum şeridi" mekanizmasıyla (bkz.
/// app_card.dart) kırmızıya işaretlenmesi.
class _SosAlertsAccessCard extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _SosAlertsAccessCard({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = AppColors.danger(context);
    final hasActive = activeCount > 0;
    final accentColor = hasActive ? danger : scheme.onSurfaceVariant;

    return AppCard(
      flat: true,
      onTap: onTap,
      statusStripeColor: hasActive ? danger : null,
      backgroundTint: hasActive ? danger : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      child: Row(
        children: [
          Icon(Icons.sos_outlined, color: accentColor, size: 24),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SOS Uyarıları',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  hasActive
                      ? '$activeCount aktif acil durum bildirimi'
                      : 'Aktif bildirim yok',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (hasActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: danger,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: scheme.surfaceContainerLowest,
                  width: 1.5,
                ),
              ),
              child: Text(
                activeCount > 9 ? '9+' : '$activeCount',
                style: TextStyle(
                  color: accessibleOnColor(danger),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
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

/// Çabuk Erişim kartı: [AppCard]'ın `flat: true` varyantı (ince kenarlıklı,
/// gölgesiz, nötr zemin) — ikon SOLDA + metin ORTADA + sağ ok SAĞDA, sade/
/// çizgisel bir görsel dil. [AppButtonVariant.compactAction]'ın dolu/renkli
/// stilinden BİLİNÇLİ olarak farklı: bu bir gezinme linki, "bir şey yapmaz",
/// yalnızca bir ekrana götürür.
class _QuickAccessTile extends StatelessWidget {
  final _AccessData data;
  const _QuickAccessTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      flat: true,
      onTap: data.onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm,
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
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: scheme.surfaceContainerLowest,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        data.badgeCount > 9 ? '9+' : '${data.badgeCount}',
                        style: TextStyle(
                          color: accessibleOnColor(AppColors.danger(context)),
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
          // Referans düzen madde 5: sağda küçük bir sağ ok ikonu — önceki
          // sürümde YOKTU, "bu bir yere götürür" ipucunu tamamlıyor.
          Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
