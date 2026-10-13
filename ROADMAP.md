# Roadmap Society Roleplay

Dokumen ini dibaca setiap sesi update otomatis (tiap 5 jam). Setiap sesi:
pilih SATU item teratas yang belum selesai, implementasikan, compile (0 error),
commit + push, lalu tandai selesai di file ini.

## Selesai

- [x] v1.0 — Inti: akun register/login (SHA256), UCP + karakter (maks 3), MySQL,
      rupiah, autosave, command dasar (/stats /money /save /help /setadmin /kick /ban).
      `/stats` sudah dirombak 2026-10-13 menjadi menu dialog bertingkat:
      Informasi Umum, Keuangan (tunai + bank + total kekayaan),
      Kebutuhan (label Kenyang/Lapar, Segar/Haus, Santai/Stres Berat),
      Aset (jumlah bisnis & rumah milik pemain; kendaraan menyusul).
- [x] v2.0 — Refactor modular: `Society_Main.pwn` + `Server_Libraries/`
      (Mysql/Mysql_Connect.inc, Utils/Utils_Color.pwn, Utils/Utils_Enum.pwn),
      dialog pakai easydialog, skema DB via `society.sql` (tanpa auto-create),
      enum `Society_Player`, repo berisi full server package (pawno, plugins, dsb.)
- [x] Sistem kebutuhan: textdraw makan/drink/stress (bar oldschool), decay tiap
      menit, efek lapar/haus/stress ke nyawa, command /eat & /drink,
      tersimpan di DB (kolom hunger/thirst/stress)

## Berikutnya — PRIORITAS (permintaan user 2026-10-13)

Desain acuan: pola standar komunitas SA-MP (bisnis/rumah/kendaraan dinamis via
DB + pickup/label 3D + dialog easydialog + textdraw oldschool-modern).
Struktur: modul baru di `Server_Libraries/<Nama>/`, skema di `society.sql`,
Bahasa Indonesia, compile 0 error, commit+push tiap item.

- [x] **Dynamic Business** (selesai 2026-10-13): tabel `businesses`
      (id, name, owner_char_id, type, price, profit, pos_x/y/z, locked).
      Admin: `/createbisnis [nama] [tipe] [harga]` → pickup + label 3D.
      Pemain: `/buybusiness` (dekat pickup), `/bizinfo`
      (dialog: ambil keuntungan `/bizwithdraw`, kunci), `/sellbusiness`
      (kembali 70%). Profit bertambah tiap payday (1 jam) bila ada
      pemilik, pemilik online diberi tahu. Modul:
      `Server_Libraries/Business/Business_System.pwn`.
- [x] **Dynamic House** (selesai 2026-10-14): tabel `houses`
      (id, owner_char_id, price, ent_x/y/z, ent_int, ent_vw,
      exit_x/y/z, exit_int, locked). Admin: `/createhouse [harga]`
      2 langkah — berdiri di pintu MASUK ketik perintah, lalu pergi ke
      titik pintu KELUAR di dalam interior dan ketik `/createhouse` lagi.
      Pemain: `/buyhouse`, `/enterhouse` & `/exithouse`,
      `/lockhouse`, `/sellhouse` (kembali 70%), `/houseinfo` (dialog
      kelola: kunci/buka, jual). Virtual world unik per rumah
      (= id DB) supaya penghuni rumah berbeda tidak saling melihat.
      Label 3D: nomor rumah + harga + status (Dijual/Pemilik) +
      [Terkunci]/[Terbuka]. Jumlah rumah tampil di /stats > Aset.
      Modul: `Server_Libraries/House/House_System.pwn`.
- [ ] **Private Vehicle**: tabel `player_vehicles` (id, char_id, model,
      pos_x/y/z, angle, color1, color2, plate, locked, fuel). Maks 2 per
      karakter. `/buyvehicle` (daftar model + harga, spawn di dekat pemain),
      `/vpark` (simpan posisi), `/vlock`, spawn otomatis saat karakter load,
      despawn saat disconnect. Textdraw kecil info kendaraan saat mengemudi.
