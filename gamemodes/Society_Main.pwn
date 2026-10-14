//================================================================
// Society Roleplay - Society_Main.pwn
// Gamemode SA-MP 0.3.7 R2 - server roleplay Indonesia bertema oldschool.
//
// Struktur modular:
//   gamemodes/Society_Main.pwn                        <- file utama (logika)
//   gamemodes/Server_Libraries/Utils/Utils_Color.pwn  <- definisi warna
//   gamemodes/Server_Libraries/Utils/Utils_Enum.pwn   <- enum Society_Player
//   gamemodes/Server_Libraries/Mysql/Mysql_Connect.inc<- koneksi database
//   gamemodes/Server_Libraries/Business/Business_System.pwn <- bisnis dinamis
//   gamemodes/Server_Libraries/House/House_System.pwn     <- rumah dinamis
//   gamemodes/Server_Libraries/Vehicle/Vehicle_System.pwn <- kendaraan pribadi
//   gamemodes/Server_Libraries/Admin/Admin_System.pwn    <- admin DB: nama level, duty, daftar admin
//   society.sql                                       <- skema database MySQL
//
// Fitur:
//  - Sistem akun (register/login) dengan kata sandi ter-hash SHA256
//  - UCP + sistem karakter (maksimal 3 per akun): nama, umur, gender, skin
//  - Penyimpanan MySQL (import society.sql terlebih dahulu)
//  - Dialog memakai easyDialog (tanpa ID dialog manual)
//  - Autosave tiap 10 menit + perintah /save
//  - Mata uang Rupiah dengan format Rp1.500.000
//  - Bisnis dinamis: /createbisnis (admin), /buybusiness, /bizinfo, /bizwithdraw, /sellbusiness
//  - Rumah dinamis: /createhouse (admin), /buyhouse, /lockhouse, /sellhouse, /houseinfo (masuk/keluar pakai ENTER)
//  - Fraksi dinamis: /createfaction (admin), /finvite, /fkick, /setrank, /f, /duty (seragam+senjata dinas), /finfo, /factions, /fdeposit, /fwithdraw, /fsetleader (admin), /fquit
//  - Bengkel dinamis: /createws (admin), /buyworkshop, /wsinfo, /wswithdraw, /mod (warna, komponen, neon), /repair
//  - Garasi kota dinamis: /creategarage (admin), /garage (titip/ambil kendaraan), /garages
//  - Keluarga/gangster dinamis: /createfamily (bayar), /faminvite, /famkick, /setfamrank, /fam, /famquit, /faminfo, /families, /famcolor (warna nama & kendaraan), /famdeposit, /famwithdraw, /famsetleader (admin)
//  - Zona dinamis: /createzone (admin, tipe Greenzone/Zona Bahaya), /zones (daftar+detail), /deletezone (admin); greenzone membatalkan damage & tembakan (OnPlayerTakeDamage/OnPlayerWeaponShot), textdraw nama zona saat masuk area
//  - Dealer dinamis: /createdealer (admin), /buydealer, /dealer (showroom: lihat stok, test drive 60 detik, beli jadi kendaraan pribadi), /dealerinfo, /dealerwithdraw (komisi 5% tiap penjualan), /selldealer, /dealers
//  - Perintah pemain: /stats, /money, /save, /help
//  - Perintah admin: /setadmin (RCON), /adminduty, /admins, /kick, /ban
//
// Dikembangkan dengan Hermes Agent.
//================================================================

#include <a_samp>
#include <a_mysql>
#include <easyDialog>
#include "Server_Libraries/Utils/Utils_Color.pwn"
#include "Server_Libraries/Utils/Utils_Enum.pwn"
#include "Server_Libraries/Mysql/Mysql_Connect.inc"
#include "Server_Libraries/Needs/Needs_System.pwn"

main(){}

//==== DATA KARAKTER PEMAIN ====
// (Data akun & sesi ada di enum Society_Player -> Society_PlayerData)
new pCharIDs[MAX_PLAYERS][3];
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
    if (!Society_PlayerData[playerid][sPLogged]) return 0;
    return (Society_PlayerData[playerid][sPAdmin] >= level);
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
    Society_PlayerData[playerid][sPAccountID] = 0;
    Society_PlayerData[playerid][sPCharID] = 0;
    Society_PlayerData[playerid][sPLogged] = false;
    Society_PlayerData[playerid][sPLoginTries] = 0;
    Society_PlayerData[playerid][sPAdmin] = 0;
    Society_PlayerData[playerid][sPCharCount] = 0;
    Society_PlayerData[playerid][sPTempPass][0] = EOS;
    Society_PlayerData[playerid][sPHunger] = 100.0;
    Society_PlayerData[playerid][sPThirst] = 100.0;
    Society_PlayerData[playerid][sPStress] = 0.0;
    Society_PlayerData[playerid][sPNeedsCD] = 0;
    Society_PlayerData[playerid][sPFactionID] = 0;
    Society_PlayerData[playerid][sPFactionRank] = 0;
    Society_PlayerData[playerid][sPFamilyID] = 0;
    Society_PlayerData[playerid][sPFamilyRank] = 0;
    for (new i = 0; i < 3; i++)
    {
        sPCharList[playerid][i][0] = EOS;
    }
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
    pCreateName[playerid][0] = EOS;
    pCreateAge[playerid] = 0;
    pCreateGender[playerid] = 0;
    pCharName[playerid][0] = EOS;
    for (new i = 0; i < 3; i++)
    {
        pCharIDs[playerid][i] = 0;
    }
    return 1;
}

//================================================================
// DATABASE
//================================================================

// Modul bisnis dinamis (di-include di sini karena memakai pCharName
// dan stock util di atas).
#include "Server_Libraries/Business/Business_System.pwn"

// Modul rumah dinamis (pola sama seperti modul bisnis).
#include "Server_Libraries/House/House_System.pwn"

// Modul kendaraan pribadi dinamis (pola sama seperti modul rumah).
#include "Server_Libraries/Vehicle/Vehicle_System.pwn"

// Modul admin DB: nama jabatan level, mode duty, daftar admin online.
#include "Server_Libraries/Admin/Admin_System.pwn"

// Modul fraksi dinamis (pola sama seperti modul bisnis).
#include "Server_Libraries/Faction/Faction_System.pwn"

// Modul bengkel dinamis (pola sama seperti modul bisnis).
#include "Server_Libraries/Workshop/Workshop_System.pwn"

// Modul garasi kota dinamis (pola sama seperti modul bengkel,
// memakai data kendaraan vGarageID dari modul Vehicle).
#include "Server_Libraries/Garage/Garage_System.pwn"

// Keluarga/gangster dinamis (di-include di sini karena memakai
// pCharName, pAdminDuty & data kendaraan pribadi dari modul lain).
#include "Server_Libraries/Family/Family_System.pwn"

// Zona dinamis: greenzone (tanpa damage/tembakan) & zona bahaya.
#include "Server_Libraries/Zone/Zone_System.pwn"

// Dealer kendaraan dinamis (di-include setelah modul Vehicle,
// karena memakai katalog kendaraan & Vehicle_Buy dari modul itu).
#include "Server_Libraries/Dealer/Dealer_System.pwn"

