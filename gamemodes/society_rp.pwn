//================================================================
// Society Roleplay - Gamemode SA-MP 0.3.7 R2
// Server roleplay Indonesia bertema oldschool.
//
// Fitur:
//  - Sistem akun (register/login) dengan kata sandi ter-hash SHA256
//  - Sistem karakter (maksimal 3 per akun): nama, umur, gender, skin
//  - Penyimpanan MySQL (tabel akun & karakter dibuat otomatis)
//  - Autosave tiap 10 menit + perintah /save
//  - Mata uang Rupiah dengan format Rp1.500.000
//  - Perintah pemain: /stats, /uang, /save, /bantuan
//  - Perintah admin: /setadmin (RCON), /kick, /ban
//
// Dikembangkan dengan Hermes Agent.
//================================================================

#include <a_samp>
#include <a_mysql>

//==== KONFIGURASI DATABASE ====
// Sesuaikan dengan pengaturan MySQL server anda sebelum compile.
#define MYSQL_HOST "127.0.0.1"
#define MYSQL_USER "root"
#define MYSQL_PASS ""
#define MYSQL_DB   "society_rp"

//==== WARNA (gaya oldschool) ====
#define COLOR_GREEN  0x33AA33FF
#define COLOR_RED    0xFF4444FF
#define COLOR_WHITE  0xFFFFFFFF
#define COLOR_YELLOW 0xFFFF00FF
#define COLOR_BLUE   0x33CCFFFF
#define COLOR_GREY   0xA9A9A9FF

main(){}

//==== ID DIALOG ====
enum
{
    D_LOGIN = 1000,
    D_REGISTER,
    D_REGISTER_CONFIRM,
    D_CHARLIST,
    D_CREATE_NAME,
    D_CREATE_AGE,
    D_CREATE_GENDER,
    D_CREATE_SKIN,
    D_STATS,
    D_HELP
};

//==== HANDLE DATABASE ====
new MySQL:g_SQL = MYSQL_INVALID_HANDLE;

//==== DATA PEMAIN ====
new pAccountID[MAX_PLAYERS];
new pCharID[MAX_PLAYERS];
new bool:pLogged[MAX_PLAYERS];
new pLoginTries[MAX_PLAYERS];
new pAdmin[MAX_PLAYERS];
new pCharCount[MAX_PLAYERS];
new pCharIDs[MAX_PLAYERS][3];
new pCharList[MAX_PLAYERS][3][32];
new pCharName[MAX_PLAYERS][32];
new pAge[MAX_PLAYERS];
new pGender[MAX_PLAYERS]; // 0 = Laki-laki, 1 = Perempuan
new pSkin[MAX_PLAYERS];
new pMoney[MAX_PLAYERS];
new pBank[MAX_PLAYERS];
new pLevel[MAX_PLAYERS];
new pExp[MAX_PLAYERS];
new Float:pPosX[MAX_PLAYERS];
new Float:pPosY[MAX_PLAYERS];
new Float:pPosZ[MAX_PLAYERS];
new pInterior[MAX_PLAYERS];
new pVW[MAX_PLAYERS];
new Float:pHealth[MAX_PLAYERS];
new Float:pArmour[MAX_PLAYERS];
new bool:pNeedLoad[MAX_PLAYERS];
new pTempPass[MAX_PLAYERS][33];
new pCreateName[MAX_PLAYERS][32];
new pCreateAge[MAX_PLAYERS];
new pCreateGender[MAX_PLAYERS];

//==== FORWARD (callback MySQL & timer) ====
forward OnAccountCheck(playerid);
forward OnLoginCheck(playerid);
forward OnAccountCreated(playerid);
forward OnCharListLoad(playerid);
forward OnCharNameCheck(playerid);
forward OnCharCreated(playerid);
forward OnCharLoaded(playerid);
forward AutoSave();

//================================================================
// UTIL
//================================================================

// strtok: memecah string berdasarkan spasi (implementasi klasik).
stock strtok(const string[], &index)
{
    new length = strlen(string);
    while ((index < length) && (string[index] <= ' '))
    {
        index++;
    }
    new offset = index;
    new result[32];
    while ((index < length) && (string[index] > ' ') && ((index - offset) < (sizeof(result) - 1)))
    {
        result[index - offset] = string[index];
        index++;
    }
    result[index - offset] = EOS;
    return result;
}

// IsNumeric: true jika string hanya berisi angka 0-9.
stock IsNumeric(const str[])
{
    new len = strlen(str);
    if (len == 0) return 0;
    for (new i = 0; i < len; i++)
    {
        if (str[i] < '0' || str[i] > '9') return 0;
    }
    return 1;
}

