import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/feedback_item.dart';
import '../../providers/feedback_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/sticky_form_footer.dart';

/// Öneri / Şikayet Kutusu (Modül 17) — yeni bildirim formu. İSG Bildirimi
/// formunun (screens/isg/isg_report_form_screen.dart) BASİTLEŞTİRİLMİŞ bir
/// kopyası: fotoğraf OPSİYONEL, konum HİÇ YOK (bir öneri/şikayetin GPS
/// konumuyla ilişkisi yok — İSG'nin aksine "nerede" değil "ne" önemli), ama
/// AYNI kategori/açıklama/fotoğraf görsel dili korunur. Tek YENİ alan: Anonim
/// Gönder switch'i.
class SubmitFeedbackScreen extends StatefulWidget {
  const SubmitFeedbackScreen({super.key});

  @override
  State<SubmitFeedbackScreen> createState() => _SubmitFeedbackScreenState();
}

class _SubmitFeedbackScreenState extends State<SubmitFeedbackScreen> {
  final _descriptionController = TextEditingController();
  FeedbackCategory? _selectedCategory;
  File? _photoFile;
  bool _isAnonymous = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SubmitFeedbackScreen');
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _photoFile = File(file.path));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(mapExceptionToUserMessage(e))),
      );
    }
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
            if (_photoFile != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: AppColors.danger(context),
                ),
                title: const Text('Fotoğrafı Kaldır'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _photoFile = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  // İSG'den FARKLI olarak fotoğraf zorunlu değil — yalnızca kategori +
  // açıklama doluysa buton aktif olur (bkz. görev talimatı madde 4).
  bool get _canSubmit =>
      _selectedCategory != null && _descriptionController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<FeedbackProvider>();
    final navigator = Navigator.of(context);

    final success = await provider.submitFeedback(
      description: _descriptionController.text.trim(),
      category: _selectedCategory!,
      isAnonymous: _isAnonymous,
      photo: _photoFile,
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
          'İlgili birime iletildi. En kısa sürede değerlendirilecektir.',
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
    final provider = context.watch<FeedbackProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppTopBar(title: 'Öneri / Şikayet Bildir'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Kategori', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  crossAxisCount: responsiveGridColumns(constraints.maxWidth),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.4,
                  children: FeedbackCategory.values.map((category) {
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
                hintText: 'Önerinizi veya şikayetinizi kısaca açıklayın...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),

            // Anonim Gönder — yeni alan (bkz. sınıf dokümantasyonu). Açıklama
            // metninin HEMEN altında, ayrı bir bölüm başlığı almadan (tek bir
            // ek karar noktası, kategori/açıklama gibi "büyük" bir bölüm
            // değil).
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Anonim olarak gönder',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Adınız yöneticinize gösterilmeyecek',
                          style: AppTextStyles.caption(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isAnonymous,
                    onChanged: (value) => setState(() => _isAnonymous = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Fotoğraf (Opsiyonel)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildPhotoField(scheme),
          ],
        ),
      ),
      bottomNavigationBar: StickyFormFooter(
        child: SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Gönder',
            icon: Icons.send_outlined,
            isLoading: provider.isSubmitting,
            onPressed: _canSubmit ? _submit : null,
          ),
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
                    'Fotoğraf ekleyin (opsiyonel)',
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
}

class _CategoryOption extends StatelessWidget {
  final FeedbackCategory category;
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
