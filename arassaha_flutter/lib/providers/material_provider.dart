import 'package:flutter/foundation.dart';
import '../models/equipment.dart' show EquipmentType;
import '../models/material.dart';
import '../services/api_service.dart';

/// Malzeme / Yedek Parça Stok Takibi (Modül 13) ekranlarının state'ini yönetir:
/// arama (typeahead), malzeme detayı, kritik stok listesi, bir iş emrindeki
/// malzeme kullanımları ve bunlara ilişkin aksiyonlar (kullanım kaydetme/
/// silme, restock, yeni malzeme oluşturma).
class MaterialProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // --- Arama (MaterialPickerField — Equipment/EquipmentProvider ile AYNI
  // desen: debounce mantığı widget'ta, burada yalnızca API çağrısı) ---
  List<MaterialItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchErrorMessage;

  List<MaterialItem> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchErrorMessage => _searchErrorMessage;

  // --- Malzeme listesi ekranı (kategori/kritik stok filtreli) ---
  List<MaterialItem> _materials = [];
  bool _isLoadingList = false;
  String? _listErrorMessage;

  List<MaterialItem> get materials => _materials;
  bool get isLoadingList => _isLoadingList;
  String? get listErrorMessage => _listErrorMessage;

  // --- Malzeme detayı ---
  MaterialDetail? _selectedMaterialDetail;
  bool _isLoadingDetail = false;
  String? _detailErrorMessage;

  MaterialDetail? get selectedMaterialDetail => _selectedMaterialDetail;
  bool get isLoadingDetail => _isLoadingDetail;
  String? get detailErrorMessage => _detailErrorMessage;

  // --- Dashboard "Kritik Stoktaki Malzemeler" widget'ı ---
  List<MaterialItem> _lowStockMaterials = [];
  bool _isLoadingLowStock = false;
  String? _lowStockErrorMessage;

  List<MaterialItem> get lowStockMaterials => _lowStockMaterials;
  bool get isLoadingLowStock => _isLoadingLowStock;
  String? get lowStockErrorMessage => _lowStockErrorMessage;

  // --- İş Emri Detayı'ndaki "Kullanılan Malzemeler" bölümü ---
  List<WorkOrderMaterialUsage> _workOrderMaterials = [];
  bool _isLoadingWorkOrderMaterials = false;
  String? _workOrderMaterialsErrorMessage;

  List<WorkOrderMaterialUsage> get workOrderMaterials => _workOrderMaterials;
  bool get isLoadingWorkOrderMaterials => _isLoadingWorkOrderMaterials;
  String? get workOrderMaterialsErrorMessage => _workOrderMaterialsErrorMessage;

  // --- Mutasyon durumları (kayıt/silme/restock/oluşturma) ---
  bool _isSubmitting = false;
  String? _submitErrorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get submitErrorMessage => _submitErrorMessage;

  /// Arama sonuçlarını, verilen ekipman tipine (varsa) göre YENİDEN sıralar —
  /// [equipmentTypeHint] ile uyumlu malzemeler listenin BAŞINA taşınır, geri
  /// kalanı backend'in zaten döndürdüğü (isme göre alfabetik) sırada kalır.
  /// Bu, arama/filtreleme DEĞİL yalnızca bir sıralama ipucudur — backend'e
  /// ayrı bir parametre olarak gönderilmez, tamamen istemci tarafında yapılır.
  List<MaterialItem> _sortByEquipmentTypeHint(
    List<MaterialItem> materials,
    String? equipmentTypeHint,
  ) {
    if (equipmentTypeHint == null) return materials;
    final hintType = EquipmentType.fromJson(equipmentTypeHint);

    final matching = <MaterialItem>[];
    final rest = <MaterialItem>[];
    for (final material in materials) {
      if (material.compatibleEquipmentTypes.contains(hintType)) {
        matching.add(material);
      } else {
        rest.add(material);
      }
    }
    return [...matching, ...rest];
  }

  Future<void> searchMaterials(
    String query, {
    String? equipmentTypeHint,
  }) async {
    _isSearching = true;
    _searchErrorMessage = null;
    notifyListeners();

    try {
      final results = await _apiService.getMaterials(search: query);
      _searchResults = _sortByEquipmentTypeHint(results, equipmentTypeHint);
    } catch (e) {
      _searchErrorMessage = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _searchErrorMessage = null;
    notifyListeners();
  }

  Future<void> fetchMaterials({
    String? category,
    bool lowStockOnly = false,
  }) async {
    _isLoadingList = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _materials = await _apiService.getMaterials(
        category: category,
        lowStockOnly: lowStockOnly,
      );
    } catch (e) {
      _listErrorMessage = e.toString();
    } finally {
      _isLoadingList = false;
      notifyListeners();
    }
  }

  Future<void> fetchMaterialDetail(int id) async {
    _isLoadingDetail = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedMaterialDetail = await _apiService.getMaterialDetail(id);
    } catch (e) {
      _detailErrorMessage = e.toString();
    } finally {
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  Future<void> fetchLowStockMaterials({int limit = 5}) async {
    _isLoadingLowStock = true;
    _lowStockErrorMessage = null;
    notifyListeners();

    try {
      _lowStockMaterials = await _apiService.getLowStockMaterials(limit: limit);
    } catch (e) {
      _lowStockErrorMessage = e.toString();
    } finally {
      _isLoadingLowStock = false;
      notifyListeners();
    }
  }

  Future<void> fetchWorkOrderMaterials(int workOrderId) async {
    _isLoadingWorkOrderMaterials = true;
    _workOrderMaterialsErrorMessage = null;
    notifyListeners();

    try {
      _workOrderMaterials = await _apiService.getWorkOrderMaterials(
        workOrderId,
      );
    } catch (e) {
      _workOrderMaterialsErrorMessage = e.toString();
    } finally {
      _isLoadingWorkOrderMaterials = false;
      notifyListeners();
    }
  }

  /// Stok yetersizse backend 400 + net bir mesajla reddeder (bkz.
  /// routes/materials.js) — bu mesaj [submitErrorMessage] üzerinden okunur.
  /// Başarılıysa iş emrinin malzeme listesi yeniden çekilir.
  Future<bool> recordMaterialUsage(
    int workOrderId,
    int materialId,
    double quantityUsed,
  ) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.recordMaterialUsage(
        workOrderId,
        materialId,
        quantityUsed,
      );
      await fetchWorkOrderMaterials(workOrderId);
      return true;
    } catch (e) {
      _submitErrorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Dispeçer/yönetici — kaydı siler, backend düşülen stoğu geri ekler.
  Future<bool> removeMaterialUsage(int workOrderId, int usageId) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.removeMaterialUsage(workOrderId, usageId);
      await fetchWorkOrderMaterials(workOrderId);
      return true;
    } catch (e) {
      _submitErrorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Yalnızca yönetici — stok girişi/ikmali. Başarılıysa açık olan malzeme
  /// detayını da tazeler (güncel stok + yeni hareket geçmişi satırı görünsün diye).
  Future<bool> restockMaterial(int id, double quantityAdded) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.restockMaterial(id, quantityAdded);
      await fetchMaterialDetail(id);
      return true;
    } catch (e) {
      _submitErrorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Yalnızca yönetici — yeni bir malzeme TİPİ tanımlar.
  Future<bool> createMaterial({
    required String name,
    required MaterialCategory category,
    required MaterialUnit unit,
    required double stockQuantity,
    required double minStockThreshold,
    required List<EquipmentType> compatibleEquipmentTypes,
    double? unitCost,
  }) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.createMaterial(
        name: name,
        category: category,
        unit: unit,
        stockQuantity: stockQuantity,
        minStockThreshold: minStockThreshold,
        compatibleEquipmentTypes: compatibleEquipmentTypes,
        unitCost: unitCost,
      );
      return true;
    } catch (e) {
      _submitErrorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
