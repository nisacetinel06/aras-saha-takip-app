import 'package:flutter/foundation.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// QR Kod Üretimi modülü — henüz fiziksel etiketi basılmamış ekipmanları
/// seçme, önizleme ve "basıldı" olarak işaretleme akışının state'i.
///
/// İKİ AYRI SAYIM kasıtlı olarak birbirinden bağımsız tutulur:
///   - [unprintedCount]: Ana Sayfa'daki "QR Kod Üret" Çabuk Erişim rozeti
///     için — HER ZAMAN filtresiz toplam sayı (bkz. fetchUnprintedCount).
///   - [unprintedEquipment]: Seçim ekranındaki, tip/il filtresine göre
///     daralabilen liste (bkz. fetchUnprintedEquipment). Rozet, kullanıcı
///     seçim ekranında bir filtre uygulasa bile Ana Sayfa'dakiyle TUTARLI
///     kalmalı — bu yüzden ayrı bir istek/state.
class QrGenerationProvider extends ChangeNotifier {
  final ApiService _apiService;

  QrGenerationProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  // --- Ana Sayfa rozeti ---
  int? _unprintedCount;
  int? get unprintedCount => _unprintedCount;

  Future<void> fetchUnprintedCount() async {
    try {
      final list = await _apiService.getEquipmentList(qrPrintedFilter: false);
      _unprintedCount = list.length;
      notifyListeners();
    } catch (_) {
      // Sessiz başarısızlık: bu yalnızca bir Çabuk Erişim rozeti göstergesi,
      // Ana Sayfa'nın geri kalanını bir hata mesajıyla bozmaya değmez —
      // rozet olduğu gibi (varsa eski değer, yoksa gizli) kalır.
    }
  }

  // --- Ekipman Seçim Ekranı (qr_generation_screen.dart) ---
  List<Equipment> _unprintedEquipment = [];
  bool _isLoadingList = false;
  String? _listErrorMessage;
  EquipmentType? _typeFilter;
  String? _ilFilter;
  final Set<int> _selectedIds = {};

  List<Equipment> get unprintedEquipment => _unprintedEquipment;
  bool get isLoadingList => _isLoadingList;
  String? get listErrorMessage => _listErrorMessage;
  EquipmentType? get typeFilter => _typeFilter;
  String? get ilFilter => _ilFilter;
  Set<int> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;

  /// QR Önizleme ekranına aktarılacak, seçili ekipmanların tam listesi.
  List<Equipment> get selectedEquipment => _unprintedEquipment
      .where((e) => _selectedIds.contains(e.id))
      .toList();

  Future<void> fetchUnprintedEquipment() async {
    _isLoadingList = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _unprintedEquipment = await _apiService.getEquipmentList(
        qrPrintedFilter: false,
        typeFilter: _typeFilter?.name,
        ilFilter: _ilFilter,
      );
      // Artık listede olmayan (ör. filtre değişti ya da bu arada başka bir
      // yönetici basmış) id'ler seçimde YETİM kalmasın.
      _selectedIds.removeWhere(
        (id) => !_unprintedEquipment.any((e) => e.id == id),
      );
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingList = false;
      notifyListeners();
    }
  }

  Future<void> setTypeFilter(EquipmentType? type) async {
    _typeFilter = type;
    await fetchUnprintedEquipment();
  }

  Future<void> setIlFilter(String? il) async {
    _ilFilter = il;
    await fetchUnprintedEquipment();
  }

  void toggleSelection(int equipmentId) {
    if (_selectedIds.contains(equipmentId)) {
      _selectedIds.remove(equipmentId);
    } else {
      _selectedIds.add(equipmentId);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds
      ..clear()
      ..addAll(_unprintedEquipment.map((e) => e.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  // --- QR Önizleme / PDF sonrası "basıldı" işaretlemesi ---
  bool _isMarkingPrinted = false;
  String? _markPrintedErrorMessage;

  bool get isMarkingPrinted => _isMarkingPrinted;
  String? get markPrintedErrorMessage => _markPrintedErrorMessage;

  /// PDF paylaşım/yazdırma diyaloğu başarıyla kapandıktan SONRA çağrılır.
  /// Başarılıysa: basılan ekipmanlar `unprintedEquipment`'ten (refetch ile)
  /// düşer, seçim temizlenir, Ana Sayfa rozet sayısı da güncellenir.
  Future<bool> markAsPrinted(List<int> equipmentIds) async {
    _isMarkingPrinted = true;
    _markPrintedErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.markEquipmentQrPrinted(equipmentIds);
      clearSelection();
      await fetchUnprintedEquipment();
      await fetchUnprintedCount();
      return true;
    } catch (e) {
      _markPrintedErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isMarkingPrinted = false;
      notifyListeners();
    }
  }
}
