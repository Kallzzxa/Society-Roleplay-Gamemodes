//================================================================
// Society Roleplay - Utils_Enum
// Enum data pemain: Society_Player.
// Semua data per-pemain diakses via Society_PlayerData[playerid][sP...].
// Di-include dari gamemodes/Society_Main.pwn
//================================================================

#if defined _utils_enum_included
    #endinput
#endif
#define _utils_enum_included

// Ukuran buffer field enum (dipakai juga untuk sizeof manual).
#define MAX_TEMP_PASS 33
#define MAX_CHAR_NAME 25

enum Society_Player
{
    sPAccountID,        // id baris di tabel accounts (0 = belum login)
    sPCharID,           // id baris di tabel characters (0 = belum pilih karakter)
    sPAdmin,            // level admin dari database
    sPLoginTries,       // jumlah percobaan login yang gagal
    bool:sPLogged,      // true jika akun sudah login
    sPCharCount,        // jumlah karakter milik akun (maks 3)
    sPTempPass[MAX_TEMP_PASS], // kata sandi sementara saat register/login (dihapus setelah dipakai)
    Float:sPHunger,     // 0-100, berkurang tiap menit
    Float:sPThirst,     // 0-100, berkurang tiap menit
    Float:sPStress,     // 0-100, naik jika lapar/haus
    sPNeedsCD           // cooldown /eat & /drink (GetTickCount)
};
new Society_PlayerData[MAX_PLAYERS][Society_Player];
// Catatan: Pawn tidak mendukung array 2 dimensi di dalam enum,
// jadi daftar nama karakter disimpan di array global terpisah:
new sPCharList[MAX_PLAYERS][3][MAX_CHAR_NAME];
