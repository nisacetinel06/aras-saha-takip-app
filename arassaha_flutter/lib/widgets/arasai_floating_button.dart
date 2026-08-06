import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../screens/assistant/assistant_chat_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

const double _kButtonSize = 60;
const double _kEdgeMargin = 12;

/// ArasAI — uygulama genelinde her sekmede görünen, sürüklenebilir yuvarlak
/// asistan başlatıcısı. [MainShell]'in Scaffold'ının ÜSTÜNE bir Stack içinde
/// yerleştirilir (bkz. main_shell.dart), böylece hangi sekmede olursa olsun
/// erişilebilir kalır — Ana Sayfa modül ızgarasındaki "AI Asistan" kartından
/// BAĞIMSIZ, ikinci (ve daha keşfedilebilir) bir giriş noktasıdır.
///
/// Sürükleme sırasında parmağı birebir takip eder (ham [Positioned]); bırakınca
/// en yakın kenara (sol/sağ) yumuşak bir geçişle yapışır ([AnimatedPositioned])
/// — bkz. Messenger "chat head" deseni. Dikey eksende yalnızca AppBar/alt
/// navigasyonun üzerine binmeyecek şekilde sınırlandırılır.
class ArasAiFloatingButton extends StatefulWidget {
  /// MainShell'in sekme geçiş callback'i — asistan sohbetinde "beni X
  /// sayfasına götür" dendiğinde kullanılmak üzere [AssistantChatScreen]'e
  /// olduğu gibi iletilir (bkz. main_shell.dart _navigateToTab).
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter})?
  onNavigateToTab;

  const ArasAiFloatingButton({super.key, this.onNavigateToTab});

  @override
  State<ArasAiFloatingButton> createState() => _ArasAiFloatingButtonState();
}

class _ArasAiFloatingButtonState extends State<ArasAiFloatingButton> {
  Offset? _position;
  bool _isDragging = false;
  bool _showWelcome = false;
  bool _welcomeDismissed = false;

  @override
  void initState() {
    super.initState();
    // "İlk açıldığında bir süre konuşma baloncuğu çıksın" — MainShell (yani
    // oturum) ilk kurulduğunda bir kereliğine gösterilir, birkaç saniye sonra
    // kendiliğinden kapanır. Tasarımı bozmaması için mevcut ekran içeriğinin
    // ÜSTÜNDE, ayrı bir overlay baloncuğu olarak gösterilir — hiçbir sabit
    // layout alanı kaplamaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showWelcome = true);
      Future.delayed(const Duration(seconds: 7), () {
        if (mounted && !_welcomeDismissed) {
          setState(() => _showWelcome = false);
        }
      });
    });
  }

  _Bounds _bounds(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    // AppBar (~kToolbarHeight) ve NavigationBar (M3 varsayılan ~80) üzerine
    // binmesin diye dikey sınır bu ikisini dışarıda bırakır.
    final top = padding.top + kToolbarHeight + _kEdgeMargin;
    final bottom = size.height - padding.bottom - 80 - _kEdgeMargin;
    final left = _kEdgeMargin;
    final right = size.width - _kButtonSize - _kEdgeMargin;
    return _Bounds(
      left: left,
      top: top,
      right: right < left ? left : right,
      bottom: bottom < top ? top : bottom,
    );
  }

  void _dismissWelcome() {
    if (!_showWelcome) return;
    setState(() {
      _showWelcome = false;
      _welcomeDismissed = true;
    });
  }

  void _openAssistant() {
    _dismissWelcome();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AssistantChatScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds(context);
    _position ??= Offset(bounds.right, bounds.bottom);
    final pos = Offset(
      _position!.dx.clamp(bounds.left, bounds.right),
      _position!.dy.clamp(bounds.top, bounds.bottom),
    );

    final button = _DragHandle(
      onDragStart: () => setState(() => _isDragging = true),
      onDragUpdate: (delta) {
        setState(() {
          _position = Offset(
            (_position!.dx + delta.dx).clamp(bounds.left, bounds.right),
            (_position!.dy + delta.dy).clamp(bounds.top, bounds.bottom),
          );
        });
      },
      onDragEnd: () {
        // Bırakınca en yakın yatay kenara yasla — sürüklenebilir ama
        // ekranın ortasında asılı kalıp içeriği kapatmasın.
        final screenWidth = MediaQuery.of(context).size.width;
        final center = _position!.dx + _kButtonSize / 2;
        final snappedLeft = center < screenWidth / 2;
        setState(() {
          _isDragging = false;
          _position = Offset(
            snappedLeft ? bounds.left : bounds.right,
            _position!.dy,
          );
        });
      },
      onTap: _openAssistant,
    );

    final buttonWidget = _isDragging
        ? Positioned(left: pos.dx, top: pos.dy, child: button)
        : AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            left: pos.dx,
            top: pos.dy,
            child: button,
          );

    return Stack(
      children: [
        buttonWidget,
        if (_showWelcome)
          _WelcomeBubble(
            anchor: pos,
            buttonSize: _kButtonSize,
            onDismiss: _dismissWelcome,
          ),
      ],
    );
  }
}

