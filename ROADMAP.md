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
      (id, owner_char_id, price, type, location, ent_x/y/z, ent_int,
      ent_vw, exit_x/y/z, exit_int, locked). Admin: `/createhouse
      [harga] [tipe] [lokasi]` 2 langkah (tipe 0=Small 1=Medium 2=Large;
      lokasi = nama area). Pemain: `/buyhouse`, `/lockhouse`,
      `/sellhouse` (kembali 70%), `/houseinfo` (dialog kelola).
      Masuk/keluar rumah pakai tombol ENTER (F) — tanpa command.
      Tombol ENTER di dekat bisnis: dialog beli (dijual), kelola
      (milik sendiri), atau info (milik orang lain). Virtual world unik
      per rumah (= id DB). Label 3D format custom user: hijau `[ID:x]`
      + `This House For Sell`, putih `Location:` kuning nama lokasi,
      putih `Type:` kuning Small/Medium/Large, aksi `/buyhouse`;
      bila dimiliki: `Location:`, `Owned By:`, `Type:`,
      `Press ENTER To Enter a house`. Jumlah rumah tampil di
      /stats > Aset. Modul: `Server_Libraries/House/House_System.pwn`.
- [x] **Private Vehicle** (selesai 2026-10-14): tabel `player_vehicles`
      (id, char_id, model, pos_x/y/z, angle, color1, color2, plate, locked,
      fuel). Maks 2 per karakter, 16 model di katalog (Sanchez Rp45jt s/d
      Infernus Rp450jt). `/buyvehicle` (dialog daftar + konfirmasi, spawn di
      depan pemain + plat "SRP XXXX" + langsung dimasukkan ke kursi sopir),
      `/vpark` (simpan posisi/arah/bensin), `/vlock` (kendaraan yang
      dikemudikan/terdekat; terkunci tidak bisa dimasuki orang lain),
      `/vlist` (dialog kelola: info, kunci/buka, lacak via checkpoint),
      spawn otomatis saat karakter load, despawn saat disconnect (posisi
      disimpan dulu). PlayerTextDraw info kecil (plat, model, status kunci,
      bensin) tampil saat mengemudi. Jumlah kendaraan tampil di /stats >
      Aset. Modul: `Server_Libraries/Vehicle/Vehicle_System.pwn`.
- [x] **Admin DB** (selesai 2026-10-14): level admin SUDAH tersimpan di
      `accounts.admin` (via /setadmin). `/adminduty` (admin 1+: nyala/matikan
      on-duty — nama jadi oranye + pengumuman ke server), `/admins` (semua
      pemain: dialog daftar admin online + jabatan + status duty), nama tiap
      level (1=Junior, 2=Senior, 3=Head, 4=Manager, 5=Owner). Duty otomatis
      reset saat disconnect. /stats > Informasi Umum kini tampil jabatan
      admin (mis. "Ya (Level 3 - Head)"). Modul:
      `Server_Libraries/Admin/Admin_System.pwn`. Tidak perlu skema DB baru
      (kolom `accounts.admin` sudah ada).

## Berikutnya — BATCH BARU (permintaan user 2026-10-13)

Dikerjakan SETELAH 4 item prioritas, SEBELUM batch fitur review server.
Gaya tetap: oldschool-modern, textdraw, Bahasa Indonesia, easydialog,
compile 0 error, commit+push per item.

- [x] **Dynamic Faction** (selesai 2026-10-14): tabel `factions`
      (id, name, type [0=LSPD/1=EMS/2=Pemerintah/3=Montir/4=News], color,
      spawn_x/y/z, spawn_angle, leader_char_id, cash) + kolom baru
      `characters.faction_id` & `faction_rank`. Admin: `/createfaction [tipe] [nama]`
      → markas pickup bintang + label 3D berwarna (pembuat otomatis jadi Ketua);
      `/fsetleader [id]` (admin 4+) tunjuk ketua baru. Pimpinan: `/finvite [id]`
      (dialog terima/tolak ke target), `/fkick [id]`, `/setrank [id] [rank]`
      (ketua, rank 1-5: Rekrut s/d Wakil Ketua, 6=Ketua). Anggota: `/f [pesan]`
      chat fraksi (warna fraksi), `/duty` di markas (seragam + senjata dinas
      per tipe: LSPD pistol/shotgun/MP5, EMS pemadam, News kamera; skin lama
      dikembalikan saat off duty), `/finfo` (info + daftar anggota), `/factions`
      (daftar semua fraksi), `/fquit`, kas fraksi `/fdeposit` & `/fwithdraw`
      (ketua saja). Duty otomatis reset saat disconnect. Modul:
      `Server_Libraries/Faction/Faction_System.pwn`.
