"""
Modül 15 (Görüntü Tabanlı Hasar Tespiti) — GERÇEK DÜNYA doğrulama seti.

TEST-20 GÜNCELLEMESİ: Kaggle "Power Line Components Images Dataset" (bkz.
train_damage_model.py dosya başı notu) temiz/kontrollü koşullarda çekilmiş
görsellerden oluşuyor. Modelin gerçek sahada (değişken ışık/açı/kalite)
gerçekten ne kadar başarılı olduğunu ÖLÇMEK için, Wikimedia Commons'tan
(CC0/CC-BY/CC-BY-SA lisanslı, serbestçe kullanılabilir) 20-30 adet GERÇEKTEN
çeşitli elektrik ekipmanı fotoğrafı indirilir.

ÖNEMLİ — bu görseller EĞİTİME KATILMAZ: yalnızca `dataset/real_world_validation/`
altına, train/val/test'in TAMAMEN DIŞINDA ayrı bir klasöre indirilir.
train_damage_model.py bu klasörü SADECE ekstra bir değerlendirme (evaluate)
adımı olarak kullanır — modelin ağırlıklarını hiçbir şekilde etkilemez.

Kullanım:
    python build_real_world_validation_set.py

Çıktı:
    dataset/real_world_validation/hasarli/*.jpg
    dataset/real_world_validation/hasarsiz/*.jpg
    dataset/real_world_validation/attribution.json  (kaynak/lisans/yazar kaydı —
        Wikimedia Commons görsellerini kullanmanın şartı budur, atıf zorunludur)
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).parent
OUT_DIR = BASE_DIR / "dataset" / "real_world_validation"
API_URL = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "ArasSaha-ML-Research/1.0 (staj projesi; egitim amacli, kar amaci gutmeyen)"

# CC0/Public Domain/CC-BY/CC-BY-SA hepsi serbestçe kullanılabilir (atıfla).
ACCEPTABLE_LICENSES = ("cc0", "cc-by", "cc-by-sa", "public domain", "pd")

# (arama sorgusu, hedef klasör, kaç adet)
# "hasarli" (damaged) sorguları fırtına/kaza kaynaklı GERÇEK hasar aramaya
# odaklanır; "hasarsiz" (undamaged) sorguları normal servis/kurulum halindeki
# ekipmanı hedefler. ArasSaha'nın kendi ekipman tipleriyle (trafo/kesici/
# direk/sayaç) örtüşecek şekilde seçildi.
QUERIES = [
    ("storm damaged electrical transformer", "hasarli", 4),
    ("fallen utility pole storm damage", "hasarli", 4),
    ("damaged power line storm", "hasarli", 4),
    ("cracked electrical insulator damaged", "hasarli", 3),
    ("burnt electrical transformer explosion", "hasarli", 3),
    ("distribution transformer pole mounted", "hasarsiz", 4),
    ("electricity meter residential", "hasarsiz", 4),
    ("wooden utility pole power lines", "hasarsiz", 4),
    ("electrical substation circuit breaker", "hasarsiz", 4),
]


def api_get(params: dict, retries: int = 5) -> dict:
    params = {**params, "format": "json"}
    url = f"{API_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < retries - 1:
                wait = 5 * (attempt + 1)
                print(f"  (429 - hız sınırı, {wait}s bekleniyor...)")
                time.sleep(wait)
                continue
            raise
    raise RuntimeError("api_get: tüm denemeler tükendi")


def search_files(query: str, limit: int) -> list[str]:
    data = api_get(
        {
            "action": "query",
            "list": "search",
            "srsearch": f"{query} filetype:bitmap",
            "srnamespace": 6,  # File: namespace
            "srlimit": limit * 3,  # fazladan iste — bir kısmı lisans/format nedeniyle elenecek
        }
    )
    return [r["title"] for r in data.get("query", {}).get("search", [])]


def get_image_infos_batch(titles: list[str]) -> dict[str, dict]:
    """Wikimedia'nın 429 uyarısında ÖNERDİĞİ gibi ("contact noc@wikimedia.org
    to discuss a less disruptive approach") — her başlık için AYRI bir istek
    yerine, MediaWiki API'sinin '|' ile ayrılmış çoklu-başlık desteğini
    kullanarak TEK istekte (en fazla 50 başlık) tüm imageinfo'ları çeker. Bu,
    API'ye yapılan toplam istek sayısını ~N'den 1'e indirir."""
    if not titles:
        return {}
    data = api_get(
        {
            "action": "query",
            "titles": "|".join(titles[:50]),
            "prop": "imageinfo",
            "iiprop": "url|extmetadata|size|mime",
            # Wikimedia'nın 429 mesajındaki önerisi: küçük thumbnail boyutu
            # istemek sunucu tarafında daha az yük yaratır.
            "iiurlwidth": 800,
        }
    )
    pages = data.get("query", {}).get("pages", {})
    result = {}
    for page in pages.values():
        title = page.get("title")
        infos = page.get("imageinfo")
        if title and infos:
            result[title] = infos[0]
    return result


