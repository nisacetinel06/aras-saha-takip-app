import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/isg_report.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/isg_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/sticky_form_footer.dart';

/// İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — yeni bildirim formu.
///
/// Diğer modüllerden farklı olarak burada fotoğraf VE konum baştan itibaren
/// gerçektir: fotoğraf gerçekten backend'e yüklenir, konum cihazın gerçek
/// GPS'inden (geolocator) okunur — hiçbir sahte/varsayılan değer gönderilmez.
class IsgReportFormScreen extends StatefulWidget {
  const IsgReportFormScreen({super.key});

  @override
  State<IsgReportFormScreen> createState() => _IsgReportFormScreenState();
}

class _IsgReportFormScreenState extends State<IsgReportFormScreen> {
  final _descriptionController = TextEditingController();
  IsgCategory? _selectedCategory;
  File? _photoFile;

  double? _lat;
  double? _lng;
  bool _isGettingLocation = false;
  String? _locationError;
  bool _locationPermanentlyDenied = false;
  bool _locationServiceDisabled = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('IsgReportFormScreen');
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _photoFile = File(file.path));
  }

  void _showPhotoSourcePicker() {
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
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
      _locationPermanentlyDenied = false;
      _locationServiceDisabled = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationServiceDisabled = true;
          _locationError =
              'Konum servisleri (GPS) kapalı. Lütfen açıp tekrar deneyin.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(
            () => _locationError =
                'Konum izni verilmedi. Bildirim gönderebilmek için izin gerekiyor.',
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationPermanentlyDenied = true;
          _locationError =
              'Konum izni kalıcı olarak reddedildi. Lütfen ayarlardan izin verin.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (e) {
      setState(() => _locationError = 'Konum alınamadı: $e');
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  bool get _canSubmit =>
      _selectedCategory != null &&
      _descriptionController.text.trim().isNotEmpty &&
      _photoFile != null &&
      _lat != null &&
      _lng != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final messenger = ScaffoldMessenger.of(context);

    // Modül 17 — KAPSAM BİLİNÇLİ OLARAK SINIRLI: fotoğraf yükleme gerektiren
    // işlemler (bu form dahil) çevrimdışı yazma kuyruğuna HİÇ ALINMAZ; büyük
    // bir dosyayı güvenilir şekilde kuyruklayıp senkronize etmek (kısmi
    // yükleme, bozuk dosya, disk alanı) tam bir offline-first mimarinin
    // çözmesi gereken ayrı bir problemdir — bkz. OfflineQueueService
    // üstündeki kapsam notu. Kullanıcı çevrimdışıyken NET bir mesajla
    // engellenir; istek backend'e hiç atılmaz, "gönderildi sanma" riski
    // oluşmaz.
    if (!ConnectivityProvider.instance.isOnline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Bu işlem internet bağlantısı gerektirir — fotoğraflı bildirimler '
            'çevrimdışı kuyruğa alınmaz. Lütfen bağlantı geldiğinde tekrar deneyin.',
          ),
        ),
      );
      return;
    }

    final provider = context.read<IsgProvider>();
    final navigator = Navigator.of(context);

    final success = await provider.submitReport(
      description: _descriptionController.text.trim(),
      category: _selectedCategory!,
      lat: _lat!,
      lng: _lng!,
      photo: _photoFile!,
    );

    if (!mounted) return;

    if (!success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.submitErrorMessage ?? 'Bildirim gönderilemedi.',
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.check_circle_outline,
          color: AppColors.success(dialogContext),
          size: 40,
        ),
        title: const Text('Bildiriminiz alındı'),
        content: const Text(
          'İlgili birime iletildi. En kısa sürede incelenecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IsgProvider>();
    final scheme = Theme.of(context).colorScheme;
    final isOnline = context.watch<ConnectivityProvider>().isOnline;

    return Scaffold(
      appBar: const AppTopBar(title: 'İSG Bildirimi Oluştur'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Kategori', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            // C1 (responsive grid): bkz. home_screen.dart modül ızgarasındaki
            // aynı not.
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  crossAxisCount: responsiveGridColumns(constraints.maxWidth),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.4,
                  children: IsgCategory.values.map((category) {
                    return _CategoryOption(
                      category: category,
                      selected: _selectedCategory == category,
                      onTap: () => setState(() => _selectedCategory = category),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Açıklama', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Gördüğünüz durumu kısaca açıklayın...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Fotoğraf', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            _buildPhotoField(scheme),
            const SizedBox(height: AppSpacing.lg),

            Text('Konum', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            _buildLocationField(scheme),
          ],
        ),
      ),
      bottomNavigationBar: StickyFormFooter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modül 17 — fotoğraflı bu işlem çevrimdışı kuyruğa alınmadığı
            // için kullanıcı butona basmadan ÖNCE net bir uyarı görür.
            if (!isOnline) ...[
              Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 14, color: AppColors.warning(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Çevrimdışısınız — bu işlem internet bağlantısı gerektirir.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Bildirimi Gönder',
                icon: Icons.send_outlined,
                isLoading: provider.isSubmitting,
                onPressed: (_canSubmit && isOnline) ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoField(ColorScheme scheme) {
    return AppCard(
      onTap: _showPhotoSourcePicker,
      child: _photoFile == null
          ? Row(
              children: [
                Icon(Icons.add_a_photo_outlined, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Fotoğraf ekleyin (zorunlu)',
                    style: AppTextStyles.bodyMedium(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _photoFile!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Fotoğraf eklendi. Değiştirmek için dokunun.',
                    style: AppTextStyles.bodyMedium(color: scheme.onSurface),
                  ),
                ),
                Icon(Icons.check_circle, color: AppColors.success(context)),
              ],
            ),
    );
  }

  Widget _buildLocationField(ColorScheme scheme) {
    final hasLocation = _lat != null && _lng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: hasLocation ? 'Konumu Yenile' : 'Mevcut Konumu Al',
            icon: Icons.my_location_outlined,
            variant: hasLocation
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            isLoading: _isGettingLocation,
            onPressed: _getCurrentLocation,
          ),
        ),
        if (hasLocation) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: AppColors.success(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Konum alındı: ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (_locationError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _locationError!,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            ],
          ),
          if (_locationPermanentlyDenied) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Ayarları Aç',
              variant: AppButtonVariant.secondary,
              icon: Icons.settings_outlined,
              onPressed: Geolocator.openAppSettings,
            ),
          ] else if (_locationServiceDisabled) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Konum Ayarlarını Aç',
              variant: AppButtonVariant.secondary,
              icon: Icons.settings_outlined,
              onPressed: Geolocator.openLocationSettings,
            ),
          ],
        ],
      ],
    );
  }
}

class _CategoryOption extends StatelessWidget {
  final IsgCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryOption({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;

    return AppCard(
      onTap: onTap,
      backgroundTint: selected ? color : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            category.icon,
            size: 20,
            color: selected ? color : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              category.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : scheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
