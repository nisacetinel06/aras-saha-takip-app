import 'package:flutter/foundation.dart';
import '../models/manager_message.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi ekranlarının state'ini yönetir.
///
/// TEK YÖNLÜ: çalışan yalnızca [fetchMyMessages]/[markAsRead] çağırır;
/// [sendMessage]/[fetchSentMessages]/[fetchReadStatus] SADECE yöneticinin
/// kullandığı ekranlardan (bkz. send_manager_message_screen.dart,
/// sent_messages_screen.dart) çağrılır — backend zaten bunları
/// requireRole('yonetici') ile korur (bkz. routes/managerMessages.js), ama
/// Flutter tarafında da bu ekranlara teknisyen/dispeçer rolü hiç
/// yönlendirilmez (bkz. home_screen.dart, module_entries.dart rol filtreleri).
class ManagerMessageProvider extends ChangeNotifier {
  final ApiService _apiService;

  ManagerMessageProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  List<ManagerMessage> _messages = [];
  bool _isListLoading = false;
  String? _listErrorMessage;

  List<SentManagerMessage> _sentMessages = [];
  bool _isSentListLoading = false;
  String? _sentListErrorMessage;

  MessageReadStatus? _selectedReadStatus;
  bool _isReadStatusLoading = false;
  String? _readStatusErrorMessage;

  bool _isSending = false;
  String? _sendErrorMessage;

  List<ManagerMessage> get messages => _messages;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;
  int get unreadCount => _messages.where((m) => !m.isRead).length;

  List<SentManagerMessage> get sentMessages => _sentMessages;
  bool get isSentListLoading => _isSentListLoading;
  String? get sentListErrorMessage => _sentListErrorMessage;

  MessageReadStatus? get selectedReadStatus => _selectedReadStatus;
  bool get isReadStatusLoading => _isReadStatusLoading;
  String? get readStatusErrorMessage => _readStatusErrorMessage;

  bool get isSending => _isSending;
  String? get sendErrorMessage => _sendErrorMessage;

  Future<void> fetchMyMessages() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _messages = await _apiService.getManagerMessages();
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  /// Mesajı okundu olarak işaretler ve listedeki karşılığını iyimser
  /// (optimistic) günceller — NotificationProvider.markAsRead ile AYNI desen.
  /// Zaten okunmuşsa ikinci bir istek atmaz (bkz. ManagerMessageDetailScreen
  /// initState — ekran her açıldığında çağrılır, tekrar tekrar backend'e
  /// gitmesin diye).
  Future<void> markAsRead(int id) async {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index == -1 || _messages[index].isRead) return;

    try {
      await _apiService.markManagerMessageRead(id);
      _messages[index] = _messages[index].copyWith(readAt: DateTime.now());
      notifyListeners();
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
      notifyListeners();
    }
  }

  /// Yeni bir duyuru gönderir. Başarılıysa true döner. Kaç kişiye
  /// gönderildiğini bilmek isteyen çağıran taraf (bkz.
  /// SendManagerMessageScreen) `recipientUserIds.length`'i zaten kendisi
  /// bilir — backend'in `recipient_count` yanıtı burada ayrıca taşınmaz,
  /// gönderme başarılı/başarısız bilgisi yeterlidir.
  Future<bool> sendMessage({
    String? title,
    required String content,
    required List<int> recipientUserIds,
  }) async {
    _isSending = true;
    _sendErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.sendManagerMessage(
        title: title,
        content: content,
        recipientUserIds: recipientUserIds,
      );
      return true;
    } catch (e) {
      _sendErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> fetchSentMessages() async {
    _isSentListLoading = true;
    _sentListErrorMessage = null;
    notifyListeners();

    try {
      _sentMessages = await _apiService.getSentManagerMessages();
    } catch (e) {
      _sentListErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isSentListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchReadStatus(int id) async {
    _isReadStatusLoading = true;
    _readStatusErrorMessage = null;
    _selectedReadStatus = null;
    notifyListeners();

    try {
      _selectedReadStatus = await _apiService.getManagerMessageReadStatus(id);
    } catch (e) {
      _readStatusErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isReadStatusLoading = false;
      notifyListeners();
    }
  }
}
