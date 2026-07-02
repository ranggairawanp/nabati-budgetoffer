# Budget Offering, Nabati One HCMS

Situs statis untuk penyusunan dan persetujuan Offering Letter, tersambung ke database bersama One HCMS. Terpisah dari FLK Online, tapi satu database.

## Alamat
- /offering, aplikasi. Root diarahkan ke sini.

## Isi paket, semua di root
offering.html, index.html, config.js, one_hcms_api.js, vercel.json, README.md.

## Deploy ke Vercel
1. Repo baru yang bersih, tanpa package.json, vite, atau folder src.
2. Unggah keenam berkas langsung ke root.
3. Import di Vercel, Framework Preset akan terbaca Other, Deploy.

## Alur
- Login lewat Supabase Auth. Peran menentukan maker atau approver.
- Maker mencari kandidat berstatus Lolos Seleksi, identitas tertarik dari FLK sebagai prefill baca saja.
- Maker mengisi grade, entity, posisi final, komponen kompensasi, dan panel Kalibrasi Upah, struktur internal, skala pasar eksternal, dan ekuitas internal grade dan divisi yang sama secara agregat berambang.
- Compa ratio, range penetration, dan market ratio dihitung langsung. Bila di luar rentang wajar, alasan wajib diisi dan ikut ke approver.
- Submit masuk rantai persetujuan berjenjang sesuai grade. Snapshot identitas dan kalibrasi dibekukan saat submit.

## Akun demo, password nabatiHC-123!
- cb.specialist@nabati.demo, maker grade dasar.
- windha.cps@nabati.demo, maker senior dan approver dasar.
- frans.cpo@nabati.demo, approver senior.
- groupceo@nabati.demo, approver grade 6B.

## Prasyarat database
Jalankan one_hcms_supabase_setup.sql lalu one_hcms_selection_gate.sql di project Supabase yang sama dengan FLK Online. Gate seleksi ditegakkan di database, hanya kandidat Lolos Seleksi yang bisa dibuatkan OL.
