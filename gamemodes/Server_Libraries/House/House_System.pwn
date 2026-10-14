//================================================================
// Society Roleplay - House_System
// Rumah dinamis: dibuat oleh admin (dua langkah), dibeli & dikelola
// oleh pemain. Setiap rumah punya pintu masuk (pickup + label 3D)
// dan pintu keluar di dalam interior (virtual world unik per rumah),
// tersimpan di tabel houses.
// Di-include dari gamemodes/Society_Main.pwn (setelah bagian UTIL,
// karena memakai pCharName dan stock util dari file utama).
//================================================================

#if defined _house_system_included
    #endinput
#endif
#define _house_system_included

//==== KONSTANTA ====
#define MAX_HOUSE 100
#define HOUSE_RANGE 4.0   // jarak interaksi pintu rumah
#define HOUSE_SELL_RATE 70 // persen harga kembali saat rumah dijual

// Nama tipe rumah: 0=Small, 1=Medium, 2=Large.
new House_TypeName[3][8] = {"Small", "Medium", "Large"};

//==== DATA RUMAH ====
new hExists[MAX_HOUSE];            // 1 jika slot terisi
new hDBID[MAX_HOUSE];              // id baris di tabel houses
new hOwnerCharID[MAX_HOUSE];       // id karakter pemilik (0 = belum ada pemilik)
new hOwnerName[MAX_HOUSE][24];     // nama karakter pemilik
new hPrice[MAX_HOUSE];             // harga beli
new hType[MAX_HOUSE];              // 0=Small, 1=Medium, 2=Large
new hLocation[MAX_HOUSE][64];      // nama lokasi/area rumah
new Float:hEntX[MAX_HOUSE];        // pintu masuk (koordinat)
new Float:hEntY[MAX_HOUSE];
new Float:hEntZ[MAX_HOUSE];
new hEntInt[MAX_HOUSE];            // interior pintu masuk
new hEntVW[MAX_HOUSE];             // virtual world pintu masuk
new Float:hExitX[MAX_HOUSE];       // pintu keluar (di dalam interior)
new Float:hExitY[MAX_HOUSE];
new Float:hExitZ[MAX_HOUSE];
new hExitInt[MAX_HOUSE];           // interior pintu keluar
new hLocked[MAX_HOUSE];            // 1 = terkunci
new hPickup[MAX_HOUSE];            // id pickup pintu masuk
new hExitPickup[MAX_HOUSE];        // id pickup pintu keluar
new Text3D:hLabel[MAX_HOUSE];      // label 3D pintu masuk
new bool:hLabelOn[MAX_HOUSE];      // true jika label sedang tampil

// Data sementara: pembuatan rumah dua langkah oleh admin & menu pemain.
new pHouseStep[MAX_PLAYERS];       // 0 = belum mulai, 1 = pintu masuk tercatat
new pHousePrice[MAX_PLAYERS];
new pHouseType[MAX_PLAYERS];       // 0=Small, 1=Medium, 2=Large
new pHouseLocation[MAX_PLAYERS][64];
new Float:pHouseEntX[MAX_PLAYERS];
new Float:pHouseEntY[MAX_PLAYERS];
new Float:pHouseEntZ[MAX_PLAYERS];
new pHouseEntInt[MAX_PLAYERS];
new pHouseEntVW[MAX_PLAYERS];
new pHouseMenuSlot[MAX_PLAYERS];

//==== FORWARD ====
forward OnHouseLoaded();
forward OnHouseCreated(playerid);

//================================================================
// UTIL RUMAH
//================================================================

// House_FreeSlot: mencari slot rumah kosong, -1 jika penuh.
stock House_FreeSlot()
{
    for (new i = 0; i < MAX_HOUSE; i++)
    {
        if (!hExists[i]) return i;
    }
    return -1;
}