// FormatRupiah: 1500000 -> "Rp1.500.000" (titik pemisah ribuan).
stock FormatRupiah(value, dest[], len)
{
    new tmp[32], pos = 0;
    if (value < 0) value = 0;
    if (value == 0)
    {
        tmp[pos++] = '0';
    }
    else
    {
        new count = 0;
        while (value > 0 && pos < (sizeof(tmp) - 1))
        {
            if (count == 3)
            {
                tmp[pos++] = '.';
                count = 0;
            }
            tmp[pos++] = '0' + (value % 10);
            value /= 10;
            count++;
        }
    }
    tmp[pos] = EOS;
    new dpos = 0;
    if (len > 3)
    {
        dest[dpos++] = 'R';
        dest[dpos++] = 'p';
    }
    for (new i = pos - 1; i >= 0 && dpos < (len - 1); i--)
    {
        dest[dpos++] = tmp[i];
    }
    dest[dpos] = EOS;
    return 1;
}

// IsAdmin: cek apakah pemain login dan punya level admin minimal.
stock IsAdmin(playerid, level)
{
    if (!pLogged[playerid]) return 0;
    return (pAdmin[playerid] >= level);
}

// GetCmdRest: mengambil sisa teks perintah (untuk alasan kick/ban).
stock GetCmdRest(const cmdtext[], index, dest[], len)
{
    new slen = strlen(cmdtext);
    while (index < slen && cmdtext[index] <= ' ') index++;
    if (index >= slen)
    {
        dest[0] = EOS;
        return 0;
    }
    strmid(dest, cmdtext, index, slen, len);
    return 1;
}

// ResetPlayerVars: mengosongkan semua data pemain.
stock ResetPlayerVars(playerid)
{
    pAccountID[playerid] = 0;
    pCharID[playerid] = 0;
    pLogged[playerid] = false;
    pLoginTries[playerid] = 0;
    pAdmin[playerid] = 0;
    pCharCount[playerid] = 0;
    pAge[playerid] = 17;
    pGender[playerid] = 0;
    pSkin[playerid] = 0;
    pMoney[playerid] = 0;
    pBank[playerid] = 0;
    pLevel[playerid] = 1;
    pExp[playerid] = 0;
    pPosX[playerid] = 1481.0;
    pPosY[playerid] = -1724.0;
    pPosZ[playerid] = 13.5;
    pInterior[playerid] = 0;
    pVW[playerid] = 0;
    pHealth[playerid] = 100.0;
    pArmour[playerid] = 0.0;
    pNeedLoad[playerid] = false;
    pTempPass[playerid][0] = EOS;
    pCreateName[playerid][0] = EOS;
    pCreateAge[playerid] = 0;
    pCreateGender[playerid] = 0;
    pCharName[playerid][0] = EOS;
    for (new i = 0; i < 3; i++)
    {
        pCharIDs[playerid][i] = 0;
        pCharList[playerid][i][0] = EOS;
    }
    return 1;
}

//================================================================
// DATABASE
//================================================================

// DB_CreateTables: membuat tabel akun & karakter jika belum ada.
stock DB_CreateTables()
{
    mysql_tquery(g_SQL, "CREATE TABLE IF NOT EXISTS accounts ( \
        id INT AUTO_INCREMENT PRIMARY KEY, \
        username VARCHAR(24) UNIQUE NOT NULL, \
        password CHAR(64) NOT NULL, \
        email VARCHAR(64), \
        register_date DATETIME DEFAULT CURRENT_TIMESTAMP, \
        last_login DATETIME, \
        admin TINYINT DEFAULT 0)");
    mysql_tquery(g_SQL, "CREATE TABLE IF NOT EXISTS characters ( \
        id INT AUTO_INCREMENT PRIMARY KEY, \
        account_id INT NOT NULL, \
        name VARCHAR(24) UNIQUE NOT NULL, \
        age TINYINT DEFAULT 17, \
        gender TINYINT DEFAULT 0, \
        skin INT DEFAULT 0, \
        money INT DEFAULT 500000, \
        bank INT DEFAULT 0, \
        level INT DEFAULT 1, \
        exp INT DEFAULT 0, \
        pos_x FLOAT DEFAULT 1481.0, \
        pos_y FLOAT DEFAULT -1724.0, \
        pos_z FLOAT DEFAULT 13.5, \
        interior INT DEFAULT 0, \
        vw INT DEFAULT 0, \
        health FLOAT DEFAULT 100.0, \
        armour FLOAT DEFAULT 0.0, \
        created DATETIME DEFAULT CURRENT_TIMESTAMP)");
    print("[SocietyRP] Tabel database diperiksa/dibuat.");
    return 1;
}

