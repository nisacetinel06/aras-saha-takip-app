/// Acil Durum (SOS) Modülü — "Yöneticimi Ara" butonu için sabit yedek numara.
///
/// KAPSAM KARARI: teknisyenin bağlı olduğu dispeçer/yöneticinin telefonu
/// kayıtlıysa (bkz. GET /api/users/me/supervisor) HER ZAMAN o numara aranır;
/// bu sabit yalnızca o numara HİÇ girilmemişse (null) devreye giren bir
/// yedektir. Tam bir "Ayarlar" ekranı/backend alanı (yönetici tarafından
/// değiştirilebilir bir Acil Durum Hattı) BİLİNÇLİ olarak kurulmadı — bu
/// modülün HIZ/SADELİK önceliğine göre, ikinci bir yönetim ekranı/endpoint
/// gerektirmeyen en basit çözüm budur; ihtiyaç doğarsa kolayca bu tek sabit
/// değiştirilebilir ya da ileride bir Ayarlar alanına taşınabilir.
const String emergencyHotlineNumber = '112';
const String emergencyHotlineLabel = 'Acil Durum Hattı (112)';
