import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arassaha_flutter/services/api_service.dart';
import 'package:arassaha_flutter/utils/error_mapper.dart';

/// mapExceptionToUserMessage saf bir fonksiyon (girdi alır, string döner,
/// yan etkisi yok) — TEST-11 deseniyle yazılmış: her hata tipi/durum kodu
/// için AYRI, tek satırlık bir doğrulama. Amaç: hiçbir hatanın kullanıcıya
/// ham (SocketException/TimeoutException gibi teknik) bir metin olarak
/// sızmadığını garanti altına almak (bkz. proje geçmişi/Adım 0 taraması).
void main() {
  group('mapExceptionToUserMessage - ağ hataları', () {
    test('SocketException için internet bağlantısı mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(const SocketException('test'));
      expect(message, 'İnternet bağlantınızı kontrol edin');
    });

    test('TimeoutException için sunucu yanıt vermiyor mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(TimeoutException('test'));
      expect(message, 'Sunucu yanıt vermiyor, lütfen tekrar deneyin');
    });

    test('FormatException için genel bir mesaj dönmeli', () {
      final message = mapExceptionToUserMessage(const FormatException('test'));
      expect(message, 'Beklenmeyen bir hata oluştu');
    });
  });

  group('mapExceptionToUserMessage - ApiException (HTTP durum kodları)', () {
    test('401 için oturum mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(ApiException(401, 'test'));
      expect(message, contains('Oturumunuz sona ermiş'));
    });

    test('403 için yetki mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(ApiException(403, 'test'));
      expect(message, 'Bu işlem için yetkiniz bulunmuyor');
    });

    test('404 için kayıt bulunamadı mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(ApiException(404, 'test'));
      expect(message, 'Aranan kayıt bulunamadı');
    });

    test('429 için çok fazla istek mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(ApiException(429, 'test'));
      expect(message, 'Çok fazla istek gönderildi, lütfen biraz bekleyin');
    });

    test('500 için sunucu hatası mesajı dönmeli', () {
      final message = mapExceptionToUserMessage(ApiException(500, 'test'));
      expect(message, 'Sunucuda bir hata oluştu, lütfen daha sonra tekrar deneyin');
    });

    test('tanınmayan bir durum kodu (örn. 418) için de sunucu hatası mesajına düşmeli', () {
      final message = mapExceptionToUserMessage(ApiException(418, 'test'));
      expect(message, 'Sunucuda bir hata oluştu, lütfen daha sonra tekrar deneyin');
    });
  });

  group('mapExceptionToUserMessage - tanınmayan hatalar', () {
    test('tanınmayan bir hata için genel mesaj dönmeli', () {
      final message = mapExceptionToUserMessage(Exception('bilinmeyen bir şey'));
      expect(message, 'Beklenmeyen bir hata oluştu, lütfen tekrar deneyin');
    });

    test('düz bir String (Exception bile olmayan) hata için de genel mesaj dönmeli', () {
      final message = mapExceptionToUserMessage('ham bir hata metni');
      expect(message, 'Beklenmeyen bir hata oluştu, lütfen tekrar deneyin');
    });
  });

  group('mapExceptionToUserMessage - ham teknik detay hiçbir zaman sızmamalı', () {
    test('dönen mesaj orijinal exception metnini İÇERMEMELİ', () {
      final message = mapExceptionToUserMessage(
        const SocketException("Failed host lookup: 'api.arassaha.com'"),
      );
      expect(message, isNot(contains('SocketException')));
      expect(message, isNot(contains('api.arassaha.com')));
    });
  });
}