// SaveCharacter: menyimpan data karakter pemain ke database.
stock SaveCharacter(playerid)
{
    if (!pLogged[playerid] || pCharID[playerid] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new Float:x, Float:y, Float:z, Float:hp, Float:ap;
    GetPlayerPos(playerid, x, y, z);
    GetPlayerHealth(playerid, hp);
    GetPlayerArmour(playerid, ap);
    pMoney[playerid] = GetPlayerMoney(playerid);
    new query[512];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE characters SET money = %d, bank = %d, level = %d, exp = %d, pos_x = %f, pos_y = %f, pos_z = %f, interior = %d, vw = %d, health = %f, armour = %f WHERE id = %d",
        pMoney[playerid], pBank[playerid], pLevel[playerid], pExp[playerid],
        x, y, z, GetPlayerInterior(playerid), GetPlayerVirtualWorld(playerid),
        hp, ap, pCharID[playerid]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// LoadCharacterList: mengambil daftar karakter milik akun lalu tampilkan dialog.
stock LoadCharacterList(playerid)
{
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT id, name FROM characters WHERE account_id = %d", pAccountID[playerid]);
    mysql_tquery(g_SQL, query, "OnCharListLoad", "d", playerid);
    return 1;
}

// LoadCharacter: mengambil seluruh data satu karakter dari database.
stock LoadCharacter(playerid, charid)
{
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT * FROM characters WHERE id = %d LIMIT 1", charid);
    mysql_tquery(g_SQL, query, "OnCharLoaded", "d", playerid);
    return 1;
}

// SpawnCharacter: menyiapkan spawn lalu memunculkan pemain.
stock SpawnCharacter(playerid)
{
    SetSpawnInfo(playerid, 0, pSkin[playerid],
        pPosX[playerid], pPosY[playerid], pPosZ[playerid],
        0.0, 0, 0, 0, 0, 0, 0);
    pNeedLoad[playerid] = true;
    TogglePlayerSpectating(playerid, false);
    SpawnPlayer(playerid);
    return 1;
}

//================================================================
// GAMEMODE
//================================================================

public OnGameModeInit()
{
    SetGameModeText("Society RP v1.0");
    DisableInteriorEnterExits();
    SetNameTagDrawDistance(25.0);
    ShowPlayerMarkers(PLAYER_MARKERS_MODE_OFF);
    SetWorldTime(12);
    SetWeather(10);

    g_SQL = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASS, MYSQL_DB);
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        print("[SocietyRP] ERROR: Gagal terhubung ke database MySQL (handle tidak valid).");
        SetGameModeText("DB ERROR");
        return 1;
    }
    if (mysql_errno(g_SQL) != 0)
    {
        print("[SocietyRP] ERROR: Gagal terhubung ke database MySQL (errno != 0).");
        SetGameModeText("DB ERROR");
        mysql_close(g_SQL);
        g_SQL = MYSQL_INVALID_HANDLE;
        return 1;
    }
    print("[SocietyRP] Berhasil terhubung ke database MySQL.");
    DB_CreateTables();
    SetTimer("AutoSave", 600000, true); // autosave tiap 10 menit
    print("[SocietyRP] Gamemode dimuat: Society RP v1.0");
    return 1;
}

public OnGameModeExit()
{
    if (g_SQL != MYSQL_INVALID_HANDLE)
    {
        mysql_close(g_SQL);
        g_SQL = MYSQL_INVALID_HANDLE;
    }
    print("[SocietyRP] Gamemode dimatikan.");
    return 1;
}

//================================================================
// PEMAIN
//================================================================