- [x] **Dynamic Workshop** (selesai 2026-10-14): tabel `workshops`
      (id, name, owner_char_id, price, profit, pos_x/y/z).
      Admin: `/createws [nama] [harga]` (level 3+) → pickup + label 3D
      "[BENGKEL]" (nama + harga + status Dijual/Pemilik).
      Pemain: `/buyworkshop` (dekat pickup, tanpa pemilik), `/wsinfo`
      (dialog kelola: ambil keuntungan, jual kembali 70%), `/wswithdraw`.
      Pelanggan (wajib mengemudi, dekat bengkel yang sudah ada pemiliknya):
      `/repair` (Rp150rb, gratis bila tidak rusak),
      `/mod` → ganti warna (Rp200rb, input 2 warna 0-126),
      pasang komponen (7 kategori: spoiler/hood/exhaust/nitro/stereo/
      hidrolik/lampu, 24 item, harga Rp100-600rb),
      pasang neon biru/pink (Rp500rb, objek underglow 18647/18648,
      bisa dilepas gratis). Biaya jasa masuk profit pemilik bengkel;
      gratis bila pelanggan adalah pemilik bengkel. Jumlah bengkel tampil
      di /stats > Aset. Modul: `Server_Libraries/Workshop/Workshop_System.pwn`.
- [x] **Dynamic Garage Kota** (selesai 2026-10-14): tabel `garages`
      (id, name, pos, fee) + kolom baru `player_vehicles.garage_id`
      (0 = di jalanan, >0 = id garasi tempat tersimpan).
      Admin: `/creategarage [nama] [biaya]` (level 3+) → pickup + label 3D
      gaya garkot Indonesia (referensi video YouTube 2026-10-14):
      kuning `(GARKOT ID: x)`, putih nama + biaya/isi, `Tekan F` merah.
      Pemain: `/garage` atau tekan ENTER (F) di dekat garasi → dialog
      Simpan / Ambil / Transfer / Info. Simpan: kendaraan milik pemain
      yang aktif dalam 15 meter di-despawn + tercatat di garasi, bayar
      biaya titip sekali; Ambil: spawn lagi di depan garasi + pemain
      langsung masuk kursi sopir; Transfer: pindahkan kendaraan tersimpan
      ke garkot lain (biaya Rp100.000). `/garages` (daftar semua garasi).
      Kapasitas 20 kendaraan per garasi. Kendaraan tersimpan tidak ikut
      spawn saat karakter load (dijaga di `Vehicle_Spawn`) dan tampil
      "Di Garasi" di /vlist.
      Modul: `Server_Libraries/Garage/Garage_System.pwn`.
- [x] **Dynamic Family/Gangster** (selesai 2026-10-14): tabel `families`
      (id, name, color [RGB], leader_char_id, cash) + kolom baru
      `characters.family_id` & `family_rank`. Pemain: `/createfamily [nama]`
      (bayar Rp50jt tunai, pendiri jadi Ketua lalu pilih warna identitas
      via dialog: 8 warna). Pimpinan: `/faminvite [id]` (dialog terima/tolak),
      `/famkick [id]`, `/setfamrank [id] [rank]` (ketua, rank 1-5:
      Preman s/d Tangan Kanan, 6=Ketua). Anggota: `/fam [pesan]` (chat
      berwarna keluarga), `/famquit`, `/faminfo` (info + daftar anggota +
      kas), `/families` (daftar + detail), `/famcolor` (ketua ganti warna:
      nama anggota + warna utama kendaraan anggota yang online disamakan),
      kas keluarga `/famdeposit` & `/famwithdraw` (ketua). Admin 4+:
      `/famsetleader [id]`. Warna nama via SetPlayerColor (admin on-duty
      tetap oranye, dikembalikan saat duty off). Basis badside untuk
      turf/gang war nanti. Modul: `Server_Libraries/Family/Family_System.pwn`.
- [x] **Dynamic Zone (Greenzone)** (selesai 2026-10-14): tabel `zones`
      (id, name, type, min_x/min_y/max_x/max_y). Admin: `/createzone [nama] [tipe]`
      (level 3+, tipe 0=Greenzone / 1=Zona Bahaya) → area persegi 100x100m
      di posisi admin, gangzone berwarna + label 3D.
      Greenzone: damage dibatalkan (nyawa dikembalikan di
      `OnPlayerTakeDamage`, berlaku bila korban ATAU penyerang di dalam)
      & tembakan dibatalkan (`OnPlayerWeaponShot` return 0, peringatan
      dibatasi 1x/3 detik). Textdraw "GREENZONE"/"ZONA BAHAYA" di layar
      saat masuk area (dicek tiap 1 detik via timer `ZoneTick`), plus
      pesan selamat datang. Pemain: `/zones` (dialog daftar + detail;
      admin 4+ bisa hapus dari dialog), `/deletezone` (admin 4+, berdiri
      di dalam zona). Modul: `Server_Libraries/Zone/Zone_System.pwn`.