def license_ok(imageinfo: dict) -> bool:
    meta = imageinfo.get("extmetadata", {})
    license_short = str(meta.get("LicenseShortName", {}).get("value", "")).lower()
    return any(tag in license_short for tag in ACCEPTABLE_LICENSES)


def download(url: str, dest: Path, retries: int = 4) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp, open(dest, "wb") as f:
                f.write(resp.read())
            return
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < retries - 1:
                wait = 6 * (attempt + 1)
                print(f"  (indirme 429 - {wait}s bekleniyor...)")
                time.sleep(wait)
                continue
            raise


def main():
    # attribution.json zaten varsa (önceki bir kısmi çalıştırmadan kalan),
    # onu OKUYUP devam ediyoruz — Wikimedia'nın 429 yanıtında AÇIKÇA "daha az
    # yıkıcı bir yaklaşım" istemesi üzerine, script BAŞTAN başlamak yerine
    # zaten indirilenleri KORUYUP yalnızca eksik kalan kategorileri tamamlar.
    attribution_path = OUT_DIR / "attribution.json"
    for label in ("hasarli", "hasarsiz"):
        (OUT_DIR / label).mkdir(parents=True, exist_ok=True)

    attribution = []
    if attribution_path.exists():
        attribution = json.loads(attribution_path.read_text(encoding="utf-8"))
    counts = {"hasarli": 0, "hasarsiz": 0}
    for entry in attribution:
        counts[entry["label"]] += 1
    already_downloaded_titles = {entry["title"] for entry in attribution}

    for query, label, limit in QUERIES:
        collected = sum(1 for e in attribution if e["label"] == label and query in e.get("query", ""))
        try:
            titles = [t for t in search_files(query, limit) if t not in already_downloaded_titles]
        except Exception as exc:  # ağ hatası — bu sorguyu atla, diğerlerine devam et
            print(f"[UYARI] arama başarısız ({query!r}): {exc}")
            continue
        time.sleep(3.0)

        if not titles:
            continue
        try:
            infos_by_title = get_image_infos_batch(titles)
        except Exception as exc:
            print(f"[UYARI] toplu imageinfo alınamadı ({query!r}): {exc}")
            continue

        for title in titles:
            if collected >= limit:
                break
            info = infos_by_title.get(title)
            if not info:
                continue
            mime = info.get("mime", "")
            if mime not in ("image/jpeg", "image/png"):
                continue
            # Çok küçük/thumbnail benzeri görselleri atla (gerçekçi bir telefon
            # fotoğrafı ölçeğinde olsun diye kabaca bir alt sınır) — orijinal
            # boyut (width/height), iiurlwidth'ten ETKİLENMEZ.
            if info.get("width", 0) < 300 or info.get("height", 0) < 300:
                continue
            if not license_ok(info):
                continue

            ext = ".jpg" if mime == "image/jpeg" else ".png"
            safe_name = "".join(c if c.isalnum() else "_" for c in title)[:80]
            dest = OUT_DIR / label / f"{safe_name}{ext}"
            if dest.exists():
                continue

            # Wikimedia'nın 429 mesajındaki önerisi: tam çözünürlük yerine
            # thumbnail indir (iiurlwidth=800 ile istenen 'thumburl').
            download_url = info.get("thumburl", info["url"])
            try:
                download(download_url, dest)
            except Exception as exc:
                print(f"[UYARI] indirilemedi ({title!r}): {exc}")
                continue

            meta = info.get("extmetadata", {})
            attribution.append(
                {
                    "title": title,
                    "query": query,
                    "label": label,
                    "file": str(dest.relative_to(BASE_DIR)),
                    "source_url": info.get("descriptionurl", info["url"]),
                    "license": meta.get("LicenseShortName", {}).get("value", "bilinmiyor"),
                    "author": meta.get("Artist", {}).get("value", "bilinmiyor"),
                }
            )
            collected += 1
            counts[label] += 1
            print(f"[{label}] indirildi: {title}")
            # Her attribution güncellemesinde diske de yaz — script yarıda
            # kesilse (rate limit, ağ hatası) bile o ana kadarki ilerleme
            # KAYBOLMAZ, bir sonraki çalıştırma kaldığı yerden devam eder.
            attribution_path.write_text(
                json.dumps(attribution, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            time.sleep(2.0)  # Wikimedia API'sine karşı nazik davran (429'lardan kaçınmak için)

        time.sleep(3.0)  # sorgular arası ek bekleme

    with open(OUT_DIR / "attribution.json", "w", encoding="utf-8") as f:
        json.dump(attribution, f, ensure_ascii=False, indent=2)

    print(f"\nToplam indirilen: hasarli={counts['hasarli']}, hasarsiz={counts['hasarsiz']}")
    print(f"Atıf kaydı: {OUT_DIR / 'attribution.json'}")


if __name__ == "__main__":
    main()