public OnPlayerConnect(playerid)
{
    ResetPlayerVars(playerid);
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline. Silakan coba lagi nanti.");
        Kick(playerid);
        return 1;
    }
    TogglePlayerSpectating(playerid, true); // freeze selama proses login
    new name[MAX_PLAYER_NAME], query[160];
    GetPlayerName(playerid, name, sizeof(name));
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT id FROM accounts WHERE username = '%e' LIMIT 1", name);
    mysql_tquery(g_SQL, query, "OnAccountCheck", "d", playerid);
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if (pLogged[playerid] && pCharID[playerid] > 0)
    {
        SaveCharacter(playerid);
    }
    if (pLogged[playerid] && pAccountID[playerid] > 0 && g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE accounts SET last_login = NOW() WHERE id = %d", pAccountID[playerid]);
        mysql_tquery(g_SQL, query);
    }
    ResetPlayerVars(playerid);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    if (pLogged[playerid] && pNeedLoad[playerid])
    {
        pNeedLoad[playerid] = false;
        SetPlayerInterior(playerid, pInterior[playerid]);
        SetPlayerVirtualWorld(playerid, pVW[playerid]);
        SetPlayerHealth(playerid, pHealth[playerid]);
        SetPlayerArmour(playerid, pArmour[playerid]);
        ResetPlayerMoney(playerid);
        GivePlayerMoney(playerid, pMoney[playerid]);
        new msg[96];
        format(msg, sizeof(msg), "Selamat datang di Society Roleplay, %s!", pCharName[playerid]);
        SendClientMessage(playerid, COLOR_GREEN, msg);
        SendClientMessage(playerid, COLOR_GREY, "Ketik /bantuan untuk melihat daftar perintah.");
    }
    return 1;
}

