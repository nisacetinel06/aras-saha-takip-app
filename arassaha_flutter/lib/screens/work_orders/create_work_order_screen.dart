import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

/// Bölge seçici için sabit bir konum listesi. Bu, `ARCHITECTURE.md` Bölüm
/// 11.1'deki "kişiler hiçbir yerde sabit kodlanmaz" kuralını İHLAL ETMEZ —
/// burada sabitlenen bir kişi/personel değil, coğrafi referans verisidir
/// (backend seed.js'teki bölge listesiyle aynı sahte-ama-gerçekçi bölgeler).
/// Atanacak TEKNİSYEN listesi ise her zaman GET /api/users?role=teknisyen
/// üzerinden gerçek zamanlı çekilir (bkz. _loadTechnicians).
class _RegionOption {
  final String label;
  final double lat;
  final double lng;
  const _RegionOption(this.label, this.lat, this.lng);
}

const _regionOptions = [
  _RegionOption('Erzurum / Yakutiye / Merkez Mah.', 39.9086, 41.2769),
  _RegionOption('Erzurum / Palandöken / Kültür Mah.', 39.8600, 41.2600),
  _RegionOption('Erzurum / Aziziye / Ilıca Mah.', 39.9700, 41.1900),
  _RegionOption('Erzincan / Merkez / Fatih Mah.', 39.7500, 39.4900),
  _RegionOption('Erzincan / Üzümlü / Bahçeler Mah.', 39.6800, 39.5300),
  _RegionOption('Ağrı / Merkez / Cumhuriyet Mah.', 39.7191, 43.0503),
  _RegionOption('Ağrı / Doğubayazıt / İshakpaşa Mah.', 39.5500, 44.0900),
  _RegionOption('Kars / Merkez / Ortakapı Mah.', 40.6013, 43.0975),
  _RegionOption('Kars / Sarıkamış / Fevzipaşa Mah.', 40.3300, 42.5900),
  _RegionOption('Iğdır / Merkez / Aras Mah.', 39.9167, 44.0448),
  _RegionOption('Iğdır / Tuzluca / Cumhuriyet Mah.', 40.0200, 43.6700),
  _RegionOption('Ardahan / Merkez / Yenidoğan Mah.', 41.1105, 42.7022),
  _RegionOption('Ardahan / Göle / Merkez Mah.', 40.7900, 42.6100),
  _RegionOption('Bayburt / Merkez / Dede Korkut Mah.', 40.2552, 40.2249),
  _RegionOption('Bayburt / Demirözü / Merkez Mah.', 40.1900, 39.9600),
];

/// Yeni İş Emri Oluştur/Ata ekranı (Modül 7 — RBAC). Yalnızca dispeçer/yönetici
/// rolündeki kullanıcılar erişebilir; backend zaten requireRole('dispecer',
/// 'yonetici') ile bunu engeller, ama teknisyen bir şekilde (örn. deep link)
/// bu ekrana gelirse burada da ikinci bir koruma katmanı vardır (bkz. build).
class CreateWorkOrderScreen extends StatefulWidget {
  const CreateWorkOrderScreen({super.key});

  @override
  State<CreateWorkOrderScreen> createState() => _CreateWorkOrderScreenState();
}

class _CreateWorkOrderScreenState extends State<CreateWorkOrderScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  WorkOrderPriority _priority = WorkOrderPriority.normal;
  _RegionOption? _selectedRegion;

  List<AssignedUser> _technicians = [];
  AssignedUser? _selectedTechnician;
  bool _isLoadingTechnicians = true;
  String? _technicianError;

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
      _selectedRegion != null &&
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
        locationName: _selectedRegion!.label,
        lat: _selectedRegion!.lat,
        lng: _selectedRegion!.lng,
        assignedUserId: _selectedTechnician!.id,
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
      appBar: AppBar(title: const Text('Yeni İş Emri Oluştur')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
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
            decoration: const InputDecoration(
              hintText: 'İşin detaylarını açıklayın...',
              alignLabelWithHint: true,
            ),
          ),
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

          Text('Konum / Bölge', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<_RegionOption>(
            initialValue: _selectedRegion,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Bölge seçin', isDense: true),
            items: _regionOptions
                .map((region) => DropdownMenuItem(value: region, child: Text(region.label)))
                .toList(),
            onChanged: (region) => setState(() => _selectedRegion = region),
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
