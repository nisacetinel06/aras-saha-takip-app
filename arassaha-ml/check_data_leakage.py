# Görüntü Tabanlı Hasar Tespiti (Modül 15) — veri sızıntısı (data leakage) kontrolü.
#
# GEREKÇE: Kaggle veri setinin açıklamasında "defective images created
# artificially" yazıyor — yani hasarlı görseller, muhtemelen sağlam
# fotoğrafların üzerine dijital olarak hasar eklenerek (ve/veya döndürme/kırpma
# gibi augmentation'larla ÇOĞALTILARAK) üretildi. organize_dataset.py'ın
# train/val/test bölmesi TEKİL GÖRSEL bazında rastgele yapıldığı için, aynı
# temel fotoğraftan türetilmiş yakın-kopya varyantlar farklı split'lere
# düşmüş olabilir — bu klasik bir train/test sızıntısıdır ve %100 test
# doğruluğunu YAPAY olarak şişirebilir (model genel "hasar" kavramını değil,
# belirli bir örneğin piksel imzasını ezberlemiş olabilir).
#
# İKİ AYRI kontrol yapılır:
#   1) MD5 hash eşleşmesi — BİREBİR AYNI dosyanın birden fazla split'te
#      görünmesi (kesin kanıt, hiçbir varsayıma dayanmaz).
#   2) İsimlendirme örüntüsü — ham veri setindeki dosya adlarına bakılarak
#      (bkz. aşağıdaki BASE_NAME_PATTERN) AYNI temel fotoğraftan türetilmiş
#      varyantlar (örn. pic_0.jpg, pic_0_0.jpg, pic_0_1.jpg — birebir aynı
#      olmayabilir ama görsel olarak çok yakın kopyalardır) tespit edilir ve
#      bunlardan kaçının farklı split'lere dağıldığı raporlanır. Bu, hash
#      eşleşmesinden DAHA GENİŞ bir ağ atar (biraz değiştirilmiş varyantları
#      da yakalar) ama bir isimlendirme VARSAYIMINA dayanır — bu yüzden hash
#      kontrolünden AYRI ve ek bir kontrol olarak sunulur.
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).parent
DATASET_DIR = BASE_DIR / "dataset"
RAW_DIR = BASE_DIR / "raw_dataset" / "processed_raw_data" / "train"
METADATA_PATH = BASE_DIR / "models" / "damage_model_metadata.json"

SPLITS = ("train", "val", "test")
LABELS = ("hasarli", "hasarsiz")

# organize_dataset.py, kopyaladığı her dosyayı "{ham_klasör_adı}__{orijinal_ad}"
# olarak yeniden adlandırıyordu (bkz. organize_dataset.py copy_split) — bu
# yüzden organize edilmiş bir dosya adından ham klasör adı ve orijinal ad
# GÜVENİLİR şekilde geri çıkarılabilir.
ORGANIZED_NAME_PATTERN = re.compile(r"^(?P<raw_dir>.+?)__(?P<original>.+)$")

# Ham dosya adlarındaki "taban id + opsiyonel varyant eki" örüntüsü — bkz.
# dosya başındaki not. pic_0.jpg -> taban '0', pic_0_1.jpg -> taban '0' (varyant '1').
# img_1023.jpg -> taban '1023' (varyant yok). Eşleşmeyen dosyalar kendi
# dosya adlarını taban kabul eder (eşleştirme yapılmaz, güvenli varsayım —
# olası bir sızıntıyı KAÇIRABİLİR ama asla YANLIŞ bir eşleşme UYDURMAZ).
BASE_NAME_PATTERN = re.compile(r"^(?P<prefix>pic|img)_(?P<base>\d+)(?:_\d+)?\.jpg$", re.IGNORECASE)


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def collect_organized_files():
    """dataset/{split}/{label}/*.jpg -> [(split, label, path), ...]"""
    entries = []
    for split in SPLITS:
        for label in LABELS:
            folder = DATASET_DIR / split / label
            if not folder.exists():
                continue
            for path in sorted(folder.glob("*.jpg")):
                entries.append((split, label, path))
    return entries