//================================================================
// DIALOG
//================================================================

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
    switch (dialogid)
    {
        case D_LOGIN:
        {
            if (!response)
            {
                Kick(playerid);
                return 1;
            }
            new len = strlen(inputtext);
            if (len < 4 || len > 32)
            {
                ShowPlayerDialog(playerid, D_LOGIN, DIALOG_STYLE_PASSWORD, "Login",
                    "Kata sandi minimal 4 karakter.\nMasukkan kata sandi akun anda:",
                    "Masuk", "Keluar");
                return 1;
            }
            format(pTempPass[playerid], sizeof(pTempPass[]), "%s", inputtext);
            new name[MAX_PLAYER_NAME], query[192];
            GetPlayerName(playerid, name, sizeof(name));
            mysql_format(g_SQL, query, sizeof(query),
                "SELECT id, password, admin FROM accounts WHERE username = '%e' LIMIT 1", name);
            mysql_tquery(g_SQL, query, "OnLoginCheck", "d", playerid);
            return 1;
        }
        case D_REGISTER:
        {
            if (!response)
            {
                Kick(playerid);
                return 1;
            }
            new len = strlen(inputtext);
            if (len < 4 || len > 32)
            {
                ShowPlayerDialog(playerid, D_REGISTER, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
                    "Kata sandi harus 4-32 karakter!\nBuat kata sandi untuk akun baru anda:",
                    "Daftar", "Keluar");
                return 1;
            }
            format(pTempPass[playerid], sizeof(pTempPass[]), "%s", inputtext);
            ShowPlayerDialog(playerid, D_REGISTER_CONFIRM, DIALOG_STYLE_PASSWORD, "Konfirmasi Kata Sandi",
                "Ulangi kata sandi yang baru saja anda buat:",
                "Konfirmasi", "Kembali");
            return 1;
        }
        case D_REGISTER_CONFIRM:
        {
            if (!response)
            {
                ShowPlayerDialog(playerid, D_REGISTER, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
                    "Buat kata sandi untuk akun baru anda (4-32 karakter):",
                    "Daftar", "Keluar");
                return 1;
            }
            if (strcmp(inputtext, pTempPass[playerid], false) != 0)
            {
                ShowPlayerDialog(playerid, D_REGISTER, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
                    "Konfirmasi tidak cocok! Ulangi dari awal.\nBuat kata sandi untuk akun baru anda (4-32 karakter):",
                    "Daftar", "Keluar");
                return 1;
            }
            new name[MAX_PLAYER_NAME], hash[65], query[256];
            GetPlayerName(playerid, name, sizeof(name));
            SHA256_PassHash(pTempPass[playerid], name, hash, sizeof(hash));
            mysql_format(g_SQL, query, sizeof(query),
                "INSERT INTO accounts (username, password) VALUES ('%e', '%e')", name, hash);
            mysql_tquery(g_SQL, query, "OnAccountCreated", "d", playerid);
            return 1;
        }
        case D_CHARLIST:
        {
            if (!response)
            {
                Kick(playerid);
                return 1;
            }
            if (listitem < 0 || listitem > pCharCount[playerid]) return 1;
            if (listitem == pCharCount[playerid])
            {
                // Baris "Buat Karakter Baru"
                if (pCharCount[playerid] >= 3)
                {
                    SendClientMessage(playerid, COLOR_RED, "Anda sudah memiliki 3 karakter (maksimal).");
                    LoadCharacterList(playerid);
                    return 1;
                }
                ShowPlayerDialog(playerid, D_CREATE_NAME, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
                    "Masukkan nama karakter dengan format Nama_Belakang.\nContoh: Budi_Santoso\n(3-24 karakter)",
                    "Lanjut", "Kembali");
            }
            else
            {
                LoadCharacter(playerid, pCharIDs[playerid][listitem]);
            }
            return 1;
        }
        case D_CREATE_NAME:
        {
            if (!response)
            {
                LoadCharacterList(playerid);
                return 1;
            }
            new len = strlen(inputtext);
            if (len < 3 || len > 24 || strfind(inputtext, "_", true) == -1)
            {
                ShowPlayerDialog(playerid, D_CREATE_NAME, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
                    "Nama tidak valid! Gunakan format Nama_Belakang.\nContoh: Budi_Santoso (3-24 karakter)\n\nMasukkan nama karakter:",
                    "Lanjut", "Kembali");
                return 1;
            }
            format(pCreateName[playerid], sizeof(pCreateName[]), "%s", inputtext);
            new query[160];
            mysql_format(g_SQL, query, sizeof(query),
                "SELECT id FROM characters WHERE name = '%e' LIMIT 1", inputtext);
            mysql_tquery(g_SQL, query, "OnCharNameCheck", "d", playerid);
            return 1;
        }
        case D_CREATE_AGE:
        {
            if (!response)
            {
                ShowPlayerDialog(playerid, D_CREATE_NAME, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
                    "Masukkan nama karakter dengan format Nama_Belakang.\nContoh: Budi_Santoso\n(3-24 karakter)",
                    "Lanjut", "Kembali");
                return 1;
            }
            if (!IsNumeric(inputtext))
            {
                ShowPlayerDialog(playerid, D_CREATE_AGE, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
                    "Umur harus berupa angka!\nMasukkan umur karakter (15-80 tahun):",
                    "Lanjut", "Kembali");
                return 1;
            }
            new age = strval(inputtext);
            if (age < 15 || age > 80)
            {
                ShowPlayerDialog(playerid, D_CREATE_AGE, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
                    "Umur harus 15-80 tahun!\nMasukkan umur karakter:",
                    "Lanjut", "Kembali");
                return 1;
            }
            pCreateAge[playerid] = age;
            ShowPlayerDialog(playerid, D_CREATE_GENDER, DIALOG_STYLE_LIST, "Buat Karakter - Jenis Kelamin",
                "Laki-laki\nPerempuan",
                "Pilih", "Kembali");
            return 1;
        }
        case D_CREATE_GENDER:
        {
            if (!response)
            {
                ShowPlayerDialog(playerid, D_CREATE_AGE, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
                    "Masukkan umur karakter (15-80 tahun):",
                    "Lanjut", "Kembali");
                return 1;
            }
            pCreateGender[playerid] = listitem; // 0 = Laki-laki, 1 = Perempuan
            ShowPlayerDialog(playerid, D_CREATE_SKIN, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
                "Masukkan ID skin karakter (0-311):",
                "Selesai", "Kembali");
            return 1;
        }
        case D_CREATE_SKIN:
        {
            if (!response)
            {
                ShowPlayerDialog(playerid, D_CREATE_GENDER, DIALOG_STYLE_LIST, "Buat Karakter - Jenis Kelamin",
                    "Laki-laki\nPerempuan",
                    "Pilih", "Kembali");
                return 1;
            }
            if (!IsNumeric(inputtext))
            {
                ShowPlayerDialog(playerid, D_CREATE_SKIN, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
                    "ID skin harus berupa angka!\nMasukkan ID skin karakter (0-311):",
                    "Selesai", "Kembali");
                return 1;
            }
            new skin = strval(inputtext);
            if (skin < 0 || skin > 311)
            {
                ShowPlayerDialog(playerid, D_CREATE_SKIN, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
                    "ID skin harus 0-311!\nMasukkan ID skin karakter:",
                    "Selesai", "Kembali");
                return 1;
            }
            new query[256];
            mysql_format(g_SQL, query, sizeof(query),
                "INSERT INTO characters (account_id, name, age, gender, skin) VALUES (%d, '%e', %d, %d, %d)",
                pAccountID[playerid], pCreateName[playerid], pCreateAge[playerid], pCreateGender[playerid], skin);
            mysql_tquery(g_SQL, query, "OnCharCreated", "d", playerid);
            return 1;
        }
        case D_STATS, D_HELP:
        {
            return 1; // dialog info, abaikan respon
        }
    }
    return 1;
}

//================================================================
// COMMAND
//================================================================

