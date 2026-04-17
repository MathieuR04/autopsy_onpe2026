"""
scrape_missing.py
Scrapes only the table IDs that are NOT yet in lima_2026.csv.

Usage:
  python scrape_missing.py
  python scrape_missing.py --workers 100

Expects lima_2026.csv in the same directory.
Appends new rows directly into lima_2026.csv.
"""

import requests
import pdfplumber
import pandas as pd
import re
import io
import argparse
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
from tqdm import tqdm

BASE_URL   = "https://actas-stae.onpe.gob.pe"
OUT_FILE   = "lima_2026.csv"
TIMEOUT    = 15
HEADERS    = {"User-Agent": "Mozilla/5.0"}
write_lock = Lock()

def file_exists(path):
    return os.path.isfile(path)

def fetch_pdf(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
        if r.status_code == 200:
            return io.BytesIO(r.content)
        return None
    except Exception:
        return None

def parse_install(pdf_bytes, table_id):
    try:
        with pdfplumber.open(pdf_bytes) as pdf:
            text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        loc_line = re.search(
            r'DEPARTAMENTO\s+PROVINCIA\s+DISTRITO\s*\n\s*'
            r'([A-ZÁÉÍÓÚÑÜ][A-ZÁÉÍÓÚÑÜa-záéíóúñü\s]+?)\s*\n',
            text
        )
        if loc_line:
            parts = loc_line.group(1).strip().split()
            dept_val     = parts[0] if len(parts) > 0 else None
            province_val = parts[1] if len(parts) > 1 else None
            district_val = " ".join(parts[2:]) if len(parts) > 2 else None
        else:
            dept_val = province_val = district_val = None

        time_ = re.search(
            r'([\d]{1,2}:[\d]{2}\s*[ap]\.\s*m\.)\s*\nSiendo las',
            text, re.IGNORECASE
        )

        return {
            "table_id":          int(table_id),
            "department":        dept_val,
            "province":          province_val,
            "district":          district_val,
            "installation_time": time_.group(1).strip() if time_ else None,
        }
    except Exception:
        return None

NON_PARTY_LINES = {
    "TOTAL DE ELECTORES HÁBILES", "TOTAL DE ELECTORES HABILES",
    "TOTAL DE CIUDADANOS QUE VOTARON", "TOTAL DE VOTOS EMITIDOS",
    "VOTOS EN BLANCO", "VOTOS NULOS", "VOTOS IMPUGNADOS",
    "ORGANIZACIONES POLÍTICAS", "ORGANIZACIONES POLITICAS", "TOTAL DE VOTOS",
    "OBSERVACIONES", "NO HAY OBSERVACIONES",
}

def parse_votes(pdf_bytes):
    try:
        with pdfplumber.open(pdf_bytes) as pdf:
            text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        eligible = re.search(r'TOTAL DE ELECTORES H[ÁA]BILES\s+(\d+)', text)
        voted    = re.search(r'TOTAL DE CIUDADANOS QUE VOTARON\s+(\d+)', text)

        party_votes = {}
        for match in re.finditer(
            r'^\d{1,2}\s+'
            r'([A-ZÁÉÍÓÚÑÜ\u00C0-\u024F][A-ZÁÉÍÓÚÑÜ\u00C0-\u024Fa-záéíóúñü\s\-–,\.\/\(\)]+?)'
            r'\s+(\d+)'
            r'\s+\d{1,2}\s*$',
            text, re.MULTILINE
        ):
            party = match.group(1).strip().upper()
            if party in NON_PARTY_LINES or len(party) < 3:
                continue
            party_votes[party] = int(match.group(2))

        return {
            "eligible_voters": int(eligible.group(1)) if eligible else None,
            "total_voted":     int(voted.group(1))    if voted    else None,
            "rp":  party_votes.get("RENOVACIÓN POPULAR", party_votes.get("RENOVACION POPULAR", None)),
            "jpp": party_votes.get("JUNTOS POR EL PERÚ", party_votes.get("JUNTOS POR EL PERU", None)),
        }
    except Exception:
        return None

def process_table(n):
    table_id = f"{n:06d}"

    install_pdf = fetch_pdf(f"{BASE_URL}/AIPRE{table_id}_STAE.pdf")
    if install_pdf is None:
        return None

    votes_pdf = fetch_pdf(f"{BASE_URL}/AEPRE{table_id}_STAE.pdf")
    if votes_pdf is None:
        return None

    install = parse_install(install_pdf, table_id)
    votes   = parse_votes(votes_pdf)

    if not install or not votes:
        return None
    if not install.get("district") or votes.get("eligible_voters") is None:
        return None

    row = {**install, **votes}

    with write_lock:
        pd.DataFrame([row]).to_csv(
            OUT_FILE, mode="a",
            header=not file_exists(OUT_FILE),
            index=False
        )

    return table_id

def main():
    parser = argparse.ArgumentParser(description="Scrape missing ONPE tables")
    parser.add_argument("--workers", type=int, default=100)
    args = parser.parse_args()

    # Load IDs already in lima_2026.csv
    if not file_exists(OUT_FILE):
        print(f"ERROR: {OUT_FILE} not found. Run from the autopsy folder.")
        return

    existing = set(
        pd.read_csv(OUT_FILE, usecols=["table_id"], encoding="latin1")
        ["table_id"].astype(int).tolist()
    )
    print(f"Already have {len(existing):,} tables in {OUT_FILE}.")

    # All candidate IDs 0–99999
    all_ids   = list(range(0, 100_000))
    to_check  = [n for n in all_ids if n not in existing]
    print(f"Will check {len(to_check):,} IDs not yet in the file.")
    print(f"Workers: {args.workers}\n")

    found = 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(process_table, n): n for n in to_check}
        with tqdm(total=len(to_check), unit="id", desc="Checking") as pbar:
            for future in as_completed(futures):
                result = future.result()
                if result:
                    found += 1
                    pbar.set_postfix(found=found)
                pbar.update(1)

    print(f"\nDone. {found:,} new tables found and added to {OUT_FILE}.")

if __name__ == "__main__":
    main()