- [x] **Dynamic Dealer** (selesai 2026-10-14): tabel `dealers`
      (id, name, owner_char_id, type, price, profit, pos_x/y/z).
      Admin: `/createdealer [nama] [tipe] [harga]` (level 3+, tipe
      0=Umum/1=Ekonomis/2=Sport/3=Motor) → pickup dolar emas (model 1274) +
      label 3D gaya Infer (dari video referensi Zerowaste): `{FFFFFF}ID: X` /
      `{FFFF00}` nama dealer (atau `Location: ...` bila dijual) /
      `{FFFF00}` `Pemilik: ...` (atau `Harga: Rp...` bila dijual) /
      `{FFFF00}` `Tipe: ...` / `{00CCFF}` perintah (`/buydealer` bila dijual,
      `/dealer` bila dimiliki). Pemain: `/buydealer` (dekat pickup), `/dealer`
      (showroom: dialog daftar stok + harga, test drive 60 detik spawn
      sementara, beli langsung jadi private vehicle maks 2/karakter),
      `/dealerinfo` (dialog kelola: ambil komisi, jual), `/dealerwithdraw`
      (komisi 5% tiap penjualan masuk kas dealer + notif pemilik online),
      `/selldealer` (kembali 70%), `/dealers` (daftar + detail). Kendaraan
      test drive dihapus otomatis saat timer habis/disconnect. Modul:
      `Server_Libraries/Dealer/Dealer_System.pwn`.
- [x] **Dynamic Pom** (selesai 2026-10-14): tabel `gasstations`
      (id, name, owner_char_id, price, price_per_liter, stock, profit,
      pos_x/y/z). Admin: `/creategasstation [nama] [harga]` (level 3+)
      → pickup + label 3D (`[POM BENSIN ID: x]`, nama, harga/liter, stok,
      status). Pemain: `/buygasstation` (dekat pompa, pom yang dijual),
      `/refuel` (wajib jadi sopir kendaraan pribadi di dekat pompa →
      dialog konfirmasi → isi penuh atau semampunya uang/stok), `/gasinfo`
      (dialog kelola pemilik: info, beli stok dari pemasok Rp8.000/liter
      maks 20.000L, ambil keuntungan, jual kembali 70%), `/setfuelprice`
      (pemilik atur harga Rp1.000–50.000/liter, label diperbarui),
      `/gaswithdraw`, `/sellgasstation`, `/gasstations` (daftar + detail).
      **Sistem Bensin** ikut jalan: bensin kendaraan pribadi (0–100)
      berkurang tiap 30 detik saat dikendarai (cepat saat melaju, pelan
      saat diam) via timer `FuelTick`; bensin habis → pengemudi
      dikeluarkan + tidak bisa masuk lagi sampai diisi; indikator bensin
      di textdraw info kendaraan diperbarui otomatis. Jumlah pom tampil
      di /stats > Aset. /help dipisah: perintah admin pindah ke
      `/helpadmin` (baris string /help melebihi batas Pawn). Modul:
      `Server_Libraries/GasStation/GasStation_System.pwn`.
- [x] **Dynamic Door** (selesai 2026-10-14): tabel `doors`
      (id, owner_type [0=rumah/1=bisnis/2=fraksi], owner_id, name,
      ext pos+int+vw, int pos+int+vw, locked).
      `/createdoor [tipe] [id_pemilik] [nama]` 2 langkah (admin 3+ untuk
      semua entitas, pemilik rumah/bisnis atau ketua fraksi untuk
      miliknya) — langkah 1 catat sisi luar, langkah 2 catat titik
      interior tujuan. Pickup + label 3D di kedua sisi
      (`[PINTU ID:x]`, nama, pemilik, status terkunci).
      Masuk/keluar pakai tombol ENTER (F); pintu terkunci hanya bisa
      dimasuki pengelola. `/doors` (daftar + dialog kelola untuk
      pemilik/admin 3+: kunci/buka, ganti nama, hapus via konfirmasi),
      `/doorinfo`, `/lockdoor` (pemilik/admin 3+), `/deletedoor`
      (admin 4+/pemilik). `/help` & `/helpadmin` diperbarui. Modul:
      `Server_Libraries/Door/Door_System.pwn`.
- [x] **Inventory System (textdraw)** (selesai 2026-10-14): tabel
      `inventory` (char_id, item_id, amount). `/inv` → panel PlayerTextDraw
      5 slot klik (SelectTextDraw): Roti, Air Mineral, Coconut Water,
      Kopi, Obat. Klik slot → dialog Gunakan / Buang 1 / Beri ke Pemain
      / Kembali. Efek terhubung ke Needs: roti +35 makan, air +35 minum,
      coconut +50 minum & -15 stress, kopi -30 stress, obat +40 darah.
      Data dimuat saat karakter dipilih, tersimpan otomatis.
      Modul: `Server_Libraries/Inventory/Inventory_System.pwn`.
- [x] **Starterpack Warga Baru** (selesai 2026-10-14, permintaan user;
      referensi riset YouTube 3 server): `/starterpack` → dialog isi paket
      → sekali klaim per karakter (tabel `starterpack_claims`). Isi:
      Rp5.000.000 tunai, Roti x5, Air Mineral x5, Coconut Water x3,
      Kopi x2, Obat x2 (masuk inventory), motor Sanchez gratis
      (kendaraan pribadi via `Vehicle_GiveFree`).
      Modul: `Server_Libraries/Starterpack/Starterpack_System.pwn`.

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
