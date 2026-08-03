import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/description_classification.dart';
import '../../models/equipment.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/equipment_picker_field.dart';

/// Yeni İş Emri Oluştur/Ata ekranı (Modül 7 — RBAC). Yalnızca dispeçer/yönetici
/// rolündeki kullanıcılar erişebilir; backend zaten requireRole('dispecer',
/// 'yonetici') ile bunu engeller, ama teknisyen bir şekilde (örn. deep link)
/// bu ekrana gelirse burada da ikinci bir koruma katmanı vardır (bkz. build).
///
/// KONUM TUTARLILIĞI: Bu formda artık serbest bir "Konum/Bölge" alanı YOKTUR.
/// Konumun tek gerçek kaynağı (single source of truth) her zaman seçilen
/// EKİPMANDIR — kullanıcı önce [EquipmentPickerField] ile bir ekipman arayıp
/// seçer, konum bilgisi (il/ilçe/mahalle) bu seçimden OTOMATİK gelir ve salt
/// okunurdur. Backend de zaten location_name/lat/lng'i istemciden hiç kabul
/// etmez, equipment_id'den türetir (bkz. routes/workOrders.js) — bu form
/// yalnızca aynı ilkeyi UI tarafında da yansıtır; asıl garanti backend'dedir.
class CreateWorkOrderScreen extends StatefulWidget {
  const CreateWorkOrderScreen({super.key});

  @override
  State<CreateWorkOrderScreen> createState() => _CreateWorkOrderScreenState();
}