def check_hash_leakage(entries):
    print(f"\n=== 1) MD5 hash kontrolü ({len(entries)} organize edilmiş görsel) ===")
    hash_to_locations = defaultdict(list)
    for split, label, path in entries:
        digest = md5_of(path)
        hash_to_locations[digest].append((split, label, path.name))

    duplicate_groups = {h: locs for h, locs in hash_to_locations.items() if len(locs) > 1}
    cross_split_groups = {
        h: locs for h, locs in duplicate_groups.items()
        if len({split for split, _, _ in locs}) > 1
    }

    print(f"Toplam benzersiz hash: {len(hash_to_locations)}")
    print(f"Birden fazla dosyada görünen (duplike) hash sayısı: {len(duplicate_groups)}")
    print(f"Split'LER ARASI çakışan hash sayısı (GERÇEK SIZINTI): {len(cross_split_groups)}")

    if cross_split_groups:
        print("\nÖrnek çakışmalar (ilk 10):")
        for h, locs in list(cross_split_groups.items())[:10]:
            loc_str = ", ".join(f"{split}/{label}/{name}" for split, label, name in locs)
            print(f"  hash {h[:10]}...: {loc_str}")

    return cross_split_groups


def extract_base_key(organized_filename: str):
    """Organize edilmiş bir dosya adından (örn.
    '6_defective_disk_insulator__pic_0_1.jpg') (ham_klasör, taban_id) anahtarını
    çıkarır. Eşleşmezse None döner (bu dosya hiçbir varyant grubuna dahil edilmez)."""
    m = ORGANIZED_NAME_PATTERN.match(organized_filename)
    if not m:
        return None
    raw_dir, original = m.group("raw_dir"), m.group("original")
    base_m = BASE_NAME_PATTERN.match(original)
    if not base_m:
        return None
    return (raw_dir, base_m.group("prefix"), base_m.group("base"))


def check_naming_pattern_leakage(entries):
    print("\n=== 2) İsimlendirme örüntüsü (varyant grubu) kontrolü ===")
    base_to_locations = defaultdict(list)
    unmatched = 0
    for split, label, path in entries:
        key = extract_base_key(path.name)
        if key is None:
            unmatched += 1
            continue
        base_to_locations[key].append((split, label, path.name))

    print(f"Örüntüyle eşleşmeyen dosya sayısı (kontrol dışı): {unmatched}")

    variant_groups = {k: v for k, v in base_to_locations.items() if len(v) > 1}
    cross_split_variant_groups = {
        k: v for k, v in variant_groups.items()
        if len({split for split, _, _ in v}) > 1
    }
    affected_files = sum(len(v) for v in cross_split_variant_groups.values())

    print(f"Birden fazla varyantı olan taban görsel sayısı: {len(variant_groups)}")
    print(f"Varyantları FARKLI split'lere dağılmış taban görsel sayısı: {len(cross_split_variant_groups)}")
    print(f"Bundan etkilenen toplam dosya sayısı: {affected_files}")

    if cross_split_variant_groups:
        print("\nÖrnek çaprazlanmış varyant grupları (ilk 10):")
        for key, locs in list(cross_split_variant_groups.items())[:10]:
            loc_str = ", ".join(f"{split}/{label}/{name}" for split, label, name in locs)
            print(f"  {key}: {loc_str}")

    return cross_split_variant_groups


def main():
    entries = collect_organized_files()
    if not entries:
        print(f"UYARI: {DATASET_DIR} boş görünüyor — önce organize_dataset.py çalıştırılmalı.")
        return

    hash_leaks = check_hash_leakage(entries)
    naming_leaks = check_naming_pattern_leakage(entries)

    is_clean = not hash_leaks and not naming_leaks

    print("\n=== SONUÇ ===")
    if is_clean:
        print("TEMİZ: Ne birebir hash çakışması ne de isimlendirme örüntüsüne göre")
        print("split'ler arası varyant sızıntısı bulundu.")
    else:
        print(f"SIZINTI BULUNDU: {len(hash_leaks)} hash çakışması, "
              f"{len(naming_leaks)} çaprazlanmış varyant grubu.")
        print("organize_dataset.py'ın grup-bazlı (taban görsel) bölme yapacak şekilde")
        print("düzeltilmesi ve train_damage_model.py'ın SIFIRDAN yeniden çalıştırılması gerekiyor.")

    # models/damage_model_metadata.json varsa, bu kontrolün sonucunu ekler —
    # yoksa (henüz eğitim yapılmadıysa) yalnızca konsola yazar, hata vermez.
    if METADATA_PATH.exists():
        with open(METADATA_PATH, "r", encoding="utf-8") as f:
            metadata = json.load(f)
        metadata["data_leakage_check"] = {
            "hash_cross_split_collisions": len(hash_leaks),
            "naming_pattern_cross_split_variant_groups": len(naming_leaks),
            "clean": is_clean,
        }
        with open(METADATA_PATH, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)
        print(f"\n{METADATA_PATH} güncellendi (data_leakage_check alanı eklendi).")


if __name__ == "__main__":
    main()
