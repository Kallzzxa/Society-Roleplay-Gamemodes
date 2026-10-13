//================================================================
// Society Roleplay - Business_System
// Bisnis dinamis: dibuat oleh admin, dibeli & dikelola oleh pemain.
// Setiap bisnis punya pickup + label 3D, profit bertambah tiap
// payday (1 jam) bila ada pemilik, tersimpan di tabel businesses.
// Di-include dari gamemodes/Society_Main.pwn (setelah bagian UTIL,
// karena memakai pCharName dan stock util dari file utama).
//================================================================

#if defined _business_system_included
    #endinput
#endif
#define _business_system_included

//==== KONSTANTA ====
#define MAX_BUSINESS 100
#define BUSINESS_TYPES 6
#define BUSINESS_RANGE 4.0   // jarak interaksi pickup bisnis
#define BUSINESS_SELL_RATE 70 // persen harga kembali saat bisnis dijual

// Daftar tipe bisnis + profit per payday (tiap 1 jam).
new Business_TypeName[BUSINESS_TYPES][24] =
{
    "Warung Makan",
    "Toko Kelontong",
    "Restoran",
    "Bar",
    "Toko Pakaian",
    "Hotel"
};
new Business_TypeProfit[BUSINESS_TYPES] =
{
    100000,
    200000,
    350000,
    300000,
    250000,
    500000
};

//==== DATA BISNIS ====
new bExists[MAX_BUSINESS];          // 1 jika slot terisi
new bDBID[MAX_BUSINESS];            // id baris di tabel businesses
new bName[MAX_BUSINESS][32];        // nama bisnis
new bOwnerCharID[MAX_BUSINESS];     // id karakter pemilik (0 = belum ada pemilik)
new bOwnerName[MAX_BUSINESS][24];   // nama karakter pemilik
new bType[MAX_BUSINESS];            // indeks tipe bisnis (0-5)
new bPrice[MAX_BUSINESS];           // harga beli
new bProfit[MAX_BUSINESS];          // keuntungan terkumpul (belum diambil)
new Float:bPosX[MAX_BUSINESS];
new Float:bPosY[MAX_BUSINESS];
new Float:bPosZ[MAX_BUSINESS];
new bLocked[MAX_BUSINESS];          // 1 = terkunci
new bPickup[MAX_BUSINESS];          // id pickup
new Text3D:bLabel[MAX_BUSINESS];    // label 3D
new bool:bLabelOn[MAX_BUSINESS];    // true jika label sedang tampil

// Data sementara: pembuatan bisnis oleh admin & menu /bizinfo pemain.
new pBizName[MAX_PLAYERS][32];
new pBizType[MAX_PLAYERS];
new pBizPrice[MAX_PLAYERS];
new pBizSlot[MAX_PLAYERS];
new pBizMenuSlot[MAX_PLAYERS];

//==== FORWARD ====
forward OnBusinessLoaded();
forward OnBusinessCreated(playerid);
forward BusinessPayday();

//================================================================
// UTIL BISNIS
//================================================================

// Business_FreeSlot: mencari slot bisnis kosong, -1 jika penuh.
stock Business_FreeSlot()
{
    for (new i = 0; i < MAX_BUSINESS; i++)
    {
        if (!bExists[i]) return i;
    }
    return -1;
}