class _Bounds {
  final double left;
  final double top;
  final double right;
  final double bottom;
  const _Bounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

/// Sürükleme + dokunma algısını ayrıştıran ortak buton gövdesi. Küçük bir
/// hareket toleransı ([kTouchSlop] varsayılanı `GestureDetector` zaten
/// uygular) sayesinde tek bir dokunuş sürükleme olarak algılanmaz, `onTap`
/// normal şekilde tetiklenir.
class _DragHandle extends StatelessWidget {
  final VoidCallback onDragStart;
  final void Function(Offset delta) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onTap;

  const _DragHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent(context);
    return GestureDetector(
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (details) => onDragUpdate(details.delta),
      onPanEnd: (_) => onDragEnd(),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black45,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: _kButtonSize,
            height: _kButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, AppColors.primary(context)],
              ),
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: accessibleOnColor(accent),
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// İlk açılışta bir süre görünen karşılama konuşma baloncuğu. Sayfa
/// düzenine hiçbir sabit alan eklemez — [ArasAiFloatingButton]'ın Stack'i
/// içinde, butonun hemen üstünde YÜZEN bir overlay'dir; kapanınca (zaman
/// aşımı veya dokunma ile) geride hiçbir iz bırakmaz.
class _WelcomeBubble extends StatelessWidget {
  final Offset anchor;
  final double buttonSize;
  final VoidCallback onDismiss;

  const _WelcomeBubble({
    required this.anchor,
    required this.buttonSize,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final bubbleWidth = (screenSize.width - 2 * _kEdgeMargin).clamp(
      0.0,
      280.0,
    );

    final rightFromEdge = screenSize.width - anchor.dx - buttonSize;
    final maxRight = screenSize.width - bubbleWidth - _kEdgeMargin;
    final bubbleRight = rightFromEdge.clamp(_kEdgeMargin, maxRight);
    final bubbleBottom = screenSize.height - anchor.dy + 12;

    return Positioned(
      right: bubbleRight,
      bottom: bubbleBottom,
      width: bubbleWidth,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              shadowColor: Colors.black38,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ArasAI',
                            style: AppTextStyles.bodyMedium(
                              color: AppColors.accent(context),
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '👋 Merhaba, ben ArasAsistan. ArasSaha uygulamasıyla ilgili sorularınızı yanıtlayabilir, ekipman, iş emri, İSG bildirimleri ve uygulama kullanımı konusunda size yardımcı olabilirim.',
                            style: AppTextStyles.bodyMedium(
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: onDismiss,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.xs,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Konuşma baloncuğu kuyruğu — butona doğru işaret eder.
            Padding(
              padding: EdgeInsets.only(
                right: (bubbleWidth - buttonSize / 2).clamp(
                  8.0,
                  bubbleWidth - 20,
                ),
              ),
              child: Transform.rotate(
                angle: 0.785398, // 45°
                child: Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: -8),
                  color: scheme.surfaceContainerLowest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