public OnPlayerCommandText(playerid, cmdtext[])
{
    new cmd[32], idx = 0;
    cmd = strtok(cmdtext, idx);

    // /stats - melihat statistik karakter
    if (strcmp(cmd, "/stats", true) == 0)
    {
        if (!pLogged[playerid] || pCharID[playerid] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new info[512], uang[32], bank[32], gender[12], admin[8];
        FormatRupiah(pMoney[playerid], uang, sizeof(uang));
        FormatRupiah(pBank[playerid], bank, sizeof(bank));
        if (pGender[playerid] == 1) format(gender, sizeof(gender), "Perempuan");
        else format(gender, sizeof(gender), "Laki-laki");
        if (pAdmin[playerid] > 0) format(admin, sizeof(admin), "Ya (%d)", pAdmin[playerid]);
        else format(admin, sizeof(admin), "Tidak");
        format(info, sizeof(info),
            "Nama: %s\nUmur: %d tahun\nJenis Kelamin: %s\nLevel: %d\nEXP: %d\nUang: %s\nTabungan Bank: %s\nAdmin: %s",
            pCharName[playerid], pAge[playerid], gender,
            pLevel[playerid], pExp[playerid], uang, bank, admin);
        ShowPlayerDialog(playerid, D_STATS, DIALOG_STYLE_MSGBOX, "Statistik Karakter", info, "Tutup", "");
        return 1;
    }

    // /uang - melihat jumlah uang dalam format rupiah
    if (strcmp(cmd, "/uang", true) == 0)
    {
        if (!pLogged[playerid] || pCharID[playerid] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        pMoney[playerid] = GetPlayerMoney(playerid);
        new uang[32], msg[96];
        FormatRupiah(pMoney[playerid], uang, sizeof(uang));
        format(msg, sizeof(msg), "Uang anda: %s", uang);
        SendClientMessage(playerid, COLOR_GREEN, msg);
        return 1;
    }

    // /save - menyimpan data karakter secara manual
    if (strcmp(cmd, "/save", true) == 0)
    {
        if (!pLogged[playerid] || pCharID[playerid] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        SaveCharacter(playerid);
        SendClientMessage(playerid, COLOR_GREEN, "Data tersimpan.");
        return 1;
    }

    // /bantuan - daftar perintah
    if (strcmp(cmd, "/bantuan", true) == 0)
    {
        ShowPlayerDialog(playerid, D_HELP, DIALOG_STYLE_MSGBOX, "Bantuan",
            "Perintah Pemain:\n/stats - Melihat statistik karakter\n/uang - Melihat jumlah uang\n/save - Menyimpan data karakter\n/bantuan - Membuka menu ini\n\nPerintah Admin:\n/setadmin [id] [level] - (RCON) Atur level admin\n/kick [id] [alasan] - Tendang pemain dari server\n/ban [id] [alasan] - Blokir pemain dari server",
            "Tutup", "");
        return 1;
    }

    // /setadmin - khusus RCON admin
    if (strcmp(cmd, "/setadmin", true) == 0)
    {
        if (!IsPlayerAdmin(playerid))
        {
            SendClientMessage(playerid, COLOR_RED, "Hanya RCON admin yang dapat memakai perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new sid[32], slvl[32];
        sid = strtok(cmdtext, idx);
        slvl = strtok(cmdtext, idx);
        if (!strlen(sid) || !strlen(slvl))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /setadmin [id] [level]");
            return 1;
        }
        new target = strval(sid), level = strval(slvl);
        if (!IsPlayerConnected(target) || !pLogged[target] || pAccountID[target] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Pemain tidak valid atau belum login.");
            return 1;
        }
        if (level < 0 || level > 5)
        {
            SendClientMessage(playerid, COLOR_RED, "Level admin harus antara 0-5.");
            return 1;
        }
        pAdmin[target] = level;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE accounts SET admin = %d WHERE id = %d", level, pAccountID[target]);
        mysql_tquery(g_SQL, query);
        new tname[MAX_PLAYER_NAME], msg[128];
        GetPlayerName(target, tname, sizeof(tname));
        format(msg, sizeof(msg), "[ADMIN] Level admin %s diatur menjadi %d.", tname, level);
        SendClientMessage(playerid, COLOR_YELLOW, msg);
        format(msg, sizeof(msg), "Level admin anda sekarang: %d.", level);
        SendClientMessage(target, COLOR_YELLOW, msg);
        return 1;
    }

    // /kick - khusus admin level >= 1
    if (strcmp(cmd, "/kick", true) == 0)
    {
        if (!IsAdmin(playerid, 1))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /kick [id] [alasan]");
            return 1;
        }
        new target = strval(sid);
        if (!IsPlayerConnected(target))
        {
            SendClientMessage(playerid, COLOR_RED, "ID pemain tidak ditemukan.");
            return 1;
        }
        new reason[64];
        if (!GetCmdRest(cmdtext, idx, reason, sizeof(reason)))
        {
            format(reason, sizeof(reason), "Tidak ada alasan");
        }
        new tname[MAX_PLAYER_NAME], aname[MAX_PLAYER_NAME], msg[192];
        GetPlayerName(target, tname, sizeof(tname));
        GetPlayerName(playerid, aname, sizeof(aname));
        format(msg, sizeof(msg), "[ADMIN] %s menendang %s. Alasan: %s", aname, tname, reason);
        SendClientMessageToAll(COLOR_RED, msg);
        Kick(target);
        return 1;
    }

    // /ban - khusus admin level >= 1
    if (strcmp(cmd, "/ban", true) == 0)
    {
        if (!IsAdmin(playerid, 1))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /ban [id] [alasan]");
            return 1;
        }
        new target = strval(sid);
        if (!IsPlayerConnected(target))
        {
            SendClientMessage(playerid, COLOR_RED, "ID pemain tidak ditemukan.");
            return 1;
        }
        new reason[64];
        if (!GetCmdRest(cmdtext, idx, reason, sizeof(reason)))
        {
            format(reason, sizeof(reason), "Tidak ada alasan");
        }
        new tname[MAX_PLAYER_NAME], aname[MAX_PLAYER_NAME], msg[192];
        GetPlayerName(target, tname, sizeof(tname));
        GetPlayerName(playerid, aname, sizeof(aname));
        format(msg, sizeof(msg), "[ADMIN] %s memblokir %s. Alasan: %s", aname, tname, reason);
        SendClientMessageToAll(COLOR_RED, msg);
        BanEx(target, reason);
        return 1;
    }

    SendClientMessage(playerid, COLOR_GREY, "Perintah tidak dikenal. Ketik /bantuan.");
    return 1;
}

//================================================================
// CALLBACK MYSQL & TIMER
//================================================================

// OnAccountCheck: cek apakah nama pemain sudah punya akun.
public OnAccountCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (cache_num_rows() > 0)
    {
        ShowPlayerDialog(playerid, D_LOGIN, DIALOG_STYLE_PASSWORD, "Login",
            "Selamat datang kembali di Society Roleplay!\n\nAkun anda sudah terdaftar.\nMasukkan kata sandi:",
            "Masuk", "Keluar");
    }
    else
    {
        ShowPlayerDialog(playerid, D_REGISTER, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
            "Selamat datang di Society Roleplay!\n\nAkun anda belum terdaftar.\nBuat kata sandi (4-32 karakter):",
            "Daftar", "Keluar");
    }
    return 1;
}

// OnLoginCheck: verifikasi kata sandi saat login.
public OnLoginCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (cache_num_rows() == 0)
    {
        Kick(playerid);
        return 1;
    }
    new name[MAX_PLAYER_NAME], dbhash[65], myhash[65], tmp;
    GetPlayerName(playerid, name, sizeof(name));
    cache_get_value_name(0, "password", dbhash, sizeof(dbhash));
    SHA256_PassHash(pTempPass[playerid], name, myhash, sizeof(myhash));
    pTempPass[playerid][0] = EOS; // hapus kata sandi dari memori
    if (strcmp(myhash, dbhash, false) == 0)
    {
        cache_get_value_name_int(0, "id", tmp);
        pAccountID[playerid] = tmp;
        cache_get_value_name_int(0, "admin", tmp);
        pAdmin[playerid] = tmp;
        pLogged[playerid] = true;
        pLoginTries[playerid] = 0;
        SendClientMessage(playerid, COLOR_GREEN, "Login berhasil! Memuat daftar karakter...");
        LoadCharacterList(playerid);
    }
    else
    {
        pLoginTries[playerid]++;
        if (pLoginTries[playerid] >= 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Kata sandi salah 3 kali. Anda dikeluarkan dari server.");
            Kick(playerid);
        }
        else
        {
            new msg[256];
            format(msg, sizeof(msg),
                "Kata sandi salah! Percobaan %d/3.\nMasukkan kata sandi akun anda:",
                pLoginTries[playerid]);
            ShowPlayerDialog(playerid, D_LOGIN, DIALOG_STYLE_PASSWORD, "Login", msg, "Masuk", "Keluar");
        }
    }
    return 1;
}