// Business_RefreshLabel: menggambar ulang label 3D sesuai status bisnis.
stock Business_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    if (bLabelOn[slot])
    {
        Delete3DTextLabel(bLabel[slot]);
        bLabelOn[slot] = false;
    }
    new text[256], harga[32], status[64], kunci[32];
    FormatRupiah(bPrice[slot], harga, sizeof(harga));
    if (bOwnerCharID[slot] <= 0)
    {
        format(status, sizeof(status), "Status: {33AA33}Dijual{FFFFFF}");
    }
    else
    {
        format(status, sizeof(status), "Status: Pemilik {FFCC00}%s{FFFFFF}", bOwnerName[slot]);
    }
    if (bLocked[slot])
    {
        format(kunci, sizeof(kunci), "{FF4444}[Terkunci]{FFFFFF}");
    }
    else
    {
        format(kunci, sizeof(kunci), "{33AA33}[Terbuka]{FFFFFF}");
    }
    format(text, sizeof(text), "{FFFF00}[BISNIS]{FFFFFF}\n%s\n%s | %s\n%s\n%s",
        bName[slot], Business_TypeName[bType[slot]], harga, status, kunci);
    bLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        bPosX[slot], bPosY[slot], bPosZ[slot] + 1.2, 20.0, 0, 1);
    bLabelOn[slot] = true;
    return 1;
}

// Business_Spawn: membuat pickup + label 3D untuk satu bisnis.
stock Business_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    bPickup[slot] = CreatePickup(1274, 23, bPosX[slot], bPosY[slot], bPosZ[slot], 0);
    Business_RefreshLabel(slot);
    return 1;
}