// SaveCharacter: menyimpan data karakter pemain ke database.
stock SaveCharacter(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new Float:x, Float:y, Float:z, Float:hp, Float:ap;
    GetPlayerPos(playerid, x, y, z);
    GetPlayerHealth(playerid, hp);
    GetPlayerArmour(playerid, ap);
    pMoney[playerid] = GetPlayerMoney(playerid);
    new query[512];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE characters SET money = %d, bank = %d, level = %d, exp = %d, pos_x = %f, pos_y = %f, pos_z = %f, interior = %d, vw = %d, health = %f, armour = %f, hunger = %f, thirst = %f, stress = %f, faction_id = %d, faction_rank = %d, family_id = %d, family_rank = %d WHERE id = %d",
        pMoney[playerid], pBank[playerid], pLevel[playerid], pExp[playerid],
        x, y, z, GetPlayerInterior(playerid), GetPlayerVirtualWorld(playerid),
        hp, ap,
        Society_PlayerData[playerid][sPHunger], Society_PlayerData[playerid][sPThirst], Society_PlayerData[playerid][sPStress],
        Society_PlayerData[playerid][sPFactionID], Society_PlayerData[playerid][sPFactionRank],
        Society_PlayerData[playerid][sPFamilyID], Society_PlayerData[playerid][sPFamilyRank],
        Society_PlayerData[playerid][sPCharID]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// LoadCharacterList: mengambil daftar karakter milik akun lalu tampilkan dialog.
stock LoadCharacterList(playerid)
{
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT id, name FROM characters WHERE account_id = %d", Society_PlayerData[playerid][sPAccountID]);
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

    g_SQL = MySQL_Connect();
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SetGameModeText("DB ERROR");
        return 1;
    }
    SetTimer("AutoSave", 600000, true); // autosave tiap 10 menit
    SetTimer("NeedsTick", 60000, true); // kebutuhan (makan/minum/stress) tiap 1 menit
    SetTimer("BusinessPayday", 3600000, true); // profit bisnis tiap 1 jam
    SetTimer("ZoneTick", 1000, true);       // cek zona tempat pemain (textdraw)
    Business_LoadAll(); // muat bisnis dinamis dari database
    House_LoadAll();    // muat rumah dinamis dari database
    Vehicle_LoadAll();  // muat kendaraan pribadi dari database
    Faction_LoadAll();  // muat fraksi dinamis dari database
    Workshop_LoadAll(); // muat bengkel dinamis dari database
    Garage_LoadAll();   // muat garasi kota dinamis dari database
    Family_LoadAll();   // muat keluarga/gangster dinamis dari database
    Zone_LoadAll();     // muat zona dinamis dari database
    Dealer_LoadAll();   // muat dealer kendaraan dinamis dari database
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
    Faction_OnConnect(playerid); // reset data sementara fraksi
    Family_OnConnect(playerid); // reset data sementara keluarga
    Zone_OnConnect(playerid);   // reset data sementara zona
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
    if (Society_PlayerData[playerid][sPLogged] && Society_PlayerData[playerid][sPCharID] > 0)
    {
        SaveCharacter(playerid);
    }
    if (Society_PlayerData[playerid][sPLogged] && Society_PlayerData[playerid][sPAccountID] > 0 && g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE accounts SET last_login = NOW() WHERE id = %d", Society_PlayerData[playerid][sPAccountID]);
        mysql_tquery(g_SQL, query);
    }
    Needs_Hide(playerid);
    Needs_DestroyTextDraws(playerid);
    House_OnDisconnect(playerid); // batalkan pembuatan rumah yang belum selesai
    Vehicle_OnDisconnect(playerid); // simpan & despawn kendaraan milik pemain
    Admin_OnDisconnect(playerid); // reset status duty admin
    Faction_OnDisconnect(playerid); // reset status duty fraksi & undangan
    Family_OnDisconnect(playerid); // reset data sementara keluarga
    Zone_OnDisconnect(playerid); // hapus textdraw zona
    Dealer_OnDisconnect(playerid); // hapus kendaraan test drive
    ResetPlayerVars(playerid);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    if (Society_PlayerData[playerid][sPLogged] && pNeedLoad[playerid])
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
        SendClientMessage(playerid, COLOR_GREY, "Ketik /help untuk melihat daftar perintah.");
        Needs_Show(playerid); // tampilkan textdraw makan/minum/stress
    }
    return 1;
}

// OnPlayerTakeDamage: damage di dalam greenzone dibatalkan
// (modul Zone: Zone_OnTakeDamage mengembalikan nyawa yang hilang).
public OnPlayerTakeDamage(playerid, issuerid, Float:amount, weaponid)
{
    Zone_OnTakeDamage(playerid, issuerid, amount, weaponid);
    return 1;
}

// OnPlayerWeaponShot: tembakan di dalam greenzone dibatalkan
// (modul Zone: Zone_OnWeaponShot mengembalikan 0 = batal).
public OnPlayerWeaponShot(playerid, weaponid, hittype, hitid, Float:fX, Float:fY, Float:fZ)
{
    return Zone_OnWeaponShot(playerid);
}

// OnPlayerStateChange: info textdraw kendaraan saat pemain mengemudi.
public OnPlayerStateChange(playerid, newstate, oldstate)
{
    Vehicle_OnStateChange(playerid, newstate, oldstate);
    return 1;
}

// OnPlayerEnterVehicle: cegah masuk ke kendaraan pribadi yang terkunci.
public OnPlayerEnterVehicle(playerid, vehicleid, ispassenger)
{
    Vehicle_OnEnterVehicle(playerid, vehicleid, ispassenger);
    return 1;
}

//================================================================
// DIALOG (easyDialog - tanpa ID dialog manual)
//================================================================

// Dialog:Login - meminta kata sandi akun yang sudah terdaftar.
Dialog:Login(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Kick(playerid);
        return 1;
    }
    new len = strlen(inputtext);
    if (len < 4 || len > 32)
    {
        Dialog_Show(playerid, Login, DIALOG_STYLE_PASSWORD, "Login",
            "Kata sandi minimal 4 karakter.\nMasukkan kata sandi akun anda:",
            "Masuk", "Keluar");
        return 1;
    }
    format(Society_PlayerData[playerid][sPTempPass], MAX_TEMP_PASS, "%s", inputtext);
    new name[MAX_PLAYER_NAME], query[192];
    GetPlayerName(playerid, name, sizeof(name));
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT id, password, admin FROM accounts WHERE username = '%e' LIMIT 1", name);
    mysql_tquery(g_SQL, query, "OnLoginCheck", "d", playerid);
    return 1;
}

// Dialog:Register - membuat kata sandi untuk akun baru.
Dialog:Register(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Kick(playerid);
        return 1;
    }
    new len = strlen(inputtext);
    if (len < 4 || len > 32)
    {
        Dialog_Show(playerid, Register, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
            "Kata sandi harus 4-32 karakter!\nBuat kata sandi untuk akun baru anda:",
            "Daftar", "Keluar");
        return 1;
    }
    format(Society_PlayerData[playerid][sPTempPass], MAX_TEMP_PASS, "%s", inputtext);
    Dialog_Show(playerid, RegisterConfirm, DIALOG_STYLE_PASSWORD, "Konfirmasi Kata Sandi",
        "Ulangi kata sandi yang baru saja anda buat:",
        "Konfirmasi", "Kembali");
    return 1;
}

// Dialog:RegisterConfirm - konfirmasi ulang kata sandi baru.
Dialog:RegisterConfirm(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Dialog_Show(playerid, Register, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
            "Buat kata sandi untuk akun baru anda (4-32 karakter):",
            "Daftar", "Keluar");
        return 1;
    }
    if (strcmp(inputtext, Society_PlayerData[playerid][sPTempPass], false) != 0)
    {
        Dialog_Show(playerid, Register, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
            "Konfirmasi tidak cocok! Ulangi dari awal.\nBuat kata sandi untuk akun baru anda (4-32 karakter):",
            "Daftar", "Keluar");
        return 1;
    }
    new name[MAX_PLAYER_NAME], hash[65], query[256];
    GetPlayerName(playerid, name, sizeof(name));
    SHA256_PassHash(Society_PlayerData[playerid][sPTempPass], name, hash, sizeof(hash));
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO accounts (username, password) VALUES ('%e', '%e')", name, hash);
    mysql_tquery(g_SQL, query, "OnAccountCreated", "d", playerid);
    return 1;
}

// Dialog:CharList - memilih karakter atau membuat karakter baru.
Dialog:CharList(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Kick(playerid);
        return 1;
    }
    new count = Society_PlayerData[playerid][sPCharCount];
    if (listitem < 0 || listitem > count) return 1;
    if (listitem == count)
    {
        // Baris "Buat Karakter Baru"
        if (count >= 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda sudah memiliki 3 karakter (maksimal).");
            LoadCharacterList(playerid);
            return 1;
        }
        Dialog_Show(playerid, CreateName, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
            "Masukkan nama karakter dengan format Nama_Belakang.\nContoh: Budi_Santoso\n(3-24 karakter)",
            "Lanjut", "Kembali");
    }
    else
    {
        LoadCharacter(playerid, pCharIDs[playerid][listitem]);
    }
    return 1;
}

