//================================================================
// Society Roleplay - Mysql_Connect
// Koneksi database MySQL (plugin BlueG R41).
// Skema tabel TIDAK dibuat di sini — import society.sql ke MySQL.
// Di-include dari gamemodes/Society_Main.pwn
//================================================================

#if defined _mysql_connect_included
    #endinput
#endif
#define _mysql_connect_included

//==== KONFIGURASI DATABASE ====
// Sesuaikan dengan pengaturan MySQL server anda sebelum compile.
#define MYSQL_HOST "127.0.0.1"
#define MYSQL_USER "root"
#define MYSQL_PASS ""
#define MYSQL_DB   "society_rp"

// Handle koneksi database global.
new MySQL:g_SQL = MYSQL_INVALID_HANDLE;

// MySQL_Connect: membuka koneksi ke database.
// Mengembalikan handle MySQL, atau MYSQL_INVALID_HANDLE jika gagal.
stock MySQL:MySQL_Connect()
{
    new MySQL:handle = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASS, MYSQL_DB);
    if (handle == MYSQL_INVALID_HANDLE)
    {
        print("[SocietyRP] ERROR: Gagal terhubung ke database MySQL (handle tidak valid).");
        return MYSQL_INVALID_HANDLE;
    }
    if (mysql_errno(handle) != 0)
    {
        print("[SocietyRP] ERROR: Gagal terhubung ke database MySQL (errno != 0).");
        mysql_close(handle);
        return MYSQL_INVALID_HANDLE;
    }
    print("[SocietyRP] Berhasil terhubung ke database MySQL.");
    return handle;
}
