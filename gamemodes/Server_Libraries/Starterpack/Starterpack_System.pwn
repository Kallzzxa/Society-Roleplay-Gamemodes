//================================================================
// Society Roleplay - Starterpack_System
// Paket warga baru: sekali klaim per karakter via /starterpack.
// Isi (referensi riset YouTube server SA-MP Indonesia):
//   - Uang tunai Rp5.000.000
//   - Roti x5, Air Mineral x5, Coconut Water x3 (masuk inventory)
//   - Kopi x2, Obat x2 (masuk inventory)
//   - Motor Sanchez gratis (kendaraan pribadi)
// Klaim tercatat di tabel starterpack_claims (satu kali per karakter).
// Di-include dari gamemodes/Society_Main.pwn (setelah Vehicle).
//================================================================

#if defined _starterpack_system_included
    #endinput
#endif
#define _starterpack_system_included

#define STARTER_CASH 5000000
#define STARTER_VEH_MODEL 468 // Sanchez

//==== FORWARD ====
forward OnStarterpackCheck(playerid);

//================================================================
// KLAIM
//================================================================

// Starterpack_TryClaim: /starterpack - cek ke database apakah sudah diklaim.
stock Starterpack_TryClaim(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 0;
    }
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
        return 0;
    }
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT char_id FROM starterpack_claims WHERE char_id = %d", charid);
    mysql_tquery(g_SQL, query, "OnStarterpackCheck", "d", playerid);
    return 1;
}

// OnStarterpackCheck: bila belum diklaim, tampilkan dialog isi paket.
public OnStarterpackCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 1;
    if (cache_num_rows() > 0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Kamu sudah mengambil starterpack untuk karakter ini.");
        return 1;
    }
    new cash[32], sub[512];
    FormatRupiah(STARTER_CASH, cash, sizeof(cash));
    format(sub, sizeof(sub),
        "Selamat datang, warga baru!~n~Isi paket starterpack:~n~- Uang tunai %s~n~- Roti x5, Air Mineral x5, Coconut Water x3~n~- Kopi x2, Obat x2~n~- Motor Sanchez gratis~n~Item masuk ke inventory (/inv).~n~Hanya bisa diklaim SATU KALI.",
        cash);
    new opts[2][64] = {"Ambil Paket", "Batal"};
    UI_ShowMenu(playerid, "dialog_StarterpackInfo", "STARTERPACK", sub, opts, 2);
    return 1;
}

// Starterpack_Give: memberikan seluruh isi paket ke pemain.
stock Starterpack_Give(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return 0;

    GivePlayerMoney(playerid, STARTER_CASH);
    Inventory_Give(playerid, INV_ROTI, 5);
    Inventory_Give(playerid, INV_AIR, 5);
    Inventory_Give(playerid, INV_COCONUT, 3);
    Inventory_Give(playerid, INV_KOPI, 2);
    Inventory_Give(playerid, INV_OBAT, 2);
    Inventory_Save(playerid);
    Vehicle_GiveFree(playerid, STARTER_VEH_MODEL);

    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO starterpack_claims (char_id) VALUES (%d)", charid);
    mysql_tquery(g_SQL, query);

    new cash[32], msg[256];
    FormatRupiah(STARTER_CASH, cash, sizeof(cash));
    format(msg, sizeof(msg),
        "[STARTERPACK] Kamu menerima %s + item inventory + motor Sanchez! Cek tasmu dengan /inv.",
        cash);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_YELLOW, "Tips: makan & minum dari inventory untuk menjaga kebutuhanmu.");
    UI_Notify(playerid, UI_NT_OK, "Starterpack diklaim!");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:StarterpackInfo - konfirmasi pengambilan paket (UI modern).
Dialog:StarterpackInfo(playerid, response, listitem, inputtext[])
{
    if (!response || listitem != 0) return 1; // "Ambil Paket" = opsi 0
    Starterpack_Give(playerid);
    return 1;
}