// OnAccountCreated: setelah INSERT akun berhasil.
public OnAccountCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    pAccountID[playerid] = cache_insert_id();
    pTempPass[playerid][0] = EOS; // hapus kata sandi dari memori
    pAdmin[playerid] = 0;
    pLogged[playerid] = true;
    pLoginTries[playerid] = 0;
    SendClientMessage(playerid, COLOR_GREEN, "Akun berhasil dibuat! Selamat datang di Society Roleplay.");
    LoadCharacterList(playerid);
    return 1;
}

// OnCharListLoad: membangun dialog daftar karakter milik akun.
public OnCharListLoad(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new rows = cache_num_rows(), tmp;
    if (rows > 3) rows = 3;
    pCharCount[playerid] = rows;
    new list[256], item[40];
    list[0] = EOS;
    for (new i = 0; i < rows; i++)
    {
        cache_get_value_name_int(i, "id", tmp);
        pCharIDs[playerid][i] = tmp;
        cache_get_value_name(i, "name", pCharList[playerid][i], 32);
        format(item, sizeof(item), "%s\n", pCharList[playerid][i]);
        strcat(list, item, sizeof(list));
    }
    strcat(list, ">> Buat Karakter Baru <<", sizeof(list));
    ShowPlayerDialog(playerid, D_CHARLIST, DIALOG_STYLE_LIST,
        "Pilih Karakter", list, "Pilih", "Keluar");
    return 1;
}

