"""
Modül 10 (Arıza Açıklaması Otomatik Sınıflandırma) — sentetik Türkçe metin
eğitim verisi üretici.

DÜRÜSTLÜK NOTU (bkz. README.md — Modül 9'daki ile AYNI prensip): Gerçek bir
şirketin yıllarca birikmiş arıza açıklama metinleri elimizde yok. Bunun
yerine dört arıza tipi için şablon cümleler yazıp bunları hafif kelime/kalıp
varyasyonlarıyla (önek/sonek ekleme) çoğaltarak SENTETİK bir Türkçe metin
veri seti üretiyoruz — gerçek bir dil modeli değil, kural tabanlı bir
metin üretici. Gerçek üretim ortamında bu script TAMAMEN devre dışı
bırakılır; yerine ArasSaha'nın work_orders.description sütununda biriken
GERÇEK arıza açıklama metinleri (ve personel tarafından geriye dönük
etiketlenmiş gerçek arıza tipi/öncelik etiketleri) kullanılır — model
mimarisi ve eğitim/servis kodu (train_text_model.py, app.py) değişmeden kalır.
"""
import random

import pandas as pd

random.seed(42)

TARGET_MIN_PER_TYPE = 60
TARGET_MAX_PER_TYPE = 80

# Dört arıza tipi için şablon cümleler — sahada personelin gerçekten
# yazabileceği tarzda, kısa ve doğrudan Türkçe ifadeler.
BASE_TEMPLATES = {
    "trafo_arizasi": [
        "trafo aşırı ısınıyor",
        "trafodan yanık kokusu geliyor",
        "trafo ses çıkarıyor, uğultu var",
        "trafo yağı sızıntısı var",
        "trafo kapağı açılmış, içerisi görünüyor",
        "trafoda kıvılcım oluşuyor",
        "trafo gövdesinde şişme var",
        "trafo çok fazla titreşim yapıyor",
        "trafodan duman çıkıyor",
        "trafo bağlantı noktası kararmış",
        "trafo soğutma sıvısı azalmış",
        "trafo üzerinde pas ve korozyon var",
        "trafo devre dışı kaldı, gerilim düştü",
        "trafo kutusu su almış",
        "trafo etrafında elektrik kokusu var",
        "trafo sigortası sürekli atıyor",
        "trafo bağlantı kablosu gevşemiş",
        "trafo aşırı yük altında çalışıyor",
    ],
    "direk_hasari": [
        "direk eğilmiş, devrilme riski var",
        "direk fırtınada hasar gördü",
        "direk temelinde çatlak oluşmuş",
        "direk kırılmış, yola yakın duruyor",
        "direk paslanmış, zayıflamış görünüyor",
        "direk üzerindeki izolatör kırık",
        "direk aracın çarpmasıyla eğrildi",
        "direk zemin kayması nedeniyle sallanıyor",
        "direk tepesindeki bağlantı gevşemiş",
        "direk gövdesinde derin çatlaklar var",
        "direk dibindeki toprak çökmüş",
        "direk üzerindeki kablo askısı kopmuş",
        "direk devrilmek üzere",
        "direk yıllardır bakım görmemiş, çürümüş",
        "direk elektrik hattını taşıyamıyor gibi görünüyor",
        "direk beton kaide kısmı parçalanmış",
        "direk rüzgarda ciddi şekilde sallanıyor",
    ],
    "kablo_kopmasi": [
        "hat koptu, bölgede elektrik yok",
        "kablo yere düşmüş, tehlikeli durum",
        "iletken tel kopmuş sarkıyor",
        "kablo bağlantısı gevşemiş, kıvılcım çıkıyor",
        "yer altı kablosu hasar görmüş",
        "kablo izolasyonu yırtılmış, çıplak tel görünüyor",
        "hat ağaç dalına takılıp kopmuş",
        "kablo direkten ayrılmış, sarkıyor",
        "elektrik kablosu yolun ortasına düşmüş",
        "hat kopukluğu nedeniyle bölge karanlıkta kaldı",
        "kablo kanalı açılmış, tel dışarıda kalmış",
        "iletken hat gerginliğini kaybetmiş, sarkmış",
        "kablo bir araç tarafından koparılmış",
        "yüksek gerilim hattı kopmuş, çevre tehlikeli",
        "kablo bağlantı kutusu hasar görmüş",
        "hat kopuk, kıvılcım saçıyor",
    ],
    "sayac_arizasi": [
        "sayaç ekranı çalışmıyor",
        "sayaçta yanlış ölçüm var",
        "sayaç kutusu hasarlı",
        "sayaç camı kırılmış",
        "sayaç hiç veri göstermiyor",
        "sayaç bağlantısı gevşemiş",
        "sayaç kutusunun kapağı kopmuş",
        "sayaç ekranında hatalı rakamlar var",
        "sayaç suya maruz kalmış, arızalanmış",
        "sayaçta ısınma tespit edildi",
        "sayaç mühürü kırılmış",
        "sayaç panodan sökülmüş",
        "sayaçtan sürekli hata sinyali geliyor",
        "sayaç eski, dijital göstergesi bozuk",
        "sayaç yanlış tüketim gösteriyor",
        "sayaç kutusu içi nem almış",
    ],
}

