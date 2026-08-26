import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/work_order.dart' show AssignedUser;
import '../../providers/manager_message_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/error_mapper.dart';
import '../../utils/role_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/sticky_form_footer.dart';
import 'sent_messages_screen.dart';

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — yönetici görünümü, yeni mesaj
/// oluşturma. SADECE yönetici bu ekrana yönlendirilir (bkz. home_screen.dart,
/// module_entries.dart rol filtreleri) — backend de POST /api/manager-messages'ı
/// requireRole('yonetici') ile ayrıca korur.
class SendManagerMessageScreen extends StatefulWidget {
  const SendManagerMessageScreen({super.key});

  @override
  State<SendManagerMessageScreen> createState() =>
      _SendManagerMessageScreenState();
}

class _SendManagerMessageScreenState extends State<SendManagerMessageScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isLoadingCandidates = true;
  String? _candidatesErrorMessage;
  List<AssignedUser> _candidates = [];

  final Set<int> _selectedIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SendManagerMessageScreen');
    _loadCandidates();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoadingCandidates = true;
      _candidatesErrorMessage = null;
    });
    try {
      // Alıcı adayları: aktif teknisyen/dispeçerler — bu modülün kavramsal
      // modeli "yönetici -> çalışan" olduğu için yönetici rolü hiç listelenmez
      // (bkz. sınıf dokümantasyonu). Yönetici için zenginleştirilmiş yanıt
      // (bkz. routes/users.js FULL_FIELDS) `il` alanını da içerir — "Şu
      // İldeki Herkes" kısayolu bu alana dayanır.
      final users = await ApiService().getUsers(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _candidates = users.where((u) => u.role != 'yonetici').toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _candidatesErrorMessage = mapExceptionToUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoadingCandidates = false);
    }
  }

  List<AssignedUser> get _filteredCandidates {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _candidates;
    return _candidates
        .where((u) => u.name.toLowerCase().contains(query))
        .toList();
  }

  /// Adaylar arasında BOŞ olmayan, tekrarsız il değerleri — "Şu İldeki
  /// Herkes" kısayol çipleri buradan üretilir. Uygulamada sabit kodlanmış bir
  /// il listesi yok (bkz. providers/manager_message_provider.dart notu),
  /// yalnızca GERÇEKTEN o ile atanmış çalışanlar varsa bir çip gösterilir.
  List<String> get _availableIller {
    final set = <String>{};
    for (final u in _candidates) {
      if (u.il != null && u.il!.trim().isNotEmpty) set.add(u.il!.trim());
    }
    final list = set.toList()..sort();
    return list;
  }

  void _selectAllTeknisyen() {
    setState(() {
      _selectedIds.addAll(
        _candidates.where((u) => u.role == 'teknisyen').map((u) => u.id),
      );
    });
  }

  void _selectAllInIl(String il) {
    setState(() {
      _selectedIds.addAll(
        _candidates.where((u) => u.il == il).map((u) => u.id),
      );
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  bool get _canSubmit =>
      _contentController.text.trim().isNotEmpty &&
      _selectedIds.isNotEmpty &&
      !context.read<ManagerMessageProvider>().isSending;

  Future<void> _submit() async {
    final provider = context.read<ManagerMessageProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final recipientCount = _selectedIds.length;

    final success = await provider.sendMessage(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      content: _contentController.text.trim(),
      recipientUserIds: _selectedIds.toList(),
    );

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text('Mesaj $recipientCount kişiye gönderildi.')),
      );
      Navigator.of(context).pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.sendErrorMessage ?? 'Mesaj gönderilemedi.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSending = context.watch<ManagerMessageProvider>().isSending;

    return Scaffold(
      appBar: AppTopBar(
        title: 'Çalışanlara Mesaj Gönder',
        extraActions: [
          IconButton(
            tooltip: 'Gönderilen Mesajlar',
            icon: const Icon(Icons.outgoing_mail),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SentMessagesScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            Text(
              'Başlık (opsiyonel)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Örn. Bakım Duyurusu',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('İçerik', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _contentController,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Çalışanlara iletmek istediğiniz mesajı yazın...',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Alıcılar',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (_selectedIds.isNotEmpty)
                  Text(
                    '${_selectedIds.length} seçildi',
                    style: AppTextStyles.caption(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildRecipientPicker(),
          ],
        ),
      ),
      bottomNavigationBar: StickyFormFooter(
        child: SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Gönder',
            icon: Icons.send_outlined,
            isLoading: isSending,
            onPressed: _canSubmit ? _submit : null,
          ),
        ),
      ),
    );
  }

  Widget _buildRecipientPicker() {
    if (_isLoadingCandidates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_candidatesErrorMessage != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Çalışanlar yüklenemedi',
        subtitle: _candidatesErrorMessage!,
        onPrimaryAction: _loadCandidates,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hızlı kısayollar — "Tüm Teknisyenler" ve gerçekten en az bir
        // çalışana atanmış her il için bir "X'teki Tüm Çalışanlar" çipi.
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ActionChip(
              avatar: const Icon(Icons.engineering_outlined, size: 16),
              label: const Text('Tüm Teknisyenler'),
              onPressed: _selectAllTeknisyen,
            ),
            for (final il in _availableIller)
              ActionChip(
                avatar: const Icon(Icons.location_on_outlined, size: 16),
                label: Text("$il'daki Tüm Çalışanlar"),
                onPressed: () => _selectAllInIl(il),
              ),
            if (_selectedIds.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.close, size: 16),
                label: const Text('Seçimi Temizle'),
                onPressed: _clearSelection,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: const InputDecoration(
            hintText: 'İsimle ara...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_filteredCandidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Aramanızla eşleşen çalışan bulunamadı.',
              style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: _filteredCandidates.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = _filteredCandidates[index];
                  final selected = _selectedIds.contains(user.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          _selectedIds.add(user.id);
                        } else {
                          _selectedIds.remove(user.id);
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(user.name),
                    subtitle: user.il != null && user.il!.isNotEmpty
                        ? Text(user.il!)
                        : null,
                    secondary: RoleBadge(
                      role: user.role,
                      label: roleLabel(user.role),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