// House_RefreshLabel: menggambar ulang label 3D sesuai status rumah.
stock House_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    if (hLabelOn[slot])
    {
        Delete3DTextLabel(hLabel[slot]);
        hLabelOn[slot] = false;
    }
    new text[320], harga[32];
    FormatRupiah(hPrice[slot], harga, sizeof(harga));
    if (hOwnerCharID[slot] <= 0)
    {
        // Format label: hijau ID & status, putih label, kuning nilai, cyan perintah.
        format(text, sizeof(text), "{33AA33}[ID:%d]\n{33AA33}This House For Sell\n{FFFFFF}Location:{FFFF00}%s\n{FFFFFF}Type:{FFFF00}%s\n{FFFFFF}Type {00CCFF}`/buyhouse`{FFFFFF} for buy this house",
            hDBID[slot], hLocation[slot], House_TypeName[hType[slot]]);
    }
    else
    {
        format(text, sizeof(text), "{33AA33}[ID:%d]\n{FFFFFF}Location:{FFFF00}%s\n{FFFFFF}Owned By:{FFFF00}%s\n{FFFFFF}Type:{FFFF00}%s\n{FFFFFF}Press {FF4444}`ENTER`{FFFFFF} To Enter a house",
            hDBID[slot], hLocation[slot], hOwnerName[slot], House_TypeName[hType[slot]]);
    }
    hLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        hEntX[slot], hEntY[slot], hEntZ[slot] + 1.2, 20.0, hEntVW[slot], 1);
    hLabelOn[slot] = true;
    return 1;
}

// House_Spawn: membuat pickup pintu masuk & keluar untuk satu rumah.
stock House_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    hPickup[slot] = CreatePickup(1273, 23, hEntX[slot], hEntY[slot], hEntZ[slot], hEntVW[slot]);
    hExitPickup[slot] = CreatePickup(1273, 23, hExitX[slot], hExitY[slot], hExitZ[slot], hDBID[slot]);
    House_RefreshLabel(slot);
    return 1;
}