class _CreateWorkOrderScreenState extends State<CreateWorkOrderScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  WorkOrderPriority _priority = WorkOrderPriority.normal;
  Equipment? _selectedEquipment;

  List<AssignedUser> _technicians = [];
  AssignedUser? _selectedTechnician;
  bool _isLoadingTechnicians = true;
  String? _technicianError;

  bool _isSubmitting = false;
  String? _submitError;

  // Arıza Açıklaması Otomatik Sınıflandırma (Modül 10) — kullanıcı açıklama
  // yazmayı bıraktıktan 800ms sonra (debounce) arka planda öneri istenir.
  // Bu, her tuş vuruşunda istek atmayı önler (gereksiz ağ trafiği/ML servis
  // yükü). Öneri, kullanıcı metni DEĞİŞTİRMEDEN "Yoksay" derse ya da form
  // gönderilene kadar geçerliliğini korur; metin tekrar değişince eskisi
  // temizlenip yeni bir öneri beklenir.
  Timer? _debounceTimer;
  DescriptionClassification? _suggestion;
  bool _isClassifying = false;
  bool _suggestionDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String text) {
    // Metin her değiştiğinde önceki öneri artık güncel açıklamayla ilgili
    // olmayabilir — hemen temizlenir, yeni öneri debounce sonrası gelir.
    setState(() {
      _suggestion = null;
      _suggestionDismissed = false;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () => _classifyDescription(text));
  }

  Future<void> _classifyDescription(String text) async {
    // 3 kelimeden az metin için backend zaten öneri döndürmez (bkz.
    // arassaha-ml/app.py MIN_WORD_COUNT) — burada da aynı kısayolu
    // uygulayıp gereksiz bir ağ isteğini baştan engelliyoruz.
    if (text.trim().split(RegExp(r'\s+')).length < 3) return;
    if (!mounted) return;

    setState(() => _isClassifying = true);
    try {
      final result = await ApiService().classifyDescription(text);
      if (!mounted || _descriptionController.text != text) return;
      setState(() => _suggestion = result.hasSuggestion ? result : null);
    } catch (_) {
      // ML servisi kapalıysa/erişilemezse sessizce yutulur — bu bir
      // yardımcı öneri özelliği, formun geri kalanını engellememeli.
    } finally {
      if (mounted) setState(() => _isClassifying = false);
    }
  }

  void _applySuggestion() {
    if (_suggestion == null) return;
    setState(() {
      // "arıza tipi" work_orders şemasında ayrı bir alan değildir; öneri
      // uygulanınca formdaki mevcut Başlık alanına yazılır (bkz. üstteki
      // model yorumu) — kullanıcı sonradan yine elle değiştirebilir.
      _titleController.text = _suggestion!.suggestedType!.label;
      if (_suggestion!.suggestedPriority != null) {
        _priority = _suggestion!.suggestedPriority!;
      }
      _suggestion = null;
      _suggestionDismissed = true;
    });
  }

  void _dismissSuggestion() {
    setState(() {
      _suggestion = null;
      _suggestionDismissed = true;
    });
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoadingTechnicians = true;
      _technicianError = null;
    });
    try {
      final users = await ApiService().getUsers(roleFilter: 'teknisyen', activeOnly: true);
      setState(() => _technicians = users);
    } catch (e) {
      setState(() => _technicianError = e.toString());
    } finally {
      setState(() => _isLoadingTechnicians = false);
    }
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty &&
      _selectedEquipment != null &&
      _selectedTechnician != null &&
      !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ApiService().createWorkOrder(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
        assignedUserId: _selectedTechnician!.id,
        equipmentId: _selectedEquipment!.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş emri oluşturuldu ve teknisyene atandı.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // İkinci koruma katmanı: bu ekrana normal kullanımda yalnızca Ana
    // Sayfa'daki (rol bazlı gizlenen) "Yeni İş Emri Ata" ile gelinir; ama bir
    // şekilde (örn. state restore, deep link) yetkisiz bir rol buraya
    // ulaşırsa burada da engellenir.
    if (!auth.canCreateWorkOrders) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu ekrana erişim yetkiniz yok.')),
        );
        Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppTopBar(title: 'Yeni İş Emri Oluştur'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          // Mantıksal sıra: önce "hangi ekipman" sorusu cevaplanır, sonra
          // başlık/açıklama girilir — bkz. dosya üstündeki Konum Tutarlılığı notu.
          Text('Ekipman', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          EquipmentPickerField(
            initialValue: _selectedEquipment,
            onSelected: (equipment) => setState(() => _selectedEquipment = equipment),
          ),
          if (_selectedEquipment != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _LocationInfoCard(equipment: _selectedEquipment!),
          ],
          const SizedBox(height: AppSpacing.lg),

          Text('Başlık', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Örn. Trafo Arızası'),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Açıklama', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            onChanged: _onDescriptionChanged,
            decoration: InputDecoration(
              hintText: 'İşin detaylarını açıklayın...',
              alignLabelWithHint: true,
              suffixIcon: _isClassifying
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          if (_suggestion != null && !_suggestionDismissed) ...[
            const SizedBox(height: AppSpacing.sm),
            _ClassificationSuggestionBox(
              suggestion: _suggestion!,
              onApply: _applySuggestion,
              onDismiss: _dismissSuggestion,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          Text('Öncelik', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: WorkOrderPriority.values.map((priority) {
              final selected = _priority == priority;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _PriorityChip(
                    priority: priority,
                    selected: selected,
                    onTap: () => setState(() => _priority = priority),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Atanacak Teknisyen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          _buildTechnicianField(scheme),

          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(child: Text(_submitError!, style: TextStyle(color: scheme.error, fontSize: 13))),
              ],
            ),
          ],

          if (_selectedEquipment == null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lütfen önce bir ekipman seçin.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'İş Emri Oluştur',
              icon: Icons.assignment_add,
              isLoading: _isSubmitting,
              onPressed: _canSubmit ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicianField(ColorScheme scheme) {
    if (_isLoadingTechnicians) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_technicianError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_technicianError!, style: TextStyle(color: scheme.error, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Tekrar Dene', variant: AppButtonVariant.secondary, onPressed: _loadTechnicians),
        ],
      );
    }

    return DropdownButtonFormField<AssignedUser>(
      initialValue: _selectedTechnician,
      isExpanded: true,
      decoration: const InputDecoration(hintText: 'Teknisyen seçin', isDense: true),
      items: _technicians
          .map((user) => DropdownMenuItem(value: user, child: Text(user.name)))
          .toList(),
      onChanged: (user) => setState(() => _selectedTechnician = user),
    );
  }
}

/// Seçilen ekipmandan OTOMATİK gelen, salt okunur konum özeti. Kullanıcı bu
/// bilgiyi elle değiştiremez — açıklayıcı not, "neden değiştiremiyorum"
/// sorusuna baştan yanıt verir (bkz. dosya üstündeki Konum Tutarlılığı notu).
class _LocationInfoCard extends StatelessWidget {
  final Equipment equipment;
  const _LocationInfoCard({required this.equipment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text('Konum Bilgisi', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('${equipment.il} / ${equipment.ilce} / ${equipment.mahalle}', style: TextStyle(color: scheme.onSurface)),
          const SizedBox(height: 6),
          Text(
            'Bu bilgi seçilen ekipmandan otomatik alınıyor.',
            style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final WorkOrderPriority priority;
  final bool selected;
  final VoidCallback onTap;
  const _PriorityChip({required this.priority, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = priorityColor(context, priority);

    return AppCard(
      onTap: onTap,
      backgroundTint: selected ? color : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Center(
        child: Text(
          priority.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Arıza Açıklaması Otomatik Sınıflandırma (Modül 10) — açıklama alanının
/// hemen altında beliren, dikkat çekici ama rahatsız etmeyen öneri kutusu.
/// "(yapay zeka önerisi)" etiketi şeffaflık için bilinçli olarak eklendi —
/// kullanıcı bunun otomatik/tahmini bir öneri olduğunu, bağlayıcı olmadığını
/// bilmeli. Öneri yalnızca bilgi amaçlıdır; "Uygula" denmezse form normal
/// şekilde manuel doldurulmaya devam eder.
class _ClassificationSuggestionBox extends StatelessWidget {
  final DescriptionClassification suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  const _ClassificationSuggestionBox({
    required this.suggestion,
    required this.onApply,
    required this.onDismiss,
  });

  String get _message {
    final typeLabel = suggestion.suggestedType!.label;
    final priority = suggestion.suggestedPriority;
    if (priority == null) {
      return 'Bu açıklama "$typeLabel" ile uyuşuyor gibi görünüyor.';
    }
    return 'Bu açıklama "$typeLabel" ve "${priority.label}" önceliğiyle uyuşuyor gibi görünüyor.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accent(context);

    return AppCard(
      backgroundTint: accent,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _message,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '(yapay zeka önerisi)',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(label: 'Yoksay', variant: AppButtonVariant.text, onPressed: onDismiss),
              const SizedBox(width: AppSpacing.xs),
              AppButton(label: 'Uygula', variant: AppButtonVariant.secondary, onPressed: onApply),
            ],
          ),
        ],
      ),
    );
  }
}
