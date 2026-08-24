#!/usr/bin/env bash
# Hata ve Boş Durum Standartları denetimi (bkz. CONTRIBUTING.md).
#
# lib/ altındaki .dart dosyalarında ham exception metninin (e.toString(),
# error.toString(), $e / $error interpolasyonu) kullanıcıya gösterilen bir
# yere sızıp sızmadığını tarar. `mapExceptionToUserMessage()` tanımının
# bulunduğu utils/error_mapper.dart hariç tutulur (fonksiyonun kendisi ve
# içindeki kDebugMode logu bilinçli olarak `error`'ı kullanır).
#
# Bu bir HARD gate değil, basit bir uyarı taramasıdır — bazı eşleşmeler
# (örn. sadece geliştirici konsoluna yazan debugPrint çağrıları) meşru
# olabilir; bulunan her satırı elle gözden geçirin.
set -euo pipefail

cd "$(dirname "$0")/.."

pattern='\be\.toString\(\)|\berror\.toString\(\)|\$e\b|\$\{e\}|\$error\b|\$\{error\}'
exclude_file='lib/utils/error_mapper.dart'

matches=$(grep -rnE "$pattern" lib --include='*.dart' | grep -v "^${exclude_file}:" || true)

if [ -z "$matches" ]; then
  echo "OK: ham exception sızıntısı bulunamadı (lib/**/*.dart)."
  exit 0
fi

echo "UYARI: aşağıdaki satırlar ham exception metni sızdırıyor olabilir."
echo "Kullanıcıya gösterilen her hata mesajı mapExceptionToUserMessage() üzerinden üretilmeli (bkz. CONTRIBUTING.md)."
echo
echo "$matches"
echo
echo "$(echo "$matches" | wc -l) satır bulundu."
exit 1