// OnCharNameCheck: memastikan nama karakter belum dipakai.
public OnCharNameCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (cache_num_rows() > 0)
    {
        ShowPlayerDialog(playerid, D_CREATE_NAME, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
            "Nama sudah dipakai pemain lain! Pilih nama lain.\nMasukkan nama karakter (format Nama_Belakang):",
            "Lanjut", "Kembali");
    }
    else
    {
        ShowPlayerDialog(playerid, D_CREATE_AGE, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
            "Masukkan umur karakter (15-80 tahun):",
            "Lanjut", "Kembali");
    }
    return 1;
}

// OnCharCreated: setelah INSERT karakter berhasil, langsung muat & spawn.
public OnCharCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new charid = cache_insert_id();
    SendClientMessage(playerid, COLOR_GREEN, "Karakter berhasil dibuat!");
    LoadCharacter(playerid, charid);
    return 1;
}

// OnCharLoaded: memuat seluruh data karakter ke memori lalu spawn.
public OnCharLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (cache_num_rows() == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Gagal memuat data karakter.");
        Kick(playerid);
        return 1;
    }
    new tmp;
    new Float:ftmp;
    cache_get_value_name_int(0, "id", tmp);      pCharID[playerid] = tmp;
    cache_get_value_name(0, "name", pCharName[playerid], 32);
    cache_get_value_name_int(0, "age", tmp);     pAge[playerid] = tmp;
    cache_get_value_name_int(0, "gender", tmp);  pGender[playerid] = tmp;
    cache_get_value_name_int(0, "skin", tmp);    pSkin[playerid] = tmp;
    cache_get_value_name_int(0, "money", tmp);   pMoney[playerid] = tmp;
    cache_get_value_name_int(0, "bank", tmp);    pBank[playerid] = tmp;
    cache_get_value_name_int(0, "level", tmp);   pLevel[playerid] = tmp;
    cache_get_value_name_int(0, "exp", tmp);     pExp[playerid] = tmp;
    cache_get_value_name_float(0, "pos_x", ftmp);  pPosX[playerid] = ftmp;
    cache_get_value_name_float(0, "pos_y", ftmp);  pPosY[playerid] = ftmp;
    cache_get_value_name_float(0, "pos_z", ftmp);  pPosZ[playerid] = ftmp;
    cache_get_value_name_int(0, "interior", tmp);  pInterior[playerid] = tmp;
    cache_get_value_name_int(0, "vw", tmp);        pVW[playerid] = tmp;
    cache_get_value_name_float(0, "health", ftmp); pHealth[playerid] = ftmp;
    cache_get_value_name_float(0, "armour", ftmp); pArmour[playerid] = ftmp;
    SpawnCharacter(playerid);
    return 1;
}

// AutoSave: menyimpan semua karakter yang sedang login (tiap 10 menit).
public AutoSave()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && pLogged[i] && pCharID[i] > 0)
        {
            SaveCharacter(i);
        }
    }
    print("[SocietyRP] Autosave selesai.");
    return 1;
}
