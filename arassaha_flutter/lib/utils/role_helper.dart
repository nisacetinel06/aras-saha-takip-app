/// Backend'deki `users.role` ham string'ini ('teknisyen' | 'dispecer' |
/// 'yonetici') Türkçe, ekranda gösterilebilir hâline çevirir. AuthProvider
/// (giriş yapan kullanıcı) ve Kullanıcı Yönetimi ekranları (listedeki
/// HERHANGİ bir kullanıcı) aynı mantığı kullandığı için tek yerde tutulur.
String roleLabel(String role) {
  switch (role) {
    case 'teknisyen':
      return 'Teknisyen';
    case 'dispecer':
      return 'Dispeçer';
    case 'yonetici':
      return 'Yönetici';
    default:
      return role;
  }
}
