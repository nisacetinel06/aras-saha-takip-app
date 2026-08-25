import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../providers/sos_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_button.dart';
import 'sos_sent_screen.dart';

/// Acil Durum (SOS) Modülü — Onay Akışı (Hız ile Kaza Önleme Dengesi).
///
/// Butona basınca DOĞRUDAN göndermek yerine (yanlışlıkla basmaya karşı), tam
/// ekran bir onay katmanı: 3 saniyelik GÖRÜNÜR bir geri sayım + ortada büyük
/// bir İPTAL butonu. Geri sayım bitmeden İPTAL'e basılırsa hiçbir şey
/// gönderilmez (bkz. _cancel) — ekran geri döner, backend'e HİÇ istek atılmaz.
///
/// Konum, geri sayımla PARALEL olarak baştan istenir (bkz. initState): gerçek
/// bir acil durumda geri sayım bitince GPS'in soğuk başlamasından kaynaklanan
/// EK bir gecikme yaşanmasın diye. Bu tasarım, "3 saniyeden fazla gecikme
/// yaratmamalı" kısıtını sağlar — görünür bekleme SÜRESİ 3 sn'dir, ama GPS
/// konum isteği o 3 sn içinde ZATEN tamamlanmış olur (aynı Modül 5'teki
/// isg_report_form_screen.dart izin akışı, bkz. _getCurrentLocation).
class SosConfirmScreen extends StatefulWidget {
  const SosConfirmScreen({super.key});

  @override
  State<SosConfirmScreen> createState() => _SosConfirmScreenState();
}

enum _SosConfirmPhase { countdown, sending, error }

class _SosConfirmScreenState extends State<SosConfirmScreen> {
  static const _countdownSeconds = 3;

  int _secondsLeft = _countdownSeconds;
  Timer? _timer;
  bool _cancelled = false;
  _SosConfirmPhase _phase = _SosConfirmPhase.countdown;
  String? _errorMessage;
  late Future<Position> _locationFuture;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SosConfirmScreen');
    _locationFuture = _getCurrentLocation();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Modül 5'teki (isg_report_form_screen.dart) konum izin akışıyla AYNI
  // desen — GERÇEK cihaz GPS'i, sahte/varsayılan bir konum ASLA gönderilmez.
  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Konum servisleri (GPS) kapalı. Lütfen açıp tekrar deneyin.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Konum izni verilmedi. Acil durum bildirimi gönderebilmek için izin gerekiyor.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Konum izni kalıcı olarak reddedildi. Lütfen ayarlardan izin verin.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  void _onTick(Timer timer) {
    if (_cancelled) {
      timer.cancel();
      return;
    }
    if (_secondsLeft <= 1) {
      timer.cancel();
      setState(() => _secondsLeft = 0);
      _confirmAndSend();
      return;
    }
    setState(() => _secondsLeft -= 1);
  }

  /// Geri sayım bitmeden çağrılırsa: timer durur, HİÇBİR istek atılmadan
  /// ekran kapanır. `_cancelled` bayrağı, tam bu anda (_onTick zaten
  /// _confirmAndSend'i tetiklemişken) bir yarış durumu oluşursa AŞAĞIDAKİ her
  /// `await` sonrası kontrol edilerek gönderimi güvenle durdurur.
  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  Future<void> _confirmAndSend() async {
    if (_cancelled || !mounted) return;
    setState(() => _phase = _SosConfirmPhase.sending);

    try {
      final position = await _locationFuture;
      if (_cancelled || !mounted) return;

      final sosProvider = context.read<SosProvider>();
      final id = await sosProvider.triggerSosAlert(
        lat: position.latitude,
        lng: position.longitude,
      );
      if (_cancelled || !mounted) return;

      if (id != null) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SosSentScreen(alertId: id)),
        );
      } else {
        setState(() {
          _phase = _SosConfirmPhase.error;
          _errorMessage =
              sosProvider.sendErrorMessage ??
              'Acil durum bildirimi gönderilemedi.';
        });
      }
    } catch (e) {
      if (_cancelled || !mounted) return;
      setState(() {
        _phase = _SosConfirmPhase.error;
        _errorMessage = mapExceptionToUserMessage(e);
      });
    }
  }

  void _retry() {
    setState(() {
      _phase = _SosConfirmPhase.countdown;
      _secondsLeft = _countdownSeconds;
      _errorMessage = null;
      _locationFuture = _getCurrentLocation();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.danger(context);
    final onDanger = accessibleOnColor(danger);
    final isSending = _phase == _SosConfirmPhase.sending;
    final isError = _phase == _SosConfirmPhase.error;

    // Sistem geri tuşu/kaydırması da AYNI güvenli iptal yolundan geçmeli —
    // aksi halde kullanıcı geri sayımı "kaçarak" atlatabilir ve backend'e ne
    // olduğu belirsiz bir istek durumu bırakabilirdi.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: danger,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Spacer(),
                Icon(
                  isError ? Icons.error_outline : Icons.warning_rounded,
                  color: onDanger,
                  size: 72,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  isError
                      ? 'BİLDİRİM GÖNDERİLEMEDİ'
                      : 'ACİL DURUM BİLDİRİMİ GÖNDERİLİYOR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onDanger,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isError
                      ? (_errorMessage ?? '')
                      : 'Konumunuz alınıyor ve dispeçer/yöneticinize iletiliyor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onDanger.withValues(alpha: 0.92),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!isError)
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            value: isSending
                                ? null
                                : _secondsLeft / _countdownSeconds,
                            strokeWidth: 8,
                            valueColor: AlwaysStoppedAnimation(onDanger),
                            backgroundColor: onDanger.withValues(alpha: 0.25),
                          ),
                        ),
                        Text(
                          isSending ? '' : '$_secondsLeft',
                          style: TextStyle(
                            color: onDanger,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (isError) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AppButton(
                      label: 'Tekrar Dene',
                      icon: Icons.refresh,
                      color: onDanger,
                      onPressed: _retry,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                // B2 (dokunma alanı): 64dp — kritik/tek eylemli bir ekranda
                // standart 48dp yerine bilinçli olarak büyütüldü (bkz.
                // touch-psychology.md "Critical Actions: 56-64px").
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: onDanger, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    onPressed: isSending ? null : _cancel,
                    child: Text(
                      'İPTAL',
                      style: TextStyle(
                        color: onDanger,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