- [ ] **Admin DB**: level admin SUDAH tersimpan di `accounts.admin`
      (via /setadmin). Tambahan: `/adminduty` (tandai on-duty, nama berwarna),
      `/admins` (daftar admin online + level), nama tiap level
      (1=Junior, 2=Senior, 3=Head, 4=Manager, 5=Owner).

## Berikutnya — BATCH BARU (permintaan user 2026-10-13)

Dikerjakan SETELAH 4 item prioritas, SEBELUM batch fitur review server.
Gaya tetap: oldschool-modern, textdraw, Bahasa Indonesia, easydialog,
compile 0 error, commit+push per item.

- [ ] **Dynamic Faction**: tabel `factions` (id, name, type
      [polisi/EMS/pemerintah/montir/news], color, spawn pos, leader_char_id,
      kas). Admin `/createfaction` → 3D label markas. `/finvite`, `/fkick`,
      rank, `/f` chat fraksi, `/duty` ambil seragam & senjata dinas.
- [ ] **Dynamic Workshop**: tabel `workshops` (id, owner_char_id, name,
      pos, price, profit). Bengkel milik pemain: `/buyworkshop`,
      pelanggan `/mod` (warna, komponen, neon) & `/repair`, pemilik
      ambil profit `/wswithdraw`. Label 3D nama bengkel.
- [ ] **Dynamic Garage Kota**: tabel `garages` (id, name, pos, fee).
      Garasi umum: `/garage` simpan kendaraan pribadi (despawn + tercatat),
      dialog ambil kembali. Solusi parkir saat slot jalanan penuh.
- [ ] **Dynamic Family/Gangster**: tabel `families` (id, name, color,
      leader_char_id, kas). `/createfamily [nama]` (bayar), `/faminvite`,
      `/famkick`, rank, `/fam` chat, warna nama & kendaraan keluarga.
      Basis badside untuk turf/gang war nanti.
- [ ] **Dynamic Zone (Greenzone)**: tabel `zones` (id, name, min_x/min_y/
      max_x/max_y, type). Admin `/createzone [nama] [tipe]` → area persegi.
      Greenzone: damage & tembak dinonaktifkan di dalam area (cek
      OnPlayerTakeDamage/OnPlayerWeaponShot). Textdraw "GREEMZONE" saat
      masuk area.
- [ ] **Dynamic Dealer**: tabel `dealers` (id, name, pos, type
      [kendaraan]). Showroom: `/dealer` → dialog daftar kendaraan + harga,
      test drive (spawn sementara), beli langsung jadi private vehicle.
- [ ] **Dynamic Pom**: tabel `gasstations` (id, owner_char_id, name, pos,
      price_per_liter, stock). `/buygasstation`, pemilik set harga `/setfuelprice`,
      pemain `/refuel` di pompa (butuh sistem bensin). Label 3D nama +
      harga.
- [ ] **Dynamic Door**: tabel `doors` (id, owner_type [house/business/
      faction], owner_id, name, ext pos, int pos+interior, locked).
      Admin/pemilik `/createdoor` → pintu masuk/keluar interior apa pun
      (rumah, bisnis, markas). `/lockdoor`, pickup + label 3D.
- [ ] **Inventory System (textdraw)**: tabel `inventory`
      (char_id, item, amount). `/inv` → UI PlayerTextDraw grid slot
      klik (pakai SelectTextDraw): pakai/drop/beri item (makanan, minuman,
      obat, senjata, narkoba, ikan, ore). Kapasitas terbatas per slot.

## Berikutnya — FITUR SERU DARI REVIEW SERVER (permintaan user 2026-10-13)

Dikerjakan SETELAH 4 item prioritas di atas. Referensi: fitur-fitur yang
paling sering di-highlight di review server SA-MP Indonesia (Ace Pride
Roleplay, Ravage Roleplay, dll). Gaya tetap: oldschool-modern, textdraw,
Bahasa Indonesia, easydialog, compile 0 error, commit+push per item.

### Kriminal (badside)
- [ ] **Sistem Rampok**: rampok bank/toko/ATM. `/rob` di titik rampok →
      progress bar textdraw (waktu berjalan), alarm ke polisi online, cooldown
      per titik, hasil uang kotor. Tabel `robbery_spots`.
