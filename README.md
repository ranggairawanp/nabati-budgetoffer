# Budget Offering, One HCMS

Aplikasi penyusunan dan persetujuan Offering Letter untuk Nabati Group.
Statis, tanpa build step. Deploy sebagai Framework Other di Vercel.

## Isi paket
- index.html, pengalihan ke /offering
- offering.html, aplikasi utama
- config.js, koneksi Supabase
- one_hcms_api.js, lapisan integrasi, mode cloud dan lokal
- one_hcms_comp_master.sql, master struktur upah dan benchmark
- one_hcms_comben_direct.sql, jalur inisiasi OL langsung oleh Comben
- one_hcms_ol_fill.py, mesin pengisi template Offering Letter resmi
- vercel.json, konfigurasi rute

## Cara deploy
Unggah seluruh berkas di root repo. Jangan tambahkan package.json atau folder src.
Di Vercel, pilih Framework Preset Other, tanpa build command.

## Akun demo
onehcms, kata sandi nabatiHC-123!
Peran, C&B Specialist, Corporate People Services, Chief People Officer, Group CEO.

## Fitur utama
- Susun OL empat blok, Basic Data, Komponen Kompensasi, Kalibrasi Upah, Total per tahun
- Komponen kompensasi resmi per tier grade dan gender, mengikuti template KSNI 2026
- Status kekaryawanan otomatis, Grade 3 PKWT, Grade 4 di plant PKWT, selain itu PKWTT
- Lokasi kerja berupa daftar, kelompok Plant, Head Office, dan Kota, tipe lokasi otomatis
- Business Unit untuk entity Indonesia
- Komponen tambahan sampai tiga baris, penambah atau pengurang, dengan penanda tampil di surat
- Potongan BPJS Ketenagakerjaan dan Kesehatan terpisah, batas upah sebagai parameter
- Skenario negosiasi sampai empat, dengan pemilih skenario final yang menjadi OL
- Kalibrasi upah, struktur internal dan benchmark pasar, dengan ambang privasi peer minimal lima
- Rantai persetujuan berjenjang mengikuti grade
- Jalur inisiasi OL langsung oleh Comben, wajib MPP Index dan MPN Number

## Mesin pengisi Offering Letter
one_hcms_ol_fill.py mengisi template resmi 2026, memilih sheet menurut tier grade dan gender,
mempertahankan rumus Total dan THR, serta mencetak komponen tambahan yang ditandai tampil di surat.