// Dialog:CreateName - nama karakter baru (format Nama_Belakang).
Dialog:CreateName(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        LoadCharacterList(playerid);
        return 1;
    }
    new len = strlen(inputtext);
    if (len < 3 || len > 24 || strfind(inputtext, "_", true) == -1)
    {
        Dialog_Show(playerid, CreateName, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
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

// Dialog:CreateAge - umur karakter baru (15-80).
Dialog:CreateAge(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Dialog_Show(playerid, CreateName, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
            "Masukkan nama karakter dengan format Nama_Belakang.\nContoh: Budi_Santoso\n(3-24 karakter)",
            "Lanjut", "Kembali");
        return 1;
    }
    if (!IsNumeric(inputtext))
    {
        Dialog_Show(playerid, CreateAge, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
            "Umur harus berupa angka!\nMasukkan umur karakter (15-80 tahun):",
            "Lanjut", "Kembali");
        return 1;
    }
    new age = strval(inputtext);
    if (age < 15 || age > 80)
    {
        Dialog_Show(playerid, CreateAge, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
            "Umur harus 15-80 tahun!\nMasukkan umur karakter:",
            "Lanjut", "Kembali");
        return 1;
    }
    pCreateAge[playerid] = age;
    Dialog_Show(playerid, CreateGender, DIALOG_STYLE_LIST, "Buat Karakter - Jenis Kelamin",
        "Laki-laki\nPerempuan",
        "Pilih", "Kembali");
    return 1;
}

// Dialog:CreateGender - jenis kelamin karakter baru.
Dialog:CreateGender(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Dialog_Show(playerid, CreateAge, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
            "Masukkan umur karakter (15-80 tahun):",
            "Lanjut", "Kembali");
        return 1;
    }
    pCreateGender[playerid] = listitem; // 0 = Laki-laki, 1 = Perempuan
    Dialog_Show(playerid, CreateSkin, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
        "Masukkan ID skin karakter (0-311):",
        "Selesai", "Kembali");
    return 1;
}

// Dialog:CreateSkin - ID skin karakter baru (0-311).
Dialog:CreateSkin(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Dialog_Show(playerid, CreateGender, DIALOG_STYLE_LIST, "Buat Karakter - Jenis Kelamin",
            "Laki-laki\nPerempuan",
            "Pilih", "Kembali");
        return 1;
    }
    if (!IsNumeric(inputtext))
    {
        Dialog_Show(playerid, CreateSkin, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
            "ID skin harus berupa angka!\nMasukkan ID skin karakter (0-311):",
            "Selesai", "Kembali");
        return 1;
    }
    new skin = strval(inputtext);
    if (skin < 0 || skin > 311)
    {
        Dialog_Show(playerid, CreateSkin, DIALOG_STYLE_INPUT, "Buat Karakter - Skin",
            "ID skin harus 0-311!\nMasukkan ID skin karakter:",
            "Selesai", "Kembali");
        return 1;
    }
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO characters (account_id, name, age, gender, skin) VALUES (%d, '%e', %d, %d, %d)",
        Society_PlayerData[playerid][sPAccountID], pCreateName[playerid], pCreateAge[playerid], pCreateGender[playerid], skin);
    mysql_tquery(g_SQL, query, "OnCharCreated", "d", playerid);
    return 1;
}

// Stats_NeedLabel: label kondisi makan/minum: >=70 baik, 30-69 cukup, <30 buruk.
stock Stats_NeedLabel(Float:value, dest[], len, good[], bad[])
{
    if (value >= 70.0) format(dest, len, "%s", good);
    else if (value >= 30.0) format(dest, len, "Cukup");
    else format(dest, len, "%s", bad);
}

// Stats_StressLabel: label stress: <30 santai, <70 tegang, >=70 stres berat.
stock Stats_StressLabel(Float:value, dest[], len)
{
    if (value < 30.0) format(dest, len, "Santai");
    else if (value < 70.0) format(dest, len, "Tegang");
    else format(dest, len, "Stres Berat");
}

// Stats_ShowMenu: menampilkan menu utama /stats.
stock Stats_ShowMenu(playerid)
{
    Dialog_Show(playerid, StatsMenu, DIALOG_STYLE_LIST, "Statistik Karakter",
        "Informasi Umum\nKeuangan\nKebutuhan\nAset",
        "Pilih", "Tutup");
}

// Dialog:StatsMenu - menu utama /stats (dialog bertingkat).
Dialog:StatsMenu(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new info[512];
    switch (listitem)
    {
        case 0: // Informasi Umum
        {
            new gender[12], admin[32], title[16];
            if (pGender[playerid] == 1) format(gender, sizeof(gender), "Perempuan");
            else format(gender, sizeof(gender), "Laki-laki");
            Admin_Name(Society_PlayerData[playerid][sPAdmin], title, sizeof(title));
            if (Society_PlayerData[playerid][sPAdmin] > 0) format(admin, sizeof(admin), "Ya (Level %d - %s)", Society_PlayerData[playerid][sPAdmin], title);
            else format(admin, sizeof(admin), "Tidak");
            format(info, sizeof(info),
                "Nama: %s\nUmur: %d tahun\nJenis Kelamin: %s\nLevel: %d\nEXP: %d\nAdmin: %s",
                pCharName[playerid], pAge[playerid], gender,
                pLevel[playerid], pExp[playerid], admin);
            Dialog_Show(playerid, StatsSub, DIALOG_STYLE_MSGBOX, "Informasi Umum", info, "Kembali", "");
        }
        case 1: // Keuangan
        {
            new uang[32], bank[32], total[32];
            pMoney[playerid] = GetPlayerMoney(playerid);
            FormatRupiah(pMoney[playerid], uang, sizeof(uang));
            FormatRupiah(pBank[playerid], bank, sizeof(bank));
            FormatRupiah(pMoney[playerid] + pBank[playerid], total, sizeof(total));
            format(info, sizeof(info),
                "Uang Tunai: %s\nTabungan Bank: %s\nTotal Kekayaan: %s",
                uang, bank, total);
            Dialog_Show(playerid, StatsSub, DIALOG_STYLE_MSGBOX, "Keuangan", info, "Kembali", "");
        }
        case 2: // Kebutuhan
        {
            new makan[16], minum[16], stress[16];
            Stats_NeedLabel(Society_PlayerData[playerid][sPHunger], makan, sizeof(makan), "Kenyang", "Lapar");
            Stats_NeedLabel(Society_PlayerData[playerid][sPThirst], minum, sizeof(minum), "Segar", "Haus");
            Stats_StressLabel(Society_PlayerData[playerid][sPStress], stress, sizeof(stress));
            format(info, sizeof(info),
                "Makan: %d (%s)\nMinum: %d (%s)\nStress: %d (%s)\n\nJaga kebutuhanmu dengan /eat dan /drink.",
                floatround(Society_PlayerData[playerid][sPHunger], floatround_round), makan,
                floatround(Society_PlayerData[playerid][sPThirst], floatround_round), minum,
                floatround(Society_PlayerData[playerid][sPStress], floatround_round), stress);
            Dialog_Show(playerid, StatsSub, DIALOG_STYLE_MSGBOX, "Kebutuhan", info, "Kembali", "");
        }
        case 3: // Aset
        {
            new biz = Business_CountOwned(Society_PlayerData[playerid][sPCharID]);
            new rumah = House_CountOwned(Society_PlayerData[playerid][sPCharID]);
            new kendaraan = Vehicle_CountOwned(Society_PlayerData[playerid][sPCharID]);
            new bengkel = Workshop_CountOwned(Society_PlayerData[playerid][sPCharID]);
            format(info, sizeof(info),
                "Bisnis: %d\nRumah: %d\nKendaraan: %d (maks 2)\nBengkel: %d",
                biz, rumah, kendaraan, bengkel);
            Dialog_Show(playerid, StatsSub, DIALOG_STYLE_MSGBOX, "Aset", info, "Kembali", "");
        }
    }
    return 1;
}