- [ ] **Black Market**: titik tersembunyi (acak) beli senjata & narkoba.
      `/bm` di dekat titik → dialog daftar barang + harga. Stok terbatas.
- [ ] **Narkoba**: `/plant` (benih, butuh lahan), tumbuh real-time,
      `/harvest`, `/selldrugs` ke bandar/pemain. Risiko: polisi bisa
      `/seize`. Tabel `drug_plants`.

### Pekerjaan (goodside)
- [ ] **Job Sopir Truck**: `/truckjob` → ambil kargo, checkpoint
      rute antar kota, bayaran per jarak. Textdraw info kargo & jarak.
- [ ] **Job Mancing**: `/fish` di dekat air → timing minigame via
      textdraw, dapat ikan (jenis + berat), `/sellfish`.
- [ ] **Job Nambang**: tambang di LV → `/mine` ayun pickaxe (anim),
      dapat ore, `/sellore`.
- [ ] **Job Sopir Taxi**: `/taxi` duty → argo textdraw berjalan per jarak
      saat ada penumpang, `/meter`.

### Kendaraan
- [ ] **Sistem Bensin**: kendaraan punya fuel, berkurang saat dikendarai.
      Pom bensin: `/refuel` di dekat pompa, bayar per liter. Textdraw
      indikator bensin saat mengemudi. (Butuh kolom `fuel` di
      `player_vehicles`.)
- [ ] **Asuransi Kendaraan**: kendaraan hancur/tenggelam → `/insurance`
      tebus dengan biaya, spawn kembali di garasi/pom terdekat.
- [ ] **Bagasi & Kap**: `/trunk` (simpan/ambil barang: senjata, narkoba,
      ikan) dan `/hood` (buka/tutup kap & bagasi visual). Tabel
      `vehicle_trunk`.

### Sosial & QoL
- [ ] **Animasi**: `/anim` → dialog kategori, 100+ animasi (duduk, dansa,
      tiarap, dll). `/stopanim`.
- [ ] **Toys/Aksesoris**: `/toy` pasang aksesoris (topi, bandana, kacamata),
      `/helmet` di motor, `/mask` sembunyikan nama (nametag off).
- [ ] **Boombox**: `/boombox` taruh boombox → streaming musik URL di
      sekitar, `/stopmusic`. (Pakai PlayAudioStreamForPlayer.)
- [ ] **Nikah**: `/propose [id]` → target `/accept`, status pasangan di
      `/stats`, `/divorce`.
- [ ] **ATM Dinamis**: objek ATM tersebar → `/atm` tarik/setor/cek saldo
      di mana pun. (Butuh sistem bank/tabungan — gabung di item ini.)
- [ ] **Daily Reward**: bonus login harian beruntun (streak), klaim via
      dialog saat login. Tabel/kolom `login_streak`, `last_login`.
- [ ] **Dadu**: `/dice [taruhan] [id]` judi dadu vs pemain, pemenang ambil
      pot. Batas taruhan.
- [ ] **Shareloc**: `/shareloc [id]` kirim checkpoint lokasi ke pemain
      lain (misi, jemputan).

### Fraksi & hukum
- [ ] **Wanted & Penjara**: wanted level naik saat kriminal terlihat,
      polisi `/arrest [id]` → penjara timed di sel, `/release`. Tabel
      `jail` atau kolom `jail_time`.
- [ ] **Dynamic Gate**: `/creategate` (admin/fraksi) → gate otomatis buka
      via `/gate` atau tombol klakson di dekatnya. Tabel `gates`.

## Berikutnya — umum

- [ ] Sistem payday: gaji tiap 1 jam in-game, bonus level, pajak
- [ ] Pekerjaan 1: supir bus (checkpoint + gaji per checkpoint)
- [ ] Pekerjaan 2: kurir paket (ambil & antar paket)
- [ ] Pekerjaan 3: penambang / pemancing (pilih salah satu, sistem sederhana)
- [x] Sistem rumah: beli rumah, kunci/pintu, interior, simpan di DB (selesai 2026-10-14 via Dynamic House)
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
