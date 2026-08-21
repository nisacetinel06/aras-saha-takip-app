import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

/// Yakalanan HERHANGİ bir hatayı (ağ, sunucu, ayrıştırma) kullanıcıya
/// gösterilecek, Türkçe, kısa ve mümkünse aksiyon önerici bir mesaja çevirir.
///
/// TÜM provider'ların catch bloklarının TEK ortak çıkış noktası — daha önce
/// her provider kendi `e.toString()`'ini `errorMessage` olarak kullanıyordu,
/// bu da kullanıcıya `SocketException: Failed host lookup: ...` gibi ham,
/// teknik metinler gösteriyordu (bkz. proje geçmişi/Adım 0 taraması).
///
/// Saf bir fonksiyondur (girdi alır, string döner, yan etkisi yoktur) —
/// `kDebugMode` altındaki `developer.log` çağrısı istisnadır: yalnızca
/// GELİŞTİRİCİ konsoluna yazar, dönüş değerini ETKİLEMEZ ve release
/// build'de HİÇ çalışmaz (bkz. madde 5 — teknik detay release'de asla
/// kullanıcıya/konsola sızmamalı).
String mapExceptionToUserMessage(dynamic error) {
  if (kDebugMode) {
    developer.log(
      'Yakalanan hata: $error',
      name: 'ArasSahaError',
      error: error,
    );
  }

  if (error is SocketException) {
    return 'İnternet bağlantınızı kontrol edin';
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermiyor, lütfen tekrar deneyin';
  }
  if (error is FormatException) {
    return 'Beklenmeyen bir hata oluştu';
  }
  if (error is ApiException) {
    switch (error.statusCode) {
      case 401:
        return 'Oturumunuz sona ermiş, lütfen tekrar giriş yapın';
      case 403:
        return 'Bu işlem için yetkiniz bulunmuyor';
      case 404:
        return 'Aranan kayıt bulunamadı';
      case 429:
        return 'Çok fazla istek gönderildi, lütfen biraz bekleyin';
      case 500:
      default:
        return 'Sunucuda bir hata oluştu, lütfen daha sonra tekrar deneyin';
    }
  }

  return 'Beklenmeyen bir hata oluştu, lütfen tekrar deneyin';
}
