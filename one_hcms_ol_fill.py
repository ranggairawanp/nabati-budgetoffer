"""
One HCMS, Offering Letter fill engine.
Maps an approved OL payload to the official KSNI 2026 Excel template, routed by
grade tier and gender. Label based cell lookup, so it tolerates row shifts
between tiers. Keeps Total Remunerasi and THR as template formulas, and keeps
all formatting. Produces a single sheet final letter.

Usage:
  from one_hcms_ol_fill import fill_ol
  fill_ol("2026_Offering_Template_KSNI_revA.xlsx", data, "OL_final.xlsx")

data = {
  "grade": "5A", "gender": "L" | "P",
  "nomorSeq": "01471", "signDate": "2026-08-01",
  "nama": "...", "alamat": "...",
  "position": "...", "division": "...", "golongan": "5A", "location": "Bandung",
  "components": { "Gaji Pokok": 15000000, "Tunjangan Jabatan": 5000000, ... }
}
"""
import openpyxl

ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
BULAN = ["", "Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
         "Agustus", "September", "Oktober", "November", "Desember"]


def ol_tier(grade):
    try:
        n = int("".join(ch for ch in str(grade) if ch.isdigit())[:1])
    except Exception:
        n = 0
    if n >= 5:
        return "G5UP"
    if n == 4:
        return "G4"
    if n == 3:
        return "G3"
    return "LOW"


def ol_sheet(grade, gender):
    t = ol_tier(grade)
    if t == "G5UP":
        return "Standard Grade 5 Up"
    if t == "G4":
        return "Standard Grade 4 (L)" if gender == "L" else "Standard Grade 4 (P)"
    return "Standard Grade 3"


def gen_nomor(seq, date_iso):
    y, m, d = [int(x) for x in date_iso.split("-")]
    return str(seq) + "/KSNI-HRD/OFF/" + ROMAN[m] + "/" + str(y)


def long_date(date_iso):
    y, m, d = [int(x) for x in date_iso.split("-")]
    return str(d) + " " + BULAN[m] + " " + str(y)


def _rows_with(ws, col, text, exact=False):
    hits = []
    for r in range(1, ws.max_row + 1):
        v = ws.cell(row=r, column=col).value
        if v is None:
            continue
        s = str(v).strip()
        if (s == text) if exact else (s.startswith(text)):
            hits.append(r)
    return hits


def _set_offer(ws, label_col_b, value):
    # offer fields, label in col B, value in col E
    hits = _rows_with(ws, 2, label_col_b)
    if hits:
        ws.cell(row=hits[0], column=5, value=value)


def fill_ol(template_path, data, out_path):
    wb = openpyxl.load_workbook(template_path)
    sheet = ol_sheet(data.get("grade"), data.get("gender"))
    ws = wb[sheet]

    # 1. Nomor, cell in col A containing KSNI-HRD
    nomor = data.get("nomor") or gen_nomor(data.get("nomorSeq", "00000"), data.get("signDate", "2026-01-01"))
    for r in range(1, ws.max_row + 1):
        v = ws.cell(row=r, column=1).value
        if v and "KSNI-HRD" in str(v):
            ws.cell(row=r, column=1, value=nomor)
            break

    # 2. Identity, Pihak Kedua. Nama appears twice in col A, take the last.
    nama_rows = _rows_with(ws, 1, "Nama", exact=True)
    if nama_rows:
        ws.cell(row=nama_rows[-1], column=5, value=data.get("nama", ""))
    alamat_rows = _rows_with(ws, 1, "Alamat", exact=True)
    if alamat_rows:
        ws.cell(row=alamat_rows[0], column=5, value=data.get("alamat", ""))

    # 3. Offer fields, label col B, value col E
    _set_offer(ws, "Posisi Jabatan", data.get("position", ""))
    _set_offer(ws, "Divisi", data.get("division", ""))
    _set_offer(ws, "Golongan", data.get("golongan", data.get("grade", "")))
    _set_offer(ws, "Lokasi Kerja", data.get("location", "Bandung"))
    if data.get("status"):
        _set_offer(ws, "Status Kekaryawanan", data.get("status"))

    # 4. Components, label col C, besaran col F. Keep Total and THR formulas.
    comps = data.get("components", {})
    for label, amount in comps.items():
        for r in range(1, ws.max_row + 1):
            v = ws.cell(row=r, column=3).value
            if v and str(v).strip().startswith(label):
                ws.cell(row=r, column=6, value=amount)
                break

    # 5. Sign date, cell in col G containing Bandung,
    for r in range(1, ws.max_row + 1):
        v = ws.cell(row=r, column=7).value
        if v and str(v).strip().startswith("Bandung,"):
            ws.cell(row=r, column=7, value="Bandung,  " + long_date(data.get("signDate", "2026-01-01")))
            break

    # 6. Single sheet final letter, drop the other tiers
    for other in list(wb.sheetnames):
        if other != sheet:
            del wb[other]

    wb.save(out_path)
    return {"sheet": sheet, "nomor": nomor, "out": out_path}