// Business_Nearest: slot bisnis terdekat dalam BUSINESS_RANGE, -1 jika tidak ada.
stock Business_Nearest(playerid)
{
    new best = -1;
    new Float:bestdist = BUSINESS_RANGE;
    for (new i = 0; i < MAX_BUSINESS; i++)
    {
        if (!bExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, bPosX[i], bPosY[i], bPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Business_OwnedNear: slot bisnis milik pemain dalam 10 meter, -1 jika tidak ada.
stock Business_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return -1;
    new best = -1;
    new Float:bestdist = 10.0;
    for (new i = 0; i < MAX_BUSINESS; i++)
    {
        if (!bExists[i] || bOwnerCharID[i] != charid) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, bPosX[i], bPosY[i], bPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

//================================================================
// AKSI BISNIS
//================================================================

// Business_Create: admin membuat bisnis baru di posisinya (simpan ke DB).
stock Business_Create(playerid, const name[], type, price)
{
    new slot = Business_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot bisnis penuh (maksimal 100).");
        return 0;
    }
    format(pBizName[playerid], sizeof(pBizName[]), "%s", name);
    pBizType[playerid] = type;
    pBizPrice[playerid] = price;
    pBizSlot[playerid] = slot;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO businesses (name, owner_char_id, type, price, profit, pos_x, pos_y, pos_z, locked) VALUES ('%e', 0, %d, %d, 0, %f, %f, %f, 0)",
        name, type, price, x, y, z);
    mysql_tquery(g_SQL, query, "OnBusinessCreated", "d", playerid);
    return 1;
}

// Business_Buy: /buybusiness - pemain membeli bisnis yang belum ada pemiliknya.
stock Business_Buy(playerid, slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    if (bOwnerCharID[slot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Bisnis ini sudah ada pemiliknya.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < bPrice[slot])
    {
        new kurang[32], msg[128];
        FormatRupiah(bPrice[slot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Harga bisnis ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -bPrice[slot]);
    bOwnerCharID[slot] = Society_PlayerData[playerid][sPCharID];
    format(bOwnerName[slot], sizeof(bOwnerName[]), "%s", pCharName[playerid]);
    new query[160];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE businesses SET owner_char_id = %d WHERE id = %d",
        bOwnerCharID[slot], bDBID[slot]);
    mysql_tquery(g_SQL, query);
    Business_RefreshLabel(slot);
    new harga[32], msg[192];
    FormatRupiah(bPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg), "Selamat! Kamu membeli bisnis \"%s\" seharga %s.", bName[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Ketik /bizinfo di dekat bisnismu untuk mengelolanya.");
    return 1;
}

// Business_Collect: /bizwithdraw - pemilik mengambil keuntungan yang terkumpul.
stock Business_Collect(playerid, slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    if (bProfit[slot] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada keuntungan yang bisa diambil.");
        return 0;
    }
    new rp[32], msg[192];
    FormatRupiah(bProfit[slot], rp, sizeof(rp));
    GivePlayerMoney(playerid, bProfit[slot]);
    format(msg, sizeof(msg), "Kamu mengambil keuntungan bisnis \"%s\": %s.", bName[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    bProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE businesses SET profit = 0 WHERE id = %d", bDBID[slot]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Business_Sell: /sellbusiness - pemilik menjual kembali (70% dari harga beli).
stock Business_Sell(playerid, slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    new kembali = (bPrice[slot] * BUSINESS_SELL_RATE) / 100;
    GivePlayerMoney(playerid, kembali);
    bOwnerCharID[slot] = 0;
    bOwnerName[slot][0] = EOS;
    bProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE businesses SET owner_char_id = 0, profit = 0 WHERE id = %d", bDBID[slot]);
    mysql_tquery(g_SQL, query);
    Business_RefreshLabel(slot);
    new rp[32], msg[192];
    FormatRupiah(kembali, rp, sizeof(rp));
    format(msg, sizeof(msg), "Bisnis \"%s\" terjual kembali. Kamu menerima %s.", bName[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Business_ToggleLock: mengunci/membuka bisnis (status tampil di label 3D).
stock Business_ToggleLock(playerid, slot)
{
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 0;
    bLocked[slot] = !bLocked[slot];
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE businesses SET locked = %d WHERE id = %d", bLocked[slot], bDBID[slot]);
    mysql_tquery(g_SQL, query);
    Business_RefreshLabel(slot);
    if (bLocked[slot])
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Bisnis dikunci.");
    }
    else
    {
        SendClientMessage(playerid, COLOR_GREEN, "Bisnis dibuka.");
    }
    return 1;
}

// Business_ShowInfo: /bizinfo - dialog kelola bisnis milik pemain.
stock Business_ShowInfo(playerid)
{
    new slot = Business_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada bisnismu di dekat sini.");
        return 0;
    }
    pBizMenuSlot[playerid] = slot;
    new profit[32], kunci[16], list[256], title[64];
    FormatRupiah(bProfit[slot], profit, sizeof(profit));
    if (bLocked[slot]) format(kunci, sizeof(kunci), "Buka Bisnis");
    else format(kunci, sizeof(kunci), "Kunci Bisnis");
    format(list, sizeof(list), "Ambil Keuntungan (%s)\n%s\nJual Bisnis", profit, kunci);
    format(title, sizeof(title), "Bisnis: %s", bName[slot]);
    Dialog_Show(playerid, BizInfo, DIALOG_STYLE_LIST, title, list, "Pilih", "Tutup");
    return 1;
}

// Business_LoadAll: memuat semua bisnis dari database saat gamemode mulai.
stock Business_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT b.id, b.name, b.owner_char_id, IFNULL(c.name, '') AS owner_name, b.type, b.price, b.profit, b.pos_x, b.pos_y, b.pos_z, b.locked FROM businesses b LEFT JOIN characters c ON c.id = b.owner_char_id",
        "OnBusinessLoaded");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:BizInfo - menu kelola bisnis: ambil untung, kunci/buka, jual.
Dialog:BizInfo(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pBizMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 1;
    if (bOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan bisnismu.");
        return 1;
    }
    if (listitem == 0)
    {
        Business_Collect(playerid, slot);
    }
    else if (listitem == 1)
    {
        Business_ToggleLock(playerid, slot);
    }
    else if (listitem == 2)
    {
        new harga[32], msg[256];
        FormatRupiah((bPrice[slot] * BUSINESS_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual bisnis \"%s\"?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            bName[slot], harga, BUSINESS_SELL_RATE);
        Dialog_Show(playerid, BizSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Bisnis", msg, "Jual", "Batal");
    }
    return 1;
}

// Dialog:BizSellConfirm - konfirmasi sebelum bisnis dijual kembali.
Dialog:BizSellConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pBizMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_BUSINESS || !bExists[slot]) return 1;
    if (bOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan bisnismu.");
        return 1;
    }
    Business_Sell(playerid, slot);
    return 1;
}

//================================================================
// CALLBACK MYSQL & TIMER
//================================================================

// OnBusinessLoaded: mengisi slot bisnis dari database lalu spawn pickup+label.
public OnBusinessLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_BUSINESS; i++)
    {
        cache_get_value_name_int(i, "id", tmp);           bDBID[i] = tmp;
        cache_get_value_name(i, "name", bName[i], sizeof(bName[]));
        cache_get_value_name_int(i, "owner_char_id", tmp); bOwnerCharID[i] = tmp;
        cache_get_value_name(i, "owner_name", bOwnerName[i], sizeof(bOwnerName[]));
        cache_get_value_name_int(i, "type", tmp);         bType[i] = tmp;
        cache_get_value_name_int(i, "price", tmp);        bPrice[i] = tmp;
        cache_get_value_name_int(i, "profit", tmp);       bProfit[i] = tmp;
        cache_get_value_name_float(i, "pos_x", ftmp);     bPosX[i] = ftmp;
        cache_get_value_name_float(i, "pos_y", ftmp);     bPosY[i] = ftmp;
        cache_get_value_name_float(i, "pos_z", ftmp);     bPosZ[i] = ftmp;
        cache_get_value_name_int(i, "locked", tmp);       bLocked[i] = tmp;
        if (bType[i] < 0 || bType[i] >= BUSINESS_TYPES) bType[i] = 0;
        bExists[i] = 1;
        bLabelOn[i] = false;
        Business_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d bisnis dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnBusinessCreated: setelah INSERT bisnis berhasil, spawn pickup+label.
public OnBusinessCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pBizSlot[playerid];
    if (slot < 0 || slot >= MAX_BUSINESS) return 1;
    bExists[slot] = 1;
    bDBID[slot] = cache_insert_id();
    format(bName[slot], sizeof(bName[]), "%s", pBizName[playerid]);
    bOwnerCharID[slot] = 0;
    bOwnerName[slot][0] = EOS;
    bType[slot] = pBizType[playerid];
    bPrice[slot] = pBizPrice[playerid];
    bProfit[slot] = 0;
    GetPlayerPos(playerid, bPosX[slot], bPosY[slot], bPosZ[slot]);
    bLocked[slot] = 0;
    bLabelOn[slot] = false;
    Business_Spawn(slot);
    new msg[128];
    format(msg, sizeof(msg), "Bisnis \"%s\" berhasil dibuat (ID database %d).", bName[slot], bDBID[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// BusinessPayday: tiap 1 jam, bisnis yang ada pemiliknya menghasilkan profit.
public BusinessPayday()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 1;
    new query[128];
    for (new i = 0; i < MAX_BUSINESS; i++)
    {
        if (!bExists[i] || bOwnerCharID[i] <= 0) continue;
        bProfit[i] += Business_TypeProfit[bType[i]];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE businesses SET profit = %d WHERE id = %d", bProfit[i], bDBID[i]);
        mysql_tquery(g_SQL, query);
        // Beri tahu pemilik yang sedang online.
        for (new p = 0; p < MAX_PLAYERS; p++)
        {
            if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
                && Society_PlayerData[p][sPCharID] == bOwnerCharID[i])
            {
                new rp[32], msg[192];
                FormatRupiah(Business_TypeProfit[bType[i]], rp, sizeof(rp));
                format(msg, sizeof(msg),
                    "[BISNIS] \"%s\" menghasilkan keuntungan %s. Ambil dengan /bizwithdraw.",
                    bName[i], rp);
                SendClientMessage(p, COLOR_YELLOW, msg);
            }
        }
    }
    print("[SocietyRP] Payday bisnis selesai.");
    return 1;
}
