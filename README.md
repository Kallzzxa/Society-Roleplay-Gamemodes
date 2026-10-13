# Society Roleplay

Gamemode SA-MP 0.3.7 untuk server roleplay Indonesia bertema oldschool.

## Fitur

- **Sistem Akun (UCP sederhana):** registrasi & login dengan kata sandi ter-hash SHA256, batas 3x salah password = kick.
- **Sistem Karakter:** maksimal 3 karakter per akun — nama (format `Nama_Belakang`), umur, jenis kelamin, dan skin.
- **Penyimpanan MySQL:** import `society.sql` untuk membuat tabel `accounts` dan `characters`.
- **Dialog memakai easyDialog:** tanpa ID dialog manual, anti tabrakan ID.
- **Autosave** tiap 10 menit + perintah `/save` manual. Posisi, nyawa, armour, uang, dan interior tersimpan saat keluar.
- **Mata uang Rupiah** dengan format `Rp1.500.000`.
- **Perintah pemain:** `/stats`, `/uang`, `/makan`, `/minum`, `/save`, `/bantuan`.
- **Sistem kebutuhan (makan/minum/stress):** textdraw bar gaya oldschool di kanan bawah layar, berkurang tiap menit; kalau lapar/haus sampai 0, nyawa berkurang. Tersimpan di database.
- **Perintah admin:** `/setadmin` (khusus RCON), `/kick`, `/ban`.
- Gaya oldschool: tanpa marker global, interior enter/exit dimatikan, waktu siang hari.

## Syarat

1. **SA-MP Server 0.3.7 R2-2** — unduh dari [sa-mp.co.id](https://sa-mp.co.id/) (tersedia versi Windows & Linux).
2. **MySQL Server** (misal XAMPP, Laragon, atau MySQL asli).
3. **Plugin MySQL R41 (BlueG)** — file `mysql.so` (Linux) / `mysql.dll` (Windows), sudah tersedia di folder `plugins/`.

## Langkah Instalasi

1. Unduh dan ekstrak paket **SA-MP 0.3.7 R2-2 Server** ke sebuah folder.
2. Copy isi repo ini ke folder server: `gamemodes/`, `plugins/`, `pawno/`, `server.cfg`, `society.sql`.
3. Buat database dan import skema:
   ```sql
   CREATE DATABASE society_rp;
   ```
   lalu import `society.sql` (`mysql -u root -p society_rp < society.sql` atau via phpMyAdmin).
4. Sesuaikan konfigurasi database di `gamemodes/Server_Libraries/Mysql/Mysql_Connect.inc` bila perlu:
   ```pawn
   #define MYSQL_HOST "127.0.0.1"
   #define MYSQL_USER "root"
   #define MYSQL_PASS ""
   #define MYSQL_DB   "society_rp"
   ```
5. Compile `gamemodes/Society_Main.pwn` dengan `pawncc` 0.3.7 (pastikan folder `pawno/include/` lengkap). Hasilnya: `gamemodes/Society_Main.amx`.
6. Pastikan MySQL server berjalan. Pengguna Windows: ganti `plugins mysql.so` menjadi `plugins mysql.dll` di `server.cfg`.
7. Jalankan server:
   - Linux: `./samp03svr`
   - Windows: `samp-server.exe`
8. Buka SA-MP client, tambahkan server `127.0.0.1:7777` (atau IP VPS anda), lalu masuk dan buat akun.

> **Penting:** ganti `rcon_password` di `server.cfg` dengan kata sandi yang kuat sebelum server dibuka ke publik!

## Struktur Folder

```
.
├── gamemodes/
│   ├── Society_Main.pwn                  # file utama gamemode (logika)
│   ├── Society_Main.amx                  # hasil compile
│   └── Server_Libraries/
│       ├── Mysql/
│       │   └── Mysql_Connect.inc         # koneksi database MySQL
│       └── Utils/
│           ├── Utils_Color.pwn           # definisi warna oldschool
│           └── Utils_Enum.pwn            # enum Society_Player (data pemain)
├── pawno/
│   └── include/                          # include SA-MP + a_mysql + easyDialog
├── plugins/
│   ├── mysql.so                          # plugin MySQL R41 (Linux)
│   └── mysql.dll                         # plugin MySQL R41 (Windows)
├── server.cfg                            # konfigurasi server
├── society.sql                           # skema database MySQL
└── README.md
```

## Kredit

Dikembangkan dengan Hermes Agent.