// Dialog:StatsSub - sub-dialog /stats, tombol Kembali membuka menu lagi.
Dialog:StatsSub(playerid, response, listitem, inputtext[])
{
    if (response) Stats_ShowMenu(playerid);
    return 1;
}

// Dialog:Help - dialog info, abaikan respon.
Dialog:Help(playerid, response, listitem, inputtext[])
{
    return 1;
}

//================================================================
// COMMAND
//================================================================

public OnPlayerCommandText(playerid, cmdtext[])
{
    new cmd[32], idx = 0;
    cmd = strtok(cmdtext, idx);

    // /stats - menu statistik karakter (dialog bertingkat: umum, keuangan, kebutuhan, aset)
    if (strcmp(cmd, "/stats", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Stats_ShowMenu(playerid);
        return 1;
    }

    // /money - melihat jumlah uang dalam format rupiah
    if (strcmp(cmd, "/money", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
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
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        SaveCharacter(playerid);
        SendClientMessage(playerid, COLOR_GREEN, "Data tersimpan.");
        return 1;
    }

    // /eat - mengisi kebutuhan makan (+35)
    if (strcmp(cmd, "/eat", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Needs_Eat(playerid);
        return 1;
    }

    // /drink - mengisi kebutuhan minum (+35)
    if (strcmp(cmd, "/drink", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Needs_Drink(playerid);
        return 1;
    }

    // /help - daftar perintah
    if (strcmp(cmd, "/help", true) == 0)
    {
        Dialog_Show(playerid, Help, DIALOG_STYLE_MSGBOX, "Bantuan",
            "Perintah Pemain:\n/stats - Melihat statistik karakter\n/money - Melihat jumlah uang\n/eat - Makan untuk mengisi kebutuhan makan\n/drink - Minum untuk mengisi kebutuhan minum\n/save - Menyimpan data karakter\n/help - Membuka menu ini\n\nBisnis:\n/buybusiness - Membeli bisnis di dekatmu\n/bizinfo - Mengelola bisnismu (ambil untung, kunci, jual)\n/bizwithdraw - Mengambil keuntungan bisnis\n/sellbusiness - Menjual kembali bisnismu\nTekan ENTER (F) di dekat bisnis untuk interaksi\n\nRumah:\n/buyhouse - Membeli rumah di dekatmu (atau tekan ENTER di depan rumah dijual)\nTekan ENTER (F) di depan pintu rumah untuk masuk/keluar\n/houseinfo - Mengelola rumahmu (kunci/buka, jual)\n/lockhouse - Mengunci/membuka rumahmu\n/sellhouse - Menjual kembali rumahmu\n\nKendaraan:\n/buyvehicle - Membeli kendaraan pribadi\n/vlist - Melihat & mengelola kendaraanmu\n/vpark - Menyimpan posisi parkir kendaraan\n/vlock - Mengunci/membuka kendaraanmu\n\nFraksi:\n/finfo - Info fraksimu & daftar anggota\n/factions - Daftar semua fraksi di server\n/f [pesan] - Chat khusus anggota fraksi\n/duty - Mulai/selesai duty (seragam & senjata dinas, di markas)\n/finvite [id] - Undang pemain (Wakil Ketua+)\n/fkick [id] - Keluarkan anggota (Wakil Ketua+)\n/fquit - Keluar dari fraksi\n/setrank [id] [rank] - Atur rank anggota (Ketua)\n/fdeposit [jumlah] - Setor ke kas fraksi\n/fwithdraw [jumlah] - Ambil kas fraksi (Ketua)\n\nKeluarga:\n/createfamily [nama] - Dirikan keluarga/gangster (Rp50 juta tunai)\n/faminfo - Info keluargamu & daftar anggota\n/families - Daftar semua keluarga di server\n/fam [pesan] - Chat khusus anggota keluarga\n/famcolor - Ganti warna identitas keluarga (Ketua)\n/faminvite [id] - Undang pemain (Tangan Kanan+)\n/famkick [id] - Keluarkan anggota (Tangan Kanan+)\n/famquit - Keluar dari keluarga\n/setfamrank [id] [rank] - Atur rank anggota (Ketua)\n/famdeposit [jumlah] - Setor ke kas keluarga\n/famwithdraw [jumlah] - Ambil kas keluarga (Ketua)\n\nBengkel:\n/buyworkshop - Membeli bengkel di dekatmu\n/wsinfo - Mengelola bengkelmu (ambil untung, jual)\n/wswithdraw - Mengambil keuntungan bengkel\n/repair - Perbaiki kendaraanmu di bengkel\n/mod - Modifikasi kendaraan (warna, komponen, neon) di bengkel\n\nGarasi Kota:\n/garage - Titip / ambil kendaraan di garasi terdekat\n/garages - Daftar semua garasi kota\n\nZona:\n/zones - Daftar & detail zona dinamis\n\nDealer Kendaraan:\n/dealer - Showroom dealer terdekat (lihat stok, test drive, beli kendaraan)\n/dealers - Daftar semua dealer di server\n/buydealer - Membeli dealer di dekatmu\n/dealerinfo - Mengelola dealermu (info, ambil komisi, jual)\n/dealerwithdraw - Mengambil komisi penjualan dealer\n/selldealer - Menjual kembali dealermu\n\nPerintah Admin:\n/setadmin [id] [level] - (RCON) Atur level admin\n/adminduty - Nyalakan/matikan mode duty (nama berwarna oranye)\n/admins - Melihat daftar admin online\n/createbisnis [nama] [tipe] [harga] - (Admin 3+) Buat bisnis dinamis\n/createhouse [harga] [tipe] [lokasi] - (Admin 3+) Buat rumah dinamis 2 langkah (tipe 0=Small 1=Medium 2=Large)\n/createfaction [tipe] [nama] - (Admin 3+) Buat fraksi dinamis di posisimu\n/fsetleader [id] - (Admin 4+) Tunjuk ketua fraksi\n/famsetleader [id] - (Admin 4+) Tunjuk ketua keluarga\n/createws [nama] [harga] - (Admin 3+) Buat bengkel dinamis di posisimu\n/creategarage [nama] [biaya] - (Admin 3+) Buat garasi kota di posisimu\n/createzone [nama] [tipe] - (Admin 3+) Buat zona 100x100m (0=Greenzone, 1=Zona Bahaya)\n/deletezone - (Admin 4+) Hapus zona tempatmu berdiri\n/createdealer [nama] [tipe] [harga] - (Admin 3+) Buat dealer kendaraan di posisimu (tipe 0=Umum, 1=Ekonomis, 2=Sport, 3=Motor)\n/kick [id] [alasan] - Tendang pemain dari server\n/ban [id] [alasan] - Blokir pemain dari server",
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
        if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged] || Society_PlayerData[target][sPAccountID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Pemain tidak valid atau belum login.");
            return 1;
        }
        if (level < 0 || level > 5)
        {
            SendClientMessage(playerid, COLOR_RED, "Level admin harus antara 0-5.");
            return 1;
        }
        Society_PlayerData[target][sPAdmin] = level;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE accounts SET admin = %d WHERE id = %d", level, Society_PlayerData[target][sPAccountID]);
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

    // /adminduty - admin level 1+: nyalakan/matikan mode duty (nama berwarna)
    if (strcmp(cmd, "/adminduty", true) == 0)
    {
        if (!IsAdmin(playerid, 1))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        Admin_ToggleDuty(playerid);
        Family_ApplyColor(playerid); // kembalikan warna nama (keluarga/oranye/normal)
        return 1;
    }

    // /admins - daftar admin yang sedang online (semua pemain)
    if (strcmp(cmd, "/admins", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged])
        {
            SendClientMessage(playerid, COLOR_RED, "Anda harus login terlebih dahulu.");
            return 1;
        }
        Admin_ShowList(playerid);
        return 1;
    }

    // /createbisnis [nama] [tipe] [harga] - admin level 3+: membuat bisnis dinamis
    if (strcmp(cmd, "/createbisnis", true) == 0)
    {
        if (!IsAdmin(playerid, 3))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new snama[32], stipe[32], sharga[32];
        snama = strtok(cmdtext, idx);
        stipe = strtok(cmdtext, idx);
        sharga = strtok(cmdtext, idx);
        if (!strlen(snama) || !strlen(stipe) || !strlen(sharga))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createbisnis [nama] [tipe] [harga]");
            SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=Warung Makan, 1=Toko Kelontong, 2=Restoran, 3=Bar, 4=Toko Pakaian, 5=Hotel");
            SendClientMessage(playerid, COLOR_GREY, "Contoh: /createbisnis Warung_Barokah 0 5000000 (spasi diganti _)");
            return 1;
        }
        if (strlen(snama) < 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Nama bisnis minimal 3 karakter.");
            return 1;
        }
        if (!IsNumeric(stipe) || !IsNumeric(sharga))
        {
            SendClientMessage(playerid, COLOR_RED, "Tipe dan harga harus berupa angka.");
            return 1;
        }
        new type = strval(stipe), price = strval(sharga);
        if (type < 0 || type >= BUSINESS_TYPES)
        {
            SendClientMessage(playerid, COLOR_RED, "Tipe bisnis harus 0-5.");
            return 1;
        }
        if (price < 100000 || price > 100000000)
        {
            SendClientMessage(playerid, COLOR_RED, "Harga bisnis harus Rp100.000 - Rp100.000.000.");
            return 1;
        }
        for (new i = 0; snama[i] != EOS; i++)
        {
            if (snama[i] == '_') snama[i] = ' ';
        }
        Business_Create(playerid, snama, type, price);
        return 1;
    }

    // /buybusiness - membeli bisnis yang belum ada pemiliknya (di dekat pickup)
    if (strcmp(cmd, "/buybusiness", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Business_Nearest(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada bisnis di dekatmu.");
            return 1;
        }
        Business_Buy(playerid, slot);
        return 1;
    }

    // /bizinfo - dialog kelola bisnis milik sendiri (di dekat bisnis)
    if (strcmp(cmd, "/bizinfo", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Business_ShowInfo(playerid);
        return 1;
    }

    // /bizwithdraw - mengambil keuntungan bisnis milik sendiri
    if (strcmp(cmd, "/bizwithdraw", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Business_OwnedNear(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada bisnismu di dekat sini.");
            return 1;
        }
        Business_Collect(playerid, slot);
        return 1;
    }

    // /sellbusiness - menjual kembali bisnismu (70% dari harga beli)
    if (strcmp(cmd, "/sellbusiness", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Business_OwnedNear(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada bisnismu di dekat sini.");
            return 1;
        }
        pBizMenuSlot[playerid] = slot;
        new harga[32], msg[256];
        FormatRupiah((bPrice[slot] * BUSINESS_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual bisnis \"%s\"?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            bName[slot], harga, BUSINESS_SELL_RATE);
        Dialog_Show(playerid, BizSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Bisnis", msg, "Jual", "Batal");
        return 1;
    }

    // /createhouse [harga] [type] [lokasi] - admin level 3+: membuat rumah dinamis (2 langkah)
    // Langkah 1: berdiri di posisi PINTU MASUK -> /createhouse [harga] [type] [lokasi]
    // Langkah 2: pergi ke titik PINTU KELUAR di dalam interior -> /createhouse
    // type: 0=Small, 1=Medium, 2=Large. lokasi: nama area, spasi diganti _ (cth: Pasar_Baru)
    if (strcmp(cmd, "/createhouse", true) == 0)
    {
        if (!IsAdmin(playerid, 3))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new sharga[32], stype[32], slokasi[64];
        sharga = strtok(cmdtext, idx);
        stype = strtok(cmdtext, idx);
        slokasi = strtok(cmdtext, idx);
        if (strlen(sharga) && strlen(stype) && strlen(slokasi))
        {
            // Langkah 1: catat pintu masuk + tipe + lokasi.
            if (!IsNumeric(sharga) || !IsNumeric(stype))
            {
                SendClientMessage(playerid, COLOR_RED, "Harga dan tipe harus berupa angka.");
                return 1;
            }
            new price = strval(sharga), type = strval(stype);
            if (price < 1000000 || price > 100000000)
            {
                SendClientMessage(playerid, COLOR_RED, "Harga rumah harus Rp1.000.000 - Rp100.000.000.");
                return 1;
            }
            if (type < 0 || type > 2)
            {
                SendClientMessage(playerid, COLOR_RED, "Tipe rumah harus 0=Small, 1=Medium, 2=Large.");
                return 1;
            }
            if (strlen(slokasi) < 3 || strlen(slokasi) > 60)
            {
                SendClientMessage(playerid, COLOR_RED, "Nama lokasi harus 3-60 karakter.");
                return 1;
            }
            for (new i = 0; slokasi[i] != EOS; i++)
            {
                if (slokasi[i] == '_') slokasi[i] = ' ';
            }
            House_CreateStep1(playerid, price, type, slokasi);
        }
        else
        {
            // Langkah 2: catat pintu keluar & simpan.
            if (pHouseStep[playerid] != 1)
            {
                SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createhouse [harga] [tipe] [lokasi]");
                SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=Small, 1=Medium, 2=Large. Lokasi: nama area (spasi diganti _).");
                SendClientMessage(playerid, COLOR_GREY, "Berdiri di posisi pintu MASUK, ketik perintah di atas,");
                SendClientMessage(playerid, COLOR_GREY, "lalu pergi ke titik pintu KELUAR di interior dan ketik /createhouse.");
                return 1;
            }
            House_CreateStep2(playerid);
        }
        return 1;
    }

    // /buyhouse - membeli rumah yang belum ada pemiliknya (di dekat pintu masuk)
    if (strcmp(cmd, "/buyhouse", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = House_NearestEntrance(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada rumah di dekatmu.");
            return 1;
        }
        House_Buy(playerid, slot);
        return 1;
    }

    // /houseinfo - dialog kelola rumah milik sendiri
    if (strcmp(cmd, "/houseinfo", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        House_ShowInfo(playerid);
        return 1;
    }

    // /lockhouse - mengunci/membuka rumah milik sendiri
    if (strcmp(cmd, "/lockhouse", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = House_OwnedNear(playerid);
        if (slot == -1) slot = House_InsideHouse(playerid);
        if (slot == -1 || hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada rumahmu di dekat sini.");
            return 1;
        }
        House_ToggleLock(playerid, slot);
        return 1;
    }

    // /sellhouse - menjual kembali rumahmu (70% dari harga beli)
    if (strcmp(cmd, "/sellhouse", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = House_OwnedNear(playerid);
        if (slot == -1 || hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada rumahmu di dekat sini.");
            return 1;
        }
        pHouseMenuSlot[playerid] = slot;
        new harga[32], msg[256];
        FormatRupiah((hPrice[slot] * HOUSE_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual rumah #%d?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            hDBID[slot], harga, HOUSE_SELL_RATE);
        Dialog_Show(playerid, HouseSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Rumah", msg, "Jual", "Batal");
        return 1;
    }

    // /buyvehicle - membuka katalog & membeli kendaraan pribadi (maks 2 per karakter)
    if (strcmp(cmd, "/buyvehicle", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        if (Vehicle_CountOwned(Society_PlayerData[playerid][sPCharID]) >= MAX_VEH_PER_CHAR)
        {
            SendClientMessage(playerid, COLOR_RED, "Kamu sudah punya 2 kendaraan (maksimal).");
            return 1;
        }
        new list[1024];
        Vehicle_BuildBuyList(list, sizeof(list));
        Dialog_Show(playerid, VehBuy, DIALOG_STYLE_LIST, "Beli Kendaraan", list, "Pilih", "Tutup");
        return 1;
    }

    // /vpark - menyimpan posisi parkir kendaraan yang sedang dikemudikan
    if (strcmp(cmd, "/vpark", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Vehicle_Park(playerid);
        return 1;
    }

    // /vlock - mengunci/membuka kendaraanmu (yang dikemudikan atau terdekat)
    if (strcmp(cmd, "/vlock", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = -1;
        if (IsPlayerInAnyVehicle(playerid))
        {
            slot = Vehicle_SlotFromVehID(GetPlayerVehicleID(playerid));
        }
        if (slot == -1) slot = Vehicle_OwnedNear(playerid);
        if (slot == -1 || vOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada kendaraanmu di dekat sini.");
            return 1;
        }
        Vehicle_ToggleLock(playerid, slot);
        return 1;
    }

    // /vlist - daftar & kelola kendaraan pribadimu (info, kunci/buka, lacak)
    if (strcmp(cmd, "/vlist", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Vehicle_ShowList(playerid);
        return 1;
    }

    // /createfaction [tipe] [nama] - admin level 3+: membuat fraksi dinamis di posisi admin
    if (strcmp(cmd, "/createfaction", true) == 0)
    {
        if (!IsAdmin(playerid, 3))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new stipe[32], snama[32];
        stipe = strtok(cmdtext, idx);
        snama = strtok(cmdtext, idx);
        if (!strlen(stipe) || !strlen(snama))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createfaction [tipe] [nama]");
            SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=LSPD (Polisi), 1=EMS (Medis), 2=Pemerintah, 3=Montir, 4=News");
            SendClientMessage(playerid, COLOR_GREY, "Contoh: /createfaction 0 LSPD_Los_Santos (spasi diganti _)");
            return 1;
        }
        if (strlen(snama) < 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Nama fraksi minimal 3 karakter.");
            return 1;
        }
        if (!IsNumeric(stipe))
        {
            SendClientMessage(playerid, COLOR_RED, "Tipe fraksi harus berupa angka.");
            return 1;
        }
        new type = strval(stipe);
        if (type < 0 || type >= FACTION_TYPES)
        {
            SendClientMessage(playerid, COLOR_RED, "Tipe fraksi harus 0-4.");
            return 1;
        }
        for (new i = 0; snama[i] != EOS; i++)
        {
            if (snama[i] == '_') snama[i] = ' ';
        }
        Faction_Create(playerid, type, snama);
        return 1;
    }

    // /fsetleader [id] - admin level 4+: menunjuk ketua fraksi baru (harus sudah anggota)
    if (strcmp(cmd, "/fsetleader", true) == 0)
    {
        if (!IsAdmin(playerid, 4))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /fsetleader [id]");
            return 1;
        }
        Faction_SetLeader(playerid, strval(sid));
        return 1;
    }

    // /finvite [id] - pimpinan (Wakil Ketua+) mengundang pemain ke fraksi
    if (strcmp(cmd, "/finvite", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /finvite [id]");
            return 1;
        }
        Faction_Invite(playerid, strval(sid));
        return 1;
    }

    // /fkick [id] - pimpinan (Wakil Ketua+) mengeluarkan anggota fraksi
    if (strcmp(cmd, "/fkick", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /fkick [id]");
            return 1;
        }
        Faction_Kick(playerid, strval(sid));
        return 1;
    }

    // /fquit - keluar dari fraksi sendiri
    if (strcmp(cmd, "/fquit", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Faction_Quit(playerid);
        return 1;
    }

    // /setrank [id] [rank] - ketua mengatur rank anggota (1-5)
    if (strcmp(cmd, "/setrank", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32], srank[32];
        sid = strtok(cmdtext, idx);
        srank = strtok(cmdtext, idx);
        if (!strlen(sid) || !strlen(srank))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /setrank [id] [rank]");
            SendClientMessage(playerid, COLOR_GREY, "Rank: 1=Rekrut, 2=Anggota, 3=Senior, 4=Perwira, 5=Wakil Ketua");
            return 1;
        }
        Faction_SetRank(playerid, strval(sid), strval(srank));
        return 1;
    }

    // /f [pesan] - chat khusus anggota fraksi
    if (strcmp(cmd, "/f", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new text[128];
        if (!GetCmdRest(cmdtext, idx, text, sizeof(text)))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /f [pesan]");
            return 1;
        }
        Faction_Chat(playerid, text);
        return 1;
    }

    // /duty - mulai/selesai duty fraksi (harus di markas): seragam + senjata dinas
    if (strcmp(cmd, "/duty", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Faction_ToggleDuty(playerid);
        return 1;
    }

    // /finfo - info fraksi sendiri + daftar anggota
    if (strcmp(cmd, "/finfo", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Faction_ShowInfo(playerid);
        return 1;
    }

    // /factions - daftar semua fraksi di server
    if (strcmp(cmd, "/factions", true) == 0)
    {
        Faction_ShowList(playerid);
        return 1;
    }

    // /fdeposit [jumlah] - setor uang tunai ke kas fraksi
    if (strcmp(cmd, "/fdeposit", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sjumlah[32];
        sjumlah = strtok(cmdtext, idx);
        if (!strlen(sjumlah) || !IsNumeric(sjumlah))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /fdeposit [jumlah]");
            return 1;
        }
        Faction_Deposit(playerid, strval(sjumlah));
        return 1;
    }

    // /fwithdraw [jumlah] - ketua mengambil uang dari kas fraksi
    if (strcmp(cmd, "/fwithdraw", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sjumlah[32];
        sjumlah = strtok(cmdtext, idx);
        if (!strlen(sjumlah) || !IsNumeric(sjumlah))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /fwithdraw [jumlah]");
            return 1;
        }
        Faction_Withdraw(playerid, strval(sjumlah));
        return 1;
    }

    // /createfamily [nama] - mendirikan keluarga/gangster baru (bayar Rp50 juta tunai)
    if (strcmp(cmd, "/createfamily", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new snama[32];
        snama = strtok(cmdtext, idx);
        if (!strlen(snama))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createfamily [nama]");
            SendClientMessage(playerid, COLOR_GREY, "Contoh: /createfamily Grove_Street (spasi diganti _)");
            return 1;
        }
        if (strlen(snama) < 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Nama keluarga minimal 3 karakter.");
            return 1;
        }
        for (new i = 0; snama[i] != EOS; i++)
        {
            if (snama[i] == '_') snama[i] = ' ';
        }
        Family_Create(playerid, snama);
        return 1;
    }

    // /faminvite [id] - pimpinan (Tangan Kanan+) mengundang pemain ke keluarga
    if (strcmp(cmd, "/faminvite", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /faminvite [id]");
            return 1;
        }
        Family_Invite(playerid, strval(sid));
        return 1;
    }

    // /famkick [id] - pimpinan (Tangan Kanan+) mengeluarkan anggota keluarga
    if (strcmp(cmd, "/famkick", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /famkick [id]");
            return 1;
        }
        Family_Kick(playerid, strval(sid));
        return 1;
    }

    // /setfamrank [id] [rank] - ketua mengatur rank anggota keluarga (1-5)
    if (strcmp(cmd, "/setfamrank", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sid[32], srank[32];
        sid = strtok(cmdtext, idx);
        srank = strtok(cmdtext, idx);
        if (!strlen(sid) || !strlen(srank))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /setfamrank [id] [rank]");
            SendClientMessage(playerid, COLOR_GREY, "Rank: 1=Preman, 2=Anak Buah, 3=Penegak, 4=Kapten, 5=Tangan Kanan");
            return 1;
        }
        Family_SetRank(playerid, strval(sid), strval(srank));
        return 1;
    }

    // /fam [pesan] - chat khusus anggota keluarga (berwarna identitas keluarga)
    if (strcmp(cmd, "/fam", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new text[128];
        if (!GetCmdRest(cmdtext, idx, text, sizeof(text)))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /fam [pesan]");
            return 1;
        }
        Family_Chat(playerid, text);
        return 1;
    }

    // /famquit - keluar dari keluarga sendiri
    if (strcmp(cmd, "/famquit", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Family_Quit(playerid);
        return 1;
    }

    // /faminfo - info keluargamu + daftar anggota + kas
    if (strcmp(cmd, "/faminfo", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Family_ShowInfo(playerid);
        return 1;
    }

    // /families - daftar semua keluarga di server
    if (strcmp(cmd, "/families", true) == 0)
    {
        Family_ShowList(playerid);
        return 1;
    }

    // /famcolor - ketua memilih warna identitas keluarga (dialog)
    if (strcmp(cmd, "/famcolor", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Family_ShowColorPicker(playerid);
        return 1;
    }

    // /famdeposit [jumlah] - setor uang tunai ke kas keluarga
    if (strcmp(cmd, "/famdeposit", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sjumlah[32];
        sjumlah = strtok(cmdtext, idx);
        if (!strlen(sjumlah) || !IsNumeric(sjumlah))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /famdeposit [jumlah]");
            return 1;
        }
        Family_Deposit(playerid, strval(sjumlah));
        return 1;
    }

    // /famwithdraw [jumlah] - ketua mengambil uang dari kas keluarga
    if (strcmp(cmd, "/famwithdraw", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new sjumlah[32];
        sjumlah = strtok(cmdtext, idx);
        if (!strlen(sjumlah) || !IsNumeric(sjumlah))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /famwithdraw [jumlah]");
            return 1;
        }
        Family_Withdraw(playerid, strval(sjumlah));
        return 1;
    }

    // /famsetleader [id] - admin level 4+: menunjuk ketua keluarga baru (harus sudah anggota)
    if (strcmp(cmd, "/famsetleader", true) == 0)
    {
        if (!IsAdmin(playerid, 4))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        new sid[32];
        sid = strtok(cmdtext, idx);
        if (!strlen(sid))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /famsetleader [id]");
            return 1;
        }
        Family_SetLeader(playerid, strval(sid));
        return 1;
    }

    // /createws [nama] [harga] - admin level 3+: membuat bengkel dinamis di posisi admin
    if (strcmp(cmd, "/createws", true) == 0)
    {
        if (!IsAdmin(playerid, 3))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new snama[32], sharga[32];
        snama = strtok(cmdtext, idx);
        sharga = strtok(cmdtext, idx);
        if (!strlen(snama) || !strlen(sharga))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createws [nama] [harga]");
            SendClientMessage(playerid, COLOR_GREY, "Contoh: /createws Bengkel_Barokah 5000000 (spasi diganti _)");
            return 1;
        }
        if (strlen(snama) < 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Nama bengkel minimal 3 karakter.");
            return 1;
        }
        if (!IsNumeric(sharga))
        {
            SendClientMessage(playerid, COLOR_RED, "Harga harus berupa angka.");
            return 1;
        }
        new price = strval(sharga);
        if (price < 100000 || price > 100000000)
        {
            SendClientMessage(playerid, COLOR_RED, "Harga bengkel harus Rp100.000 - Rp100.000.000.");
            return 1;
        }
        for (new i = 0; snama[i] != EOS; i++)
        {
            if (snama[i] == '_') snama[i] = ' ';
        }
        Workshop_Create(playerid, snama, price);
        return 1;
    }

    // /buyworkshop - membeli bengkel yang belum ada pemiliknya (di dekat pickup)
    if (strcmp(cmd, "/buyworkshop", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Workshop_Nearest(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada bengkel di dekatmu.");
            return 1;
        }
        Workshop_Buy(playerid, slot);
        return 1;
    }

    // /wsinfo - dialog kelola bengkel milik sendiri (di dekat bengkel)
    if (strcmp(cmd, "/wsinfo", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Workshop_ShowInfo(playerid);
        return 1;
    }

    // /wswithdraw - mengambil keuntungan bengkel milik sendiri
    if (strcmp(cmd, "/wswithdraw", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Workshop_OwnedNear(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada bengkelmu di dekat sini.");
            return 1;
        }
        Workshop_Collect(playerid, slot);
        return 1;
    }

    // /repair - memperbaiki kendaraan yang dikemudikan di dekat bengkel
    if (strcmp(cmd, "/repair", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Workshop_Repair(playerid);
        return 1;
    }

    // /mod - memodifikasi kendaraan (warna, komponen, neon) di dekat bengkel
    if (strcmp(cmd, "/mod", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Workshop_ShowModMenu(playerid);
        return 1;
    }

    // /creategarage [nama] [biaya] - admin level 3+: membuat garasi kota di posisi admin
    if (strcmp(cmd, "/creategarage", true) == 0)
    {
        if (!IsAdmin(playerid, 3))
        {
            SendClientMessage(playerid, COLOR_RED, "Anda tidak memiliki akses ke perintah ini.");
            return 1;
        }
        if (g_SQL == MYSQL_INVALID_HANDLE)
        {
            SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
            return 1;
        }
        new snama[32], sbiaya[32];
        snama = strtok(cmdtext, idx);
        sbiaya = strtok(cmdtext, idx);
        if (!strlen(snama) || !strlen(sbiaya))
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /creategarage [nama] [biaya]");
            SendClientMessage(playerid, COLOR_GREY, "Contoh: /creategarage Garasi_Pusat 50000 (spasi diganti _)");
            return 1;
        }
        if (strlen(snama) < 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Nama garasi minimal 3 karakter.");
            return 1;
        }
        if (!IsNumeric(sbiaya))
        {
            SendClientMessage(playerid, COLOR_RED, "Biaya harus berupa angka.");
            return 1;
        }
        new fee = strval(sbiaya);
        if (fee < 0 || fee > 500000)
        {
            SendClientMessage(playerid, COLOR_RED, "Biaya titip harus Rp0 - Rp500.000.");
            return 1;
        }
        for (new i = 0; snama[i] != EOS; i++)
        {
            if (snama[i] == '_') snama[i] = ' ';
        }
        Garage_Create(playerid, snama, fee);
        return 1;
    }

    // /garage - menu garasi terdekat: titip / ambil / info kendaraan
    if (strcmp(cmd, "/garage", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        new slot = Garage_Nearest(playerid);
        if (slot == -1)
        {
            SendClientMessage(playerid, COLOR_RED, "Tidak ada garasi di dekatmu.");
            return 1;
        }
        Garage_ShowMain(playerid, slot);
        return 1;
    }

    // /garages - daftar semua garasi kota di server
    if (strcmp(cmd, "/garages", true) == 0)
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
            return 1;
        }
        Garage_ShowList(playerid);
        return 1;
    }

    // /createzone [nama] [tipe] - admin 3+: membuat zona dinamis (0=Greenzone, 1=Zona Bahaya)
    if (strcmp(cmd, "/createzone", true) == 0)
    {
        Zone_CmdCreate(playerid, cmdtext, idx);
        return 1;
    }

    // /zones - dialog daftar zona dinamis
    if (strcmp(cmd, "/zones", true) == 0)
    {
        Zone_CmdList(playerid);
        return 1;
    }

    // /deletezone - admin 4+: menghapus zona tempat admin berdiri
    if (strcmp(cmd, "/deletezone", true) == 0)
    {
        Zone_CmdDelete(playerid);
        return 1;
    }

    // /createdealer [nama] [tipe] [harga] - admin 3+: membuat dealer kendaraan
    if (strcmp(cmd, "/createdealer", true) == 0)
    {
        Dealer_CmdCreate(playerid, cmdtext, idx);
        return 1;
    }

    // /buydealer - membeli dealer yang dijual (di dekat pickup dealer)
    if (strcmp(cmd, "/buydealer", true) == 0)
    {
        Dealer_CmdBuy(playerid);
        return 1;
    }

    // /dealer - showroom di dealer terdekat (lihat stok, test drive, beli)
    if (strcmp(cmd, "/dealer", true) == 0)
    {
        Dealer_CmdShowroom(playerid);
        return 1;
    }

    // /dealerinfo - dialog kelola dealer milikmu
    if (strcmp(cmd, "/dealerinfo", true) == 0)
    {
        Dealer_CmdInfo(playerid);
        return 1;
    }

    // /dealerwithdraw - mengambil komisi penjualan dealer milikmu
    if (strcmp(cmd, "/dealerwithdraw", true) == 0)
    {
        Dealer_CmdWithdraw(playerid);
        return 1;
    }

    // /selldealer - menjual kembali dealermu (70% dari harga beli)
    if (strcmp(cmd, "/selldealer", true) == 0)
    {
        Dealer_CmdSell(playerid);
        return 1;
    }

    // /dealers - daftar semua dealer di server
    if (strcmp(cmd, "/dealers", true) == 0)
    {
        Dealer_CmdList(playerid);
        return 1;
    }

    SendClientMessage(playerid, COLOR_GREY, "Perintah tidak dikenal. Ketik /help.");
    return 1;
}

//================================================================
// INTERAKSI TOMBOL
//================================================================

// OnPlayerKeyStateChange: tombol ENTER (F) untuk interaksi pintu rumah & bisnis.
// - Di dalam rumah + dekat pintu keluar -> keluar rumah.
// - Di depan pintu rumah dijual -> dialog konfirmasi beli.
// - Di depan pintu rumah dimiliki -> masuk rumah.
// - Di dekat bisnis dijual -> dialog konfirmasi beli.
// - Di dekat bisnis sendiri -> dialog kelola (/bizinfo).
// - Di dekat bisnis orang lain -> info singkat.
public OnPlayerKeyStateChange(playerid, newkeys, oldkeys)
{
    if ((newkeys & KEY_SECONDARY_ATTACK) && !(oldkeys & KEY_SECONDARY_ATTACK))
    {
        if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 1;
        if (IsPlayerInAnyVehicle(playerid)) return 1;

        // 1. Sedang di dalam rumah & dekat pintu keluar -> keluar.
        new inslot = House_InsideHouse(playerid);
        if (inslot != -1)
        {
            if (GetPlayerDistanceFromPoint(playerid, hExitX[inslot], hExitY[inslot], hExitZ[inslot]) <= HOUSE_RANGE)
            {
                House_Exit(playerid, inslot);
                return 1;
            }
        }

        // 2. Dekat pintu masuk rumah.
        new hslot = House_NearestEntrance(playerid);
        if (hslot != -1)
        {
            if (hOwnerCharID[hslot] <= 0) House_BuyConfirm(playerid, hslot);
            else House_Enter(playerid, hslot);
            return 1;
        }

        // 3. Dekat bisnis.
        new bslot = Business_Nearest(playerid);
        if (bslot != -1)
        {
            new charid = Society_PlayerData[playerid][sPCharID];
            if (bOwnerCharID[bslot] <= 0) Business_BuyConfirm(playerid, bslot);
            else if (bOwnerCharID[bslot] == charid) Business_ShowInfo(playerid);
            else Business_InfoPublic(playerid, bslot);
            return 1;
        }
    }
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
        Dialog_Show(playerid, Login, DIALOG_STYLE_PASSWORD, "Login",
            "Selamat datang kembali di Society Roleplay!\n\nAkun anda sudah terdaftar.\nMasukkan kata sandi:",
            "Masuk", "Keluar");
    }
    else
    {
        Dialog_Show(playerid, Register, DIALOG_STYLE_PASSWORD, "Registrasi Akun",
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
    SHA256_PassHash(Society_PlayerData[playerid][sPTempPass], name, myhash, sizeof(myhash));
    Society_PlayerData[playerid][sPTempPass][0] = EOS; // hapus kata sandi dari memori
    if (strcmp(myhash, dbhash, false) == 0)
    {
        cache_get_value_name_int(0, "id", tmp);
        Society_PlayerData[playerid][sPAccountID] = tmp;
        cache_get_value_name_int(0, "admin", tmp);
        Society_PlayerData[playerid][sPAdmin] = tmp;
        Society_PlayerData[playerid][sPLogged] = true;
        Society_PlayerData[playerid][sPLoginTries] = 0;
        SendClientMessage(playerid, COLOR_GREEN, "Login berhasil! Memuat daftar karakter...");
        LoadCharacterList(playerid);
    }
    else
    {
        Society_PlayerData[playerid][sPLoginTries]++;
        if (Society_PlayerData[playerid][sPLoginTries] >= 3)
        {
            SendClientMessage(playerid, COLOR_RED, "Kata sandi salah 3 kali. Anda dikeluarkan dari server.");
            Kick(playerid);
        }
        else
        {
            new msg[256];
            format(msg, sizeof(msg),
                "Kata sandi salah! Percobaan %d/3.\nMasukkan kata sandi akun anda:",
                Society_PlayerData[playerid][sPLoginTries]);
            Dialog_Show(playerid, Login, DIALOG_STYLE_PASSWORD, "Login", msg, "Masuk", "Keluar");
        }
    }
    return 1;
}

// OnAccountCreated: setelah INSERT akun berhasil.
public OnAccountCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    Society_PlayerData[playerid][sPAccountID] = cache_insert_id();
    Society_PlayerData[playerid][sPTempPass][0] = EOS; // hapus kata sandi dari memori
    Society_PlayerData[playerid][sPAdmin] = 0;
    Society_PlayerData[playerid][sPLogged] = true;
    Society_PlayerData[playerid][sPLoginTries] = 0;
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
    Society_PlayerData[playerid][sPCharCount] = rows;
    new list[256], item[40];
    list[0] = EOS;
    for (new i = 0; i < rows; i++)
    {
        cache_get_value_name_int(i, "id", tmp);
        pCharIDs[playerid][i] = tmp;
        cache_get_value_name(i, "name", sPCharList[playerid][i], MAX_CHAR_NAME);
        format(item, sizeof(item), "%s\n", sPCharList[playerid][i]);
        strcat(list, item, sizeof(list));
    }
    strcat(list, ">> Buat Karakter Baru <<", sizeof(list));
    Dialog_Show(playerid, CharList, DIALOG_STYLE_LIST,
        "Pilih Karakter", list, "Pilih", "Keluar");
    return 1;
}

// OnCharNameCheck: memastikan nama karakter belum dipakai.
public OnCharNameCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (cache_num_rows() > 0)
    {
        Dialog_Show(playerid, CreateName, DIALOG_STYLE_INPUT, "Buat Karakter - Nama",
            "Nama sudah dipakai pemain lain! Pilih nama lain.\nMasukkan nama karakter (format Nama_Belakang):",
            "Lanjut", "Kembali");
    }
    else
    {
        Dialog_Show(playerid, CreateAge, DIALOG_STYLE_INPUT, "Buat Karakter - Umur",
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
    cache_get_value_name_int(0, "id", tmp);      Society_PlayerData[playerid][sPCharID] = tmp;
    cache_get_value_name(0, "name", pCharName[playerid], sizeof(pCharName[]));
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
    cache_get_value_name_float(0, "hunger", ftmp); Society_PlayerData[playerid][sPHunger] = ftmp;
    cache_get_value_name_float(0, "thirst", ftmp); Society_PlayerData[playerid][sPThirst] = ftmp;
    cache_get_value_name_float(0, "stress", ftmp); Society_PlayerData[playerid][sPStress] = ftmp;
    cache_get_value_name_int(0, "faction_id", tmp); Society_PlayerData[playerid][sPFactionID] = tmp;
    cache_get_value_name_int(0, "faction_rank", tmp); Society_PlayerData[playerid][sPFactionRank] = tmp;
    cache_get_value_name_int(0, "family_id", tmp); Society_PlayerData[playerid][sPFamilyID] = tmp;
    cache_get_value_name_int(0, "family_rank", tmp); Society_PlayerData[playerid][sPFamilyRank] = tmp;
    Vehicle_OnCharLoad(playerid); // spawn ulang kendaraan milik karakter
    Family_ApplyColor(playerid); // warna nama sesuai keluarga (bila anggota)
    SpawnCharacter(playerid);
    return 1;
}

// AutoSave: menyimpan semua karakter yang sedang login (tiap 10 menit).
public AutoSave()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Society_PlayerData[i][sPLogged] && Society_PlayerData[i][sPCharID] > 0)
        {
            SaveCharacter(i);
        }
    }
    print("[SocietyRP] Autosave selesai.");
    return 1;
}
