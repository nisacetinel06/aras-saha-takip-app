import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../models/work_order.dart' show AssignedUser, WorkOrderStatus;
import '../../providers/user_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/error_mapper.dart';
import '../../utils/role_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/sticky_form_footer.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

const _roles = ['teknisyen', 'dispecer', 'yonetici'];

/// Kullanıcı Ekle/Düzenle formu (Modül 8 — yalnızca yönetici erişir, bkz.
/// UserManagementListScreen). `userId` verilirse düzenleme modu, verilmezse
/// ekleme modudur — aynı ekran, tek bir kod yolu.
class UserEditScreen extends StatefulWidget {
  final int? userId;
  const UserEditScreen({super.key, this.userId});

  bool get isEditMode => userId != null;

  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _nameController = TextEditingController();
  final _sicilNoController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ilController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _role = 'teknisyen';
  bool _isActive = true;
  File? _newPhotoFile;
  String? _existingPhotoPath;

  // Rol gerçekten değiştirildiğinde (bkz. _submit) onay dialogunda göstermek
  // için yüklenen kullanıcının ORİJİNAL rolü ile işlem geçmişi.
  String? _originalRole;
  List<UserActionLog> _logs = [];

  bool _isLoadingDetail = false;
  String? _loadErrorMessage;

  // Dispeçer atama/değiştirme/silme (Modül 8 devamı — bkz. ARCHITECTURE.md):
  // yalnızca rol 'teknisyen' iken anlamlıdır ve gösterilir.
  List<AssignedUser> _dispatchers = [];
  AssignedUser? _selectedSupervisor;
  int? _existingSupervisorId;
  bool _isLoadingDispatchers = true;
  String? _dispatchersErrorMessage;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('UserEditScreen');
    _loadDispatchers();
    if (widget.isEditMode) {
      _loadUser();
    }
  }

  AssignedUser? _findDispatcher(int? id) {
    if (id == null) return null;
    for (final d in _dispatchers) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _loadDispatchers() async {
    setState(() {
      _isLoadingDispatchers = true;
      _dispatchersErrorMessage = null;
    });
    try {
      final dispatchers = await ApiService().getUsers(roleFilter: 'dispecer');
      if (!mounted) return;
      setState(() {
        _dispatchers = dispatchers;
        _selectedSupervisor =
            _findDispatcher(_existingSupervisorId) ?? _selectedSupervisor;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _dispatchersErrorMessage = mapExceptionToUserMessage(e));
    } finally {
      if (mounted) setState(() => _isLoadingDispatchers = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sicilNoController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _ilController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    setState(() {
      _isLoadingDetail = true;
      _loadErrorMessage = null;
    });

    final provider = context.read<UserProvider>();
    await provider.fetchUserDetail(widget.userId!);
    final user = provider.selectedUser;

    if (!mounted) return;

    if (user == null) {
      setState(() {
        _isLoadingDetail = false;
        _loadErrorMessage =
            provider.detailErrorMessage ?? 'Kullanıcı bulunamadı.';
      });
      return;
    }

    setState(() {
      _nameController.text = user.name;
      _sicilNoController.text = user.sicilNo;
      _phoneController.text = user.phone ?? '';
      _emailController.text = user.email ?? '';
      _ilController.text = user.il ?? '';
      _role = user.role;
      _originalRole = user.role;
      _isActive = user.isActive;
      _existingPhotoPath = user.photoPath;
      _existingSupervisorId = user.supervisorId;
      _selectedSupervisor = _findDispatcher(user.supervisorId);
      _logs = user.logs;
      _isLoadingDetail = false;
    });
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
      setState(() => _newPhotoFile = File(file.path));
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
          ],
        ),
      ),
    );
  }

  /// Yönetici tarafından şifre sıfırlama (Modül 8 devamı) — teknisyen/dispeçer
  /// kendi şifresini değiştiremediği için (profil salt-okunur), şifresini
  /// unutan bir kullanıcının şifresi burada sıfırlanır.
  Future<void> _showResetPasswordDialog() async {
    final passwordController = TextEditingController();

    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Şifreyi Sıfırla'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Yeni şifre (en az 4 karakter)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              if (passwordController.text.trim().length >= 4) {
                Navigator.of(dialogContext).pop(passwordController.text.trim());
              }
            },
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );

    if (newPassword == null || !mounted) return;

    final provider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.resetPassword(widget.userId!, newPassword);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Şifre güncellendi.'
              : (provider.saveErrorMessage ?? 'Şifre sıfırlanamadı.'),
        ),
      ),
    );
  }

  bool get _canSubmit {
    final baseValid =
        _nameController.text.trim().isNotEmpty &&
        _sicilNoController.text.trim().isNotEmpty;
    if (!widget.isEditMode) {
      return baseValid && _passwordController.text.trim().length >= 4;
    }
    return baseValid;
  }

  /// Rol GERÇEKTEN değiştiyse (yalnızca düzenleme modunda anlamlı) onay
  /// dialogu gösterir. Orijinal rol teknisyen ise, üzerindeki açık iş emri
  /// sayısını bilgilendirici bir not olarak ekler — bu sadece bir bilgi
  /// notudur, iş emirleri OTOMATİK boşaltılmaz/etkilenmez (bkz. görev tanımı
  /// madde 8: "ekstra bir iş mantığı kurmana gerek yok").
  Future<bool> _confirmRoleChange() async {
    int? openCount;
    if (_originalRole == 'teknisyen') {
      try {
        final allOrders = await ApiService().getWorkOrders();
        openCount = allOrders
            .where(
              (w) =>
                  w.assignedUser?.id == widget.userId &&
                  w.status != WorkOrderStatus.cozuldu,
            )
            .length;
      } catch (_) {
        openCount = null; // Hesaplanamadıysa notu atla, işlemi engelleme.
      }
    }

    if (!mounted) return false;

    final newRoleLabel = roleLabel(_role);
    final message = (openCount != null && openCount > 0)
        ? 'Rolü $newRoleLabel olarak değiştirmek üzeresiniz. Bu kullanıcının üzerinde $openCount adet açık iş emri var, rol değişikliği bunları etkilemeyecek. Devam edilsin mi?'
        : 'Rolü $newRoleLabel olarak değiştirmek istediğinize emin misiniz?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rol Değişikliği'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    if (widget.isEditMode && _role != _originalRole) {
      final confirmed = await _confirmRoleChange();
      if (!confirmed || !mounted) return;
    }

    final provider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Dispeçer bağı yalnızca teknisyen rolünde anlamlıdır — başka bir role
    // geçiliyorsa bu ekrandan dokunulmaz (updateSupervisor: false).
    final isTeknisyen = _role == 'teknisyen';

    bool success;
    if (widget.isEditMode) {
      success = await provider.updateUser(
        widget.userId!,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        il: _ilController.text.trim(),
        role: _role,
        updateSupervisor: isTeknisyen,
        supervisorId: isTeknisyen ? _selectedSupervisor?.id : null,
      );
    } else {
      success = await provider.createUser(
        name: _nameController.text.trim(),
        sicilNo: _sicilNoController.text.trim(),
        password: _passwordController.text.trim(),
        role: _role,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        il: _ilController.text.trim(),
        supervisorId: isTeknisyen ? _selectedSupervisor?.id : null,
      );
    }

    if (!success) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(provider.saveErrorMessage ?? 'Kaydedilemedi.')),
      );
      return;
    }

    // Fotoğraf değiştiyse — oluşturma modunda az önce dönen kullanıcının
    // id'sini (provider.selectedUser, bkz. UserProvider.createUser), düzenleme
    // modunda widget.userId'yi kullanarak — ayrıca gerçek bir upload yapılır.
    if (_newPhotoFile != null) {
      final targetId = widget.isEditMode
          ? widget.userId!
          : provider.selectedUser?.id;
      if (targetId != null) {
        final photoUploaded = await provider.uploadUserPhoto(
          targetId,
          _newPhotoFile!,
        );
        if (!photoUploaded && mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Kullanıcı kaydedildi ama fotoğraf yüklenemedi: ${provider.saveErrorMessage ?? ''}',
              ),
            ),
          );
          navigator.pop(true);
          return;
        }
      }
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.isEditMode
              ? 'Kullanıcı güncellendi.'
              : 'Kullanıcı oluşturuldu.',
        ),
      ),
    );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppTopBar(
        title: widget.isEditMode
            ? 'Kullanıcıyı Düzenle'
            : 'Yeni Kullanıcı Ekle',
      ),
      body: SafeArea(
        top: false,
        child: _isLoadingDetail
            ? const Center(child: CircularProgressIndicator())
            : _loadErrorMessage != null
            ? EmptyState(
                icon: Icons.error_outline,
                title: 'Kullanıcı yüklenemedi',
                subtitle: _loadErrorMessage!,
                onPrimaryAction: _loadUser,
                primaryActionLabel: 'Tekrar Dene',
                primaryActionVariant: AppButtonVariant.secondary,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  Center(child: _buildPhotoPicker()),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Ad Soyad',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Örn. Ahmet Yılmaz',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Sicil No',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _sicilNoController,
                    enabled: !widget.isEditMode,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Örn. 1007',
                      helperText: widget.isEditMode
                          ? 'Sicil no oluşturulduktan sonra değiştirilemez.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Telefon',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Örn. 0532 123 45 67',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'E-posta',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Örn. ahmet.yilmaz@arasedas.com.tr',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text('İl', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _ilController,
                    decoration: const InputDecoration(
                      hintText: 'Örn. Erzurum',
                      // Yöneticiden Çalışana Duyuru/Mesaj Sistemi'ndeki "Şu
                      // İldeki Herkes" toplu gönderim kısayolu bu alanı
                      // kullanır (bkz. send_manager_message_screen.dart) —
                      // opsiyonel, boş bırakılırsa yalnızca o kısayolda
                      // görünmez.
                      helperText:
                          'Toplu mesaj gönderiminde "Şu İldeki Herkes" kısayolu için kullanılır.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text('Rol', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: _roles.map((role) {
                      final selected = _role == role;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: _RoleChip(
                            role: role,
                            selected: selected,
                            onTap: () => setState(() => _role = role),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Dispeçer atama/değiştirme/silme — yalnızca teknisyen
                  // rolünde anlamlıdır (bkz. ARCHITECTURE.md Modül 8 devamı,
                  // hiyerarşik yetkilendirme: her dispeçer yalnızca kendi
                  // ekibini görür).
                  if (_role == 'teknisyen') ...[
                    Text(
                      'Bağlı Dispeçer',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSupervisorField(scheme),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (!widget.isEditMode) ...[
                    Text(
                      'Şifre',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'En az 4 karakter',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (widget.isEditMode) ...[
                    // Aktif/Pasif durumu artık BURADAN değiştirilmez —
                    // yalnızca Kullanıcı Yönetimi listesindeki net "Aktifleştir"/
                    // "Pasifleştir" butonlarından, onay dialoguyla ve
                    // loglanarak yönetilir (bkz. UserManagementListScreen).
                    // Burada yalnızca salt-okunur bir durum göstergesi var —
                    // ikisi karışmasın diye.
                    AppCard(
                      child: Row(
                        children: [
                          Icon(
                            _isActive
                                ? Icons.check_circle_outline
                                : Icons.block_outlined,
                            size: 18,
                            color: _isActive
                                ? AppColors.success(context)
                                : AppColors.danger(context),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _isActive ? 'Aktif kullanıcı' : 'Pasif kullanıcı',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),

                    // Şifre sıfırlama (Modül 8 devamı) — teknisyen/dispeçer
                    // kendi şifresini değiştiremediği için buradan yönetici
                    // tarafından sıfırlanır.
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: 'Şifreyi Sıfırla',
                        icon: Icons.password_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: _showResetPasswordDialog,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (provider.saveErrorMessage != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            provider.saveErrorMessage!,
                            style: TextStyle(color: scheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // İşlem Geçmişi — Cihaz Yönetimi modülündeki (device_action_logs)
                  // ile AYNI tasarım deseni. Yalnızca düzenleme modunda gösterilir.
                  if (widget.isEditMode) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'İşlem Geçmişi',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm + 4),
                          if (_logs.isEmpty)
                            Text(
                              'Henüz bir işlem yapılmadı.',
                              style: AppTextStyles.bodyMedium(
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (int i = 0; i < _logs.length; i++) ...[
                                  if (i > 0) const Divider(height: 20),
                                  _LogRow(log: _logs[i]),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
      // B1: form yüklenip gösterildiğinde (yükleniyor/hata durumunda değil)
      // "Kaydet" ekranın altında sabit — bkz. widgets/sticky_form_footer.dart.
      bottomNavigationBar: (_isLoadingDetail || _loadErrorMessage != null)
          ? null
          : StickyFormFooter(
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Kaydet',
                  icon: Icons.save_outlined,
                  isLoading: provider.isSaving,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ),
    );
  }

  Widget _buildSupervisorField(ColorScheme scheme) {
    if (_isLoadingDispatchers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_dispatchersErrorMessage != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Dispeçerler yüklenemedi',
        subtitle: _dispatchersErrorMessage!,
        onPrimaryAction: _loadDispatchers,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    return DropdownButtonFormField<AssignedUser?>(
      initialValue: _selectedSupervisor,
      isExpanded: true,
      decoration: const InputDecoration(
        hintText: 'Dispeçer seçin',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<AssignedUser?>(
          value: null,
          child: Text('Atanmamış'),
        ),
        ..._dispatchers.map(
          (d) => DropdownMenuItem<AssignedUser?>(value: d, child: Text(d.name)),
        ),
      ],
      onChanged: (dispatcher) =>
          setState(() => _selectedSupervisor = dispatcher),
    );
  }

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _showPhotoSourcePicker,
      child: Stack(
        children: [
          _newPhotoFile != null
              ? CircleAvatar(
                  radius: 48,
                  backgroundImage: FileImage(_newPhotoFile!),
                )
              : UserAvatar(
                  photoPath: _existingPhotoPath,
                  initials: _nameController.text.trim().isEmpty
                      ? '?'
                      : _initialsOf(_nameController.text),
                  role: _role,
                  radius: 48,
                ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 16,
                color: accessibleOnColor(Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = roleColor(context, role);

    return AppCard(
      onTap: onTap,
      backgroundTint: selected ? color : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: Text(
          roleLabel(role),
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

class _LogRow extends StatelessWidget {
  final UserActionLog log;
  const _LogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.circle, size: 8, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                log.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${log.performedBy} · ${formatRelativeTime(log.createdAt)}',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