// House_NearestEntrance: slot rumah terdekat dari pintu masuk (HOUSE_RANGE), -1 jika tidak ada.
stock House_NearestEntrance(playerid)
{
    new best = -1;
    new Float:bestdist = HOUSE_RANGE;
    for (new i = 0; i < MAX_HOUSE; i++)
    {
        if (!hExists[i]) continue;
        if (GetPlayerInterior(playerid) != hEntInt[i]) continue;
        if (GetPlayerVirtualWorld(playerid) != hEntVW[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, hEntX[i], hEntY[i], hEntZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// House_OwnedNear: slot rumah milik pemain dalam 10 meter dari pintu masuk, -1 jika tidak ada.
stock House_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return -1;
    new best = -1;
    new Float:bestdist = 10.0;
    for (new i = 0; i < MAX_HOUSE; i++)
    {
        if (!hExists[i] || hOwnerCharID[i] != charid) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, hEntX[i], hEntY[i], hEntZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// House_InsideHouse: slot rumah yang sedang dimasuki pemain (berdasar virtual world unik), -1 jika tidak.
stock House_InsideHouse(playerid)
{
    new vw = GetPlayerVirtualWorld(playerid);
    for (new i = 0; i < MAX_HOUSE; i++)
    {
        if (hExists[i] && hDBID[i] == vw) return i;
    }
    return -1;
}

// House_OnDisconnect: mereset data sementara pembuatan rumah saat pemain keluar.
stock House_OnDisconnect(playerid)
{
    pHouseStep[playerid] = 0;
    pHousePrice[playerid] = 0;
    pHouseType[playerid] = 0;
    pHouseLocation[playerid][0] = EOS;
    return 1;
}

//================================================================
// AKSI RUMAH
//================================================================

// House_CountOwned: jumlah rumah milik satu karakter (untuk /stats).
stock House_CountOwned(charid)
{
    new count = 0;
    for (new i = 0; i < MAX_HOUSE; i++)
    {
        if (hExists[i] && hOwnerCharID[i] == charid) count++;
    }
    return count;
}

// House_CreateStep1: admin mencatat pintu masuk + tipe + lokasi (langkah pertama /createhouse).
stock House_CreateStep1(playerid, price, type, location[])
{
    pHousePrice[playerid] = price;
    pHouseType[playerid] = type;
    format(pHouseLocation[playerid], sizeof(pHouseLocation[]), "%s", location);
    GetPlayerPos(playerid, pHouseEntX[playerid], pHouseEntY[playerid], pHouseEntZ[playerid]);
    pHouseEntInt[playerid] = GetPlayerInterior(playerid);
    pHouseEntVW[playerid] = GetPlayerVirtualWorld(playerid);
    pHouseStep[playerid] = 1;
    new msg[160];
    format(msg, sizeof(msg), "Pintu masuk tercatat. Tipe: %s | Lokasi: %s",
        House_TypeName[type], location);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_YELLOW, "Sekarang pergi ke titik PINTU KELUAR di dalam interior,");
    SendClientMessage(playerid, COLOR_YELLOW, "lalu ketik /createhouse (tanpa argumen) untuk menyelesaikan.");
    return 1;
}

// House_CreateStep2: admin mencatat pintu keluar & menyimpan rumah ke DB (langkah kedua /createhouse).
stock House_CreateStep2(playerid)
{
    if (pHouseStep[playerid] != 1) return 0;
    new slot = House_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot rumah penuh (maksimal 100).");
        pHouseStep[playerid] = 0;
        return 0;
    }
    new Float:xx, Float:xy, Float:xz;
    GetPlayerPos(playerid, xx, xy, xz);
    new xint = GetPlayerInterior(playerid);
    new query[512];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO houses (owner_char_id, price, type, location, ent_x, ent_y, ent_z, ent_int, ent_vw, exit_x, exit_y, exit_z, exit_int, locked) VALUES (0, %d, %d, '%e', %f, %f, %f, %d, %d, %f, %f, %f, %d, 0)",
        pHousePrice[playerid], pHouseType[playerid], pHouseLocation[playerid],
        pHouseEntX[playerid], pHouseEntY[playerid], pHouseEntZ[playerid],
        pHouseEntInt[playerid], pHouseEntVW[playerid],
        xx, xy, xz, xint);
    mysql_tquery(g_SQL, query, "OnHouseCreated", "d", playerid);
    return 1;
}

// House_Buy: /buyhouse - pemain membeli rumah yang belum ada pemiliknya.
stock House_Buy(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    if (hOwnerCharID[slot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Rumah ini sudah ada pemiliknya.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < hPrice[slot])
    {
        new kurang[32], msg[128];
        FormatRupiah(hPrice[slot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Harga rumah ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -hPrice[slot]);
    hOwnerCharID[slot] = Society_PlayerData[playerid][sPCharID];
    format(hOwnerName[slot], sizeof(hOwnerName[]), "%s", pCharName[playerid]);
    new query[160];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE houses SET owner_char_id = %d WHERE id = %d",
        hOwnerCharID[slot], hDBID[slot]);
    mysql_tquery(g_SQL, query);
    House_RefreshLabel(slot);
    new harga[32], msg[192];
    FormatRupiah(hPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg), "Selamat! Kamu membeli rumah #%d seharga %s.", hDBID[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Tekan ENTER (F) di depan rumahmu untuk masuk.");
    return 1;
}

// House_Sell: /sellhouse - pemilik menjual kembali rumahnya (70% dari harga beli).
stock House_Sell(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    new kembali = (hPrice[slot] * HOUSE_SELL_RATE) / 100;
    GivePlayerMoney(playerid, kembali);
    hOwnerCharID[slot] = 0;
    hOwnerName[slot][0] = EOS;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE houses SET owner_char_id = 0 WHERE id = %d", hDBID[slot]);
    mysql_tquery(g_SQL, query);
    House_RefreshLabel(slot);
    new rp[32], msg[192];
    FormatRupiah(kembali, rp, sizeof(rp));
    format(msg, sizeof(msg), "Rumah #%d terjual kembali. Kamu menerima %s.", hDBID[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// House_ToggleLock: mengunci/membuka rumah (status tampil di label 3D).
stock House_ToggleLock(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    hLocked[slot] = !hLocked[slot];
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE houses SET locked = %d WHERE id = %d", hLocked[slot], hDBID[slot]);
    mysql_tquery(g_SQL, query);
    House_RefreshLabel(slot);
    if (hLocked[slot])
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Rumah dikunci.");
    }
    else
    {
        SendClientMessage(playerid, COLOR_GREEN, "Rumah dibuka.");
    }
    return 1;
}

// House_Enter: /enterhouse - masuk ke dalam rumah (kecuali terkunci & bukan pemilik).
stock House_Enter(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    if (hLocked[slot] && hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Rumah ini terkunci.");
        return 0;
    }
    SetPlayerInterior(playerid, hExitInt[slot]);
    SetPlayerVirtualWorld(playerid, hDBID[slot]);
    SetPlayerPos(playerid, hExitX[slot], hExitY[slot], hExitZ[slot]);
    new msg[96];
    format(msg, sizeof(msg), "Kamu memasuki rumah #%d. Tekan ENTER (F) untuk keluar.", hDBID[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// House_Exit: /exithouse - keluar dari dalam rumah ke pintu masuk.
stock House_Exit(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    SetPlayerInterior(playerid, hEntInt[slot]);
    SetPlayerVirtualWorld(playerid, hEntVW[slot]);
    SetPlayerPos(playerid, hEntX[slot], hEntY[slot], hEntZ[slot]);
    SendClientMessage(playerid, COLOR_GREEN, "Kamu keluar dari rumah.");
    return 1;
}

// House_BuyConfirm: dialog konfirmasi beli rumah (dari tombol ENTER di depan rumah dijual).
stock House_BuyConfirm(playerid, slot)
{
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 0;
    if (hOwnerCharID[slot] > 0) return 0;
    pHouseMenuSlot[playerid] = slot;
    new harga[32], msg[320];
    FormatRupiah(hPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Yakin ingin membeli rumah ini?\n\nLocation: %s\nType: %s\nHarga: %s",
        hLocation[slot], House_TypeName[hType[slot]], harga);
    Dialog_Show(playerid, HouseBuyConfirm, DIALOG_STYLE_MSGBOX, "Beli Rumah", msg, "Beli", "Batal");
    return 1;
}

// Dialog:HouseBuyConfirm - konfirmasi pembelian rumah via tombol ENTER.
Dialog:HouseBuyConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pHouseMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 1;
    House_Buy(playerid, slot);
    return 1;
}

// House_ShowInfo: /houseinfo - menu kelola rumah milik pemain (textdraw modern).
stock House_ShowInfo(playerid)
{
    new slot = House_OwnedNear(playerid);
    if (slot == -1) slot = House_InsideHouse(playerid);
    if (slot == -1 || hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada rumahmu di dekat sini.");
        return 0;
    }
    pHouseMenuSlot[playerid] = slot;
    new harga[32], kunci[16], title[32], sub[160];
    FormatRupiah(hPrice[slot], harga, sizeof(harga));
    if (hLocked[slot]) format(kunci, sizeof(kunci), "Buka Rumah");
    else format(kunci, sizeof(kunci), "Kunci Rumah");
    format(title, sizeof(title), "RUMAH #%d", hDBID[slot]);
    format(sub, sizeof(sub), "Harga beli: %s~n~Pilih aksi kelola untuk rumahmu:", harga);
    new opts[2][64];
    format(opts[0], 64, "%s", kunci);
    format(opts[1], 64, "Jual Rumah (70%%)");
    UI_ShowMenu(playerid, "dialog_HouseInfo", title, sub, opts, 2);
    return 1;
}

// House_LoadAll: memuat semua rumah dari database saat gamemode mulai.
stock House_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT h.id, h.owner_char_id, IFNULL(c.name, '') AS owner_name, h.price, h.type, h.location, h.ent_x, h.ent_y, h.ent_z, h.ent_int, h.ent_vw, h.exit_x, h.exit_y, h.exit_z, h.exit_int, h.locked FROM houses h LEFT JOIN characters c ON c.id = h.owner_char_id",
        "OnHouseLoaded");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:HouseInfo - menu kelola rumah: kunci/buka, jual.
Dialog:HouseInfo(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pHouseMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 1;
    if (hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan rumahmu.");
        return 1;
    }
    if (listitem == 0)
    {
        House_ToggleLock(playerid, slot);
    }
    else if (listitem == 1)
    {
        new harga[32], msg[256];
        FormatRupiah((hPrice[slot] * HOUSE_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual rumah #%d?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            hDBID[slot], harga, HOUSE_SELL_RATE);
        Dialog_Show(playerid, HouseSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Rumah", msg, "Jual", "Batal");
    }
    return 1;
}

// Dialog:HouseSellConfirm - konfirmasi sebelum rumah dijual kembali.
Dialog:HouseSellConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pHouseMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_HOUSE || !hExists[slot]) return 1;
    if (hOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan rumahmu.");
        return 1;
    }
    House_Sell(playerid, slot);
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnHouseLoaded: mengisi slot rumah dari database lalu spawn pickup+label.
public OnHouseLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_HOUSE; i++)
    {
        cache_get_value_name_int(i, "id", tmp);           hDBID[i] = tmp;
        cache_get_value_name_int(i, "owner_char_id", tmp); hOwnerCharID[i] = tmp;
        cache_get_value_name(i, "owner_name", hOwnerName[i], sizeof(hOwnerName[]));
        cache_get_value_name_int(i, "price", tmp);        hPrice[i] = tmp;
        cache_get_value_name_int(i, "type", tmp);         hType[i] = tmp;
        cache_get_value_name(i, "location", hLocation[i], sizeof(hLocation[]));
        cache_get_value_name_float(i, "ent_x", ftmp);     hEntX[i] = ftmp;
        cache_get_value_name_float(i, "ent_y", ftmp);     hEntY[i] = ftmp;
        cache_get_value_name_float(i, "ent_z", ftmp);     hEntZ[i] = ftmp;
        cache_get_value_name_int(i, "ent_int", tmp);      hEntInt[i] = tmp;
        cache_get_value_name_int(i, "ent_vw", tmp);       hEntVW[i] = tmp;
        cache_get_value_name_float(i, "exit_x", ftmp);    hExitX[i] = ftmp;
        cache_get_value_name_float(i, "exit_y", ftmp);    hExitY[i] = ftmp;
        cache_get_value_name_float(i, "exit_z", ftmp);    hExitZ[i] = ftmp;
        cache_get_value_name_int(i, "exit_int", tmp);     hExitInt[i] = tmp;
        cache_get_value_name_int(i, "locked", tmp);      hLocked[i] = tmp;
        hExists[i] = 1;
        hLabelOn[i] = false;
        House_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d rumah dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnHouseCreated: setelah INSERT rumah berhasil, isi slot lalu spawn pickup+label.
public OnHouseCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = House_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot rumah penuh (maksimal 100).");
        pHouseStep[playerid] = 0;
        return 1;
    }
    hExists[slot] = 1;
    hDBID[slot] = cache_insert_id();
    hOwnerCharID[slot] = 0;
    hOwnerName[slot][0] = EOS;
    hPrice[slot] = pHousePrice[playerid];
    hType[slot] = pHouseType[playerid];
    format(hLocation[slot], sizeof(hLocation[]), "%s", pHouseLocation[playerid]);
    hEntX[slot] = pHouseEntX[playerid];
    hEntY[slot] = pHouseEntY[playerid];
    hEntZ[slot] = pHouseEntZ[playerid];
    hEntInt[slot] = pHouseEntInt[playerid];
    hEntVW[slot] = pHouseEntVW[playerid];
    GetPlayerPos(playerid, hExitX[slot], hExitY[slot], hExitZ[slot]);
    hExitInt[slot] = GetPlayerInterior(playerid);
    hLocked[slot] = 0;
    hLabelOn[slot] = false;
    pHouseStep[playerid] = 0;
    House_Spawn(slot);
    new msg[128];
    format(msg, sizeof(msg), "Rumah #%d berhasil dibuat dan siap dijual.", hDBID[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}