# Aciliyet sinyali taşıyan kelime/kalıplar -> öncelik='acil'.
URGENT_KEYWORDS = [
    "acil", "yanık kokusu", "devrilme riski", "tehlikeli", "hemen",
    "kıvılcım", "duman",
]
# Düşük öncelik sinyali taşıyan kelime/kalıplar -> öncelik='dusuk'.
LOW_PRIORITY_KEYWORDS = ["uzun süredir", "hafif", "küçük"]

# Cümleleri çoğaltmak için kullanılan önek/sonekler — bazıları bilinçli
# olarak yukarıdaki aciliyet/düşük-öncelik kelimelerini İÇERİR; bu sayede
# hem metin çeşitliliği hem de öncelik etiketleri için doğal bir dağılım
# üretilmiş olur (aynı temel arıza, farklı aciliyet ifadeleriyle).
PREFIXES = ["", "acil durum: ", "dikkat: ", "uzun süredir devam eden bir sorun: "]
SUFFIXES = [
    "",
    ", acil müdahale gerekiyor",
    ", hemen kontrol edilmeli",
    ", uzun süredir bu şekilde",
    ", küçük çaplı bir sorun gibi duruyor",
    ", hafif bir arıza olabilir",
    ", durum tehlikeli görünüyor",
    ", lütfen ekip gönderin",
    ", vatandaşlar şikayet ediyor",
]


def priority_for(text: str) -> str:
    lowered = text.lower()
    if any(keyword in lowered for keyword in URGENT_KEYWORDS):
        return "acil"
    if any(keyword in lowered for keyword in LOW_PRIORITY_KEYWORDS):
        return "dusuk"
    return "normal"


def build_variants(base_sentences: list[str]) -> list[str]:
    """Şablon cümlelerden önek/sonek kombinasyonlarıyla benzersiz varyasyonlar üretir."""
    variants = set()
    for base in base_sentences:
        variants.add(base)
        for suffix in SUFFIXES:
            if suffix:
                variants.add(f"{base}{suffix}")
        for prefix in PREFIXES:
            if prefix:
                variants.add(f"{prefix}{base}")
    return list(variants)


def main():
    rows = []
    for fault_type, base_sentences in BASE_TEMPLATES.items():
        variants = build_variants(base_sentences)
        random.shuffle(variants)

        target = random.randint(TARGET_MIN_PER_TYPE, TARGET_MAX_PER_TYPE)
        selected = variants[: min(target, len(variants))]

        for text in selected:
            rows.append({"text": text, "ariza_tipi": fault_type, "oncelik": priority_for(text)})

    df = pd.DataFrame(rows).sample(frac=1, random_state=42).reset_index(drop=True)
    df.to_csv("text_training_data.csv", index=False, encoding="utf-8")

    print(f"{len(df)} satırlık sentetik metin veri seti 'text_training_data.csv' olarak kaydedildi.")
    print("\nArıza tipine göre dağılım:")
    print(df["ariza_tipi"].value_counts())
    print("\nÖnceliğe göre dağılım:")
    print(df["oncelik"].value_counts())


if __name__ == "__main__":
    main()
