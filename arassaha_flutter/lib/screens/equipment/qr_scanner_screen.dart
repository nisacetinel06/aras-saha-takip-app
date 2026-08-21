import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/equipment_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_prefs_service.dart';
import '../../theme/app_spacing.dart';
import 'equipment_detail_screen.dart';

/// Ekipman / Envanter (Modül 4) — kamera ile QR tarama ekranı.
///
/// Bir kod okunduğunda otomatik olarak GET /api/equipment/qr/:qrCode isteği
/// atılır; eşleşme bulunursa Ekipman Detay ekranına geçilir. Eşleşme
/// bulunamazsa (404) kamera KAPATILMAZ — üstte kısa süreli bir uyarı
/// gösterilip taramaya devam edilir (aynı barkodun art arda tetiklenmesini
/// önlemek için `_isProcessing` kısa bir süre için taramayı durdurur).
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  String? _transientMessage;

  // Bağlamsal İlk-Karşılaşma İpucu (bkz. sınıf dokümantasyonu "Ana Sayfa
  // Turu + Bağlamsal İpuçları" tasarım kararı) — burada BİLİNÇLİ olarak
  // showcaseview KULLANILMAZ: risk rozetinin aksine (equipment_detail_screen.dart)
  // vurgulanacak KÜÇÜK bir hedef widget yok, kamera görüntüsünün TAMAMI
  // "hedef" — bu yüzden ekranın zaten sahip olduğu banner deseniyle
  // (_LoadingBanner/_WarningBanner) birebir aynı, basit bir tam-genişlik
  // bilgi banner'ı yeterli ve daha tutarlı.
  bool _showFirstUseHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('QrScannerScreen');
    _maybeShowFirstUseHint();
  }

  Future<void> _maybeShowFirstUseHint() async {
    final hasSeen = await OnboardingPrefsService.hasSeenQrScannerHint();
    if (hasSeen || !mounted) return;
    setState(() => _showFirstUseHint = true);
    _hintTimer = Timer(const Duration(seconds: 4), _dismissFirstUseHint);
  }

  void _dismissFirstUseHint() {
    _hintTimer?.cancel();
    OnboardingPrefsService.setHasSeenQrScannerHint();
    if (!mounted || !_showFirstUseHint) return;
    setState(() => _showFirstUseHint = false);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || capture.barcodes.isEmpty) return;

    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _transientMessage = null;
    });

    final provider = context.read<EquipmentProvider>();
    final equipment = await provider.fetchEquipmentByQr(code);

    if (!mounted) return;

    if (equipment != null) {
      // Kullanıcı başarıyla bir tarama yaptı — artık QR akışını bildiğini
      // göstermiştir, ipucu bir daha karşısına çıkmasın (4 saniyelik
      // zamanlayıcıyı beklemeden bayrağı hemen işaretle).
      OnboardingPrefsService.setHasSeenQrScannerHint();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipmentId: equipment.id),
        ),
      );
      return;
    }

    setState(() {
      _transientMessage = 'Bu koda ait kayıt bulunamadı, tekrar deneyin.';
    });

    // Kullanıcının uyarıyı görebilmesi için kısa bir süre bekleyip taramaya devam et.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _transientMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('QR Kod Tara'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'El feneri',
            icon: const Icon(Icons.flash_on_outlined),
            color: Colors.white,
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _PermissionDeniedView(error: error),
          ),
          const _ScanFrameOverlay(),
          if (_showFirstUseHint && !_isProcessing && _transientMessage == null)
            Positioned(
              top: AppSpacing.lg,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: GestureDetector(
                onTap: _dismissFirstUseHint,
                child: const _InfoBanner(
                  message:
                      'Bir ekipmanın QR kodunu kameraya gösterin, otomatik '
                      'olarak tanınacaktır.',
                ),
              ),
            ),
          if (_isProcessing)
            const Positioned(
              top: AppSpacing.lg,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _LoadingBanner(),
            ),
          if (_transientMessage != null)
            Positioned(
              top: AppSpacing.lg,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _WarningBanner(message: _transientMessage!),
            ),
        ],
      ),
    );
  }
}

/// Ortadaki tarama çerçevesi overlay'i — kullanıcıya QR'ı nereye
/// hizalayacağını gösterir, işlevsel bir kısıtlama uygulamaz.
class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Ekipman aranıyor...',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Bağlamsal ilk-karşılaşma ipucu banner'ı — [_WarningBanner] ile AYNI
/// görsel dil (siyah zemin, yuvarlak köşe), yalnızca ikon/anlam farklı
/// (bilgi mavisi vs. uyarı sarısı) ki kullanıcı ikisini birbirinden ayırt
/// edebilsin. Dokununca (bkz. çağıran taraftaki GestureDetector) hemen
/// kapanır; aksi halde birkaç saniye sonra kendiliğinden kaybolur.
class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.lightBlueAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kamera izni reddedildiğinde (ya da cihazda kamera desteklenmediğinde)
/// gösterilir; kullanıcıyı manuel kod girişine (bir önceki ekrana dönerek) yönlendirir.
class _PermissionDeniedView extends StatelessWidget {
  final MobileScannerException error;
  const _PermissionDeniedView({required this.error});

  bool get _isPermissionDenied =>
      error.errorCode == MobileScannerErrorCode.permissionDenied;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _isPermissionDenied
                    ? 'Kamera izni verilmedi. QR tarayabilmek için ayarlardan kamera iznini açabilir ya da bir önceki ekrandan kodu manuel olarak girebilirsiniz.'
                    : 'Kamera kullanılamıyor. Lütfen kodu manuel olarak girin.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Manuel Kod Girişine Dön'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
