# Roadmap Society Roleplay

Dokumen ini dibaca setiap sesi update otomatis (tiap 5 jam). Setiap sesi:
pilih SATU item teratas yang belum selesai, implementasikan, compile (0 error),
commit + push, lalu tandai selesai di file ini.

## Selesai

- [x] v1.0 — Inti: akun register/login (SHA256), UCP + karakter (maks 3), MySQL,
      rupiah, autosave, command dasar (/stats /uang /save /bantuan /setadmin /kick /ban)
- [x] v2.0 — Refactor modular: `Society_Main.pwn` + `Server_Libraries/`
      (Mysql/Mysql_Connect.inc, Utils/Utils_Color.pwn, Utils/Utils_Enum.pwn),
      dialog pakai easydialog, skema DB via `society.sql` (tanpa auto-create),
      enum `Society_Player`, repo berisi full server package (pawno, plugins, dsb.)
- [x] Sistem kebutuhan: textdraw makan/minum/stress (bar oldschool), decay tiap
      menit, efek lapar/haus/stress ke nyawa, command /makan & /minum,
      tersimpan di DB (kolom hunger/thirst/stress)

## Berikutnya — PRIORITAS (permintaan user 2026-10-13)

Desain acuan: pola standar komunitas SA-MP (bisnis/rumah/kendaraan dinamis via
DB + pickup/label 3D + dialog easydialog + textdraw oldschool-modern).
Struktur: modul baru di `Server_Libraries/<Nama>/`, skema di `society.sql`,
Bahasa Indonesia, compile 0 error, commit+push tiap item.

- [ ] **Dynamic Business**: tabel `businesses` (id, name, owner_char_id, type,
      price, profit, pos_x/y/z, locked). Admin: `/buatbisnis [nama] [tipe] [harga]`
      → pickup + label 3D. Pemain: `/belibisnis` (dekat pickup), `/binfo`
      (dialog: ambil keuntungan `/bambil`, kunci), `/jualbisnis`. Profit
      bertambah tiap payday bila ada pemilik.
- [ ] **Dynamic House**: tabel `houses` (id, owner_char_id, price, entrance
      pos, exit pos+interior, locked). Admin: `/buathouse [harga] [interior]`.
      Pemain: `/belirumah`, `/masukrumah` & `/keluarrumah` (via pickup),
      `/kuncirumah`. Label 3D: nama jalan + status (Dijual/Pemilik).
- [ ] **Private Vehicle**: tabel `player_vehicles` (id, char_id, model,
      pos_x/y/z, angle, color1, color2, plate, locked, fuel). Maks 2 per
      karakter. `/belikendaraan` (daftar model + harga, spawn di dekat pemain),
      `/vparkir` (simpan posisi), `/vkunci`, spawn otomatis saat karakter load,
      despawn saat disconnect. Textdraw kecil info kendaraan saat mengemudi.
- [ ] **Admin DB**: level admin SUDAH tersimpan di `accounts.admin`
      (via /setadmin). Tambahan: `/adminduty` (tandai on-duty, nama berwarna),
      `/admins` (daftar admin online + level), nama tiap level
      (1=Junior, 2=Senior, 3=Head, 4=Manager, 5=Owner).

## Berikutnya — umum

- [ ] Sistem payday: gaji tiap 1 jam in-game, bonus level, pajak
- [ ] Pekerjaan 1: supir bus (checkpoint + gaji per checkpoint)
- [ ] Pekerjaan 2: kurir paket (ambil & antar paket)
- [ ] Pekerjaan 3: penambang / pemancing (pilih salah satu, sistem sederhana)
- [ ] Sistem rumah: beli rumah, kunci/pintu, interior, simpan di DB
- [ ] Sistem kendaraan pribadi: beli, kunci, simpan posisi & modif di DB
- [ ] Sistem bank/ATM: setor, tarik, transfer antar karakter
- [ ] Sistem HP: SMS antar pemain, kontak sederhana
- [ ] Fraksi: LSPD (tahanan, denda, /arrest) — struktur dasar
- [ ] Fraksi: EMS/rumah sakit (rawat, /heal)
- [ ] Sistem bisnis: beli bisnis, ambil keuntungan per payday
- [ ] Inventory sederhana: item, /pakai
- [ ] UCP web (PHP): register & lihat karakter via browser — folder `ucp-web/`
- [ ] Anti-cheat dasar: deteksi airbreak/teleport, money hack check
- [ ] Sistem level/XP: naik level dari waktu bermain & pekerjaan

## Aturan setiap sesi

1. `git pull --rebase origin main` dulu sebelum mulai.
2. Semua teks/komentar Bahasa Indonesia, gaya oldschool.
3. Jangan hapus/ubah fitur yang sudah ada kecuali perbaikan bug.
4. Compile wajib 0 error: `pawncc-build/pawncc gamemodes/Society_Main.pwn -i repo/pawno/include -o gamemodes/Society_Main.amx` (path absolut: /home/hatch/workspace/society-rp/...).
5. Commit message Bahasa Indonesia yang deskriptif, langsung `git push origin main`.
6. Jangan pernah commit kredensial/password/token.
