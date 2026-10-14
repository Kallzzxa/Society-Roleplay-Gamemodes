//================================================================
// Society Roleplay - Inventory_System
// Tas pemain: menyimpan item (makanan, minuman, obat) yang bisa
// dipakai lewat UI textdraw. Item terhubung ke sistem kebutuhan
// (Needs): roti/minuman mengisi makan/minum, kopi menurunkan
// stress, obat menambah darah.
// UI: /inv -> panel PlayerTextDraw dengan slot yang bisa diklik
// (SelectTextDraw). Data tersimpan di tabel inventory.
// Di-include dari gamemodes/Society_Main.pwn (setelah Needs).
//================================================================

#if defined _inventory_system_included
    #endinput
#endif
#define _inventory_system_included

//==== ITEM ====
#define MAX_INV_ITEMS 5
#define INV_ROTI    0  // +35 makan
#define INV_AIR     1  // +35 minum
#define INV_COCONUT 2  // +50 minum, -15 stress
#define INV_KOPI    3  // -30 stress
#define INV_OBAT    4  // +40 darah

new InvItemName[MAX_INV_ITEMS][16] =
{
    "Roti", "Air Mineral", "Coconut Water", "Kopi", "Obat"
};
new InvItemDesc[MAX_INV_ITEMS][64] =
{
    "Mengisi makan +35",
    "Menghilangkan haus +35",
    "Haus +50, stress -15",
    "Stress -30",
    "Darah +40"
};

//==== DATA ====
new invAmount[MAX_PLAYERS][MAX_INV_ITEMS]; // jumlah tiap item di tas

//==== TEXTDRAW UI ====
new PlayerText:invBG[MAX_PLAYERS];
new PlayerText:invTitle[MAX_PLAYERS];
new PlayerText:invSlotBox[MAX_PLAYERS][MAX_INV_ITEMS];
new PlayerText:invSlotName[MAX_PLAYERS][MAX_INV_ITEMS];
new PlayerText:invSlotAmt[MAX_PLAYERS][MAX_INV_ITEMS];
new PlayerText:invClose[MAX_PLAYERS];
new bool:invTDCreated[MAX_PLAYERS];
new bool:invOpen[MAX_PLAYERS];
new invSelItem[MAX_PLAYERS]; // item yang dipilih untuk dialog aksi

//==== FORWARD ====
forward OnInventoryLoaded(playerid);

//================================================================
// DATA
//================================================================

// Inventory_Give: menambah item ke tas (tanpa simpan otomatis).
stock Inventory_Give(playerid, itemid, amount)
{
    if (itemid < 0 || itemid >= MAX_INV_ITEMS || amount <= 0) return 0;
    invAmount[playerid][itemid] += amount;
    if (invAmount[playerid][itemid] > 999) invAmount[playerid][itemid] = 999;
    return 1;
}

// Inventory_Take: mengurangi item, 0 jika tidak cukup.
stock Inventory_Take(playerid, itemid, amount)
{
    if (itemid < 0 || itemid >= MAX_INV_ITEMS || amount <= 0) return 0;
    if (invAmount[playerid][itemid] < amount) return 0;
    invAmount[playerid][itemid] -= amount;
    return 1;
}

// Inventory_Count: jumlah satu item di tas.
stock Inventory_Count(playerid, itemid)
{
    if (itemid < 0 || itemid >= MAX_INV_ITEMS) return 0;
    return invAmount[playerid][itemid];
}

// Inventory_Save: menulis seluruh isi tas ke database.
stock Inventory_Save(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new query[512], vals[384];
    vals[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        if (invAmount[playerid][i] <= 0) continue;
        new part[48];
        format(part, sizeof(part), "%s(%d, %d, %d)",
            (count > 0) ? "," : "", charid, i, invAmount[playerid][i]);
        strcat(vals, part, sizeof(vals));
        count++;
    }
    if (count == 0)
    {
        mysql_format(g_SQL, query, sizeof(query),
            "DELETE FROM inventory WHERE char_id = %d", charid);
    }
    else
    {
        mysql_format(g_SQL, query, sizeof(query),
            "INSERT INTO inventory (char_id, item_id, amount) VALUES %s ON DUPLICATE KEY UPDATE amount = VALUES(amount)",
            vals);
    }
    mysql_tquery(g_SQL, query);
    // Hapus baris yang jumlahnya nol (tidak dikirim di INSERT).
    mysql_format(g_SQL, query, sizeof(query),
        "DELETE FROM inventory WHERE char_id = %d AND amount <= 0", charid);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Inventory_OnCharLoad: memuat isi tas saat karakter dipilih.
stock Inventory_OnCharLoad(playerid)
{
    for (new i = 0; i < MAX_INV_ITEMS; i++) invAmount[playerid][i] = 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT item_id, amount FROM inventory WHERE char_id = %d", charid);
    mysql_tquery(g_SQL, query, "OnInventoryLoaded", "d", playerid);
    return 1;
}

// OnInventoryLoaded: mengisi array tas dari database.
public OnInventoryLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new rows = cache_num_rows(), itemid, amount;
    for (new i = 0; i < rows; i++)
    {
        cache_get_value_name_int(i, "item_id", itemid);
        cache_get_value_name_int(i, "amount", amount);
        if (itemid >= 0 && itemid < MAX_INV_ITEMS && amount > 0)
        {
            invAmount[playerid][itemid] = amount;
        }
    }
    return 1;
}

// Inventory_OnDisconnect: simpan tas & hapus textdraw.
stock Inventory_OnDisconnect(playerid)
{
    if (Society_PlayerData[playerid][sPCharID] > 0) Inventory_Save(playerid);
    Inventory_Hide(playerid);
    Inventory_DestroyTDs(playerid);
    for (new i = 0; i < MAX_INV_ITEMS; i++) invAmount[playerid][i] = 0;
    invSelItem[playerid] = 0;
    return 1;
}

//================================================================
// EFEK ITEM (terhubung ke Needs)
//================================================================

// Inventory_EatCooldown: cooldown 5 detik yang sama dengan /eat & /drink.
stock Inventory_EatCooldown(playerid)
{
    new now = GetTickCount();
    if (now - Society_PlayerData[playerid][sPNeedsCD] < 5000)
    {
        SendClientMessage(playerid, COLOR_GREY, "Tunggu sebentar sebelum memakai item lagi.");
        return 0;
    }
    Society_PlayerData[playerid][sPNeedsCD] = now;
    return 1;
}

// Inventory_UseItem: memakai satu item dari tas.
stock Inventory_UseItem(playerid, itemid)
{
    if (itemid < 0 || itemid >= MAX_INV_ITEMS) return 0;
    if (invAmount[playerid][itemid] <= 0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Kamu tidak punya item itu.");
        return 0;
    }
    new msg[128];
    switch (itemid)
    {
        case INV_ROTI:
        {
            if (Society_PlayerData[playerid][sPHunger] >= 100.0)
            {
                SendClientMessage(playerid, COLOR_GREY, "Kamu sudah kenyang.");
                return 0;
            }
            if (!Inventory_EatCooldown(playerid)) return 0;
            Society_PlayerData[playerid][sPHunger] += 35.0;
            if (Society_PlayerData[playerid][sPHunger] > 100.0) Society_PlayerData[playerid][sPHunger] = 100.0;
            Society_PlayerData[playerid][sPStress] -= 10.0;
            if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
            format(msg, sizeof(msg), "Kamu memakan roti. Kenyang +35.");
        }
        case INV_AIR:
        {
            if (Society_PlayerData[playerid][sPThirst] >= 100.0)
            {
                SendClientMessage(playerid, COLOR_GREY, "Kamu tidak haus.");
                return 0;
            }
            if (!Inventory_EatCooldown(playerid)) return 0;
            Society_PlayerData[playerid][sPThirst] += 35.0;
            if (Society_PlayerData[playerid][sPThirst] > 100.0) Society_PlayerData[playerid][sPThirst] = 100.0;
            Society_PlayerData[playerid][sPStress] -= 10.0;
            if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
            format(msg, sizeof(msg), "Kamu meminum air mineral. Haus hilang +35.");
        }
        case INV_COCONUT:
        {
            if (Society_PlayerData[playerid][sPThirst] >= 100.0)
            {
                SendClientMessage(playerid, COLOR_GREY, "Kamu tidak haus.");
                return 0;
            }
            if (!Inventory_EatCooldown(playerid)) return 0;
            Society_PlayerData[playerid][sPThirst] += 50.0;
            if (Society_PlayerData[playerid][sPThirst] > 100.0) Society_PlayerData[playerid][sPThirst] = 100.0;
            Society_PlayerData[playerid][sPStress] -= 15.0;
            if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
            format(msg, sizeof(msg), "Segarnya coconut water! Haus +50, stress berkurang.");
        }
        case INV_KOPI:
        {
            if (Society_PlayerData[playerid][sPStress] <= 0.0)
            {
                SendClientMessage(playerid, COLOR_GREY, "Kamu sudah santai, tidak butuh kopi.");
                return 0;
            }
            Society_PlayerData[playerid][sPStress] -= 30.0;
            if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
            format(msg, sizeof(msg), "Kamu menyeruput kopi. Stress -30.");
        }
        case INV_OBAT:
        {
            new Float:hp;
            GetPlayerHealth(playerid, hp);
            if (hp >= 100.0)
            {
                SendClientMessage(playerid, COLOR_GREY, "Darahmu sudah penuh.");
                return 0;
            }
            if (!Inventory_EatCooldown(playerid)) return 0;
            hp += 40.0;
            if (hp > 100.0) hp = 100.0;
            SetPlayerHealth(playerid, hp);
            format(msg, sizeof(msg), "Kamu memakai obat. Darah +40.");
        }
        default: return 0;
    }
    invAmount[playerid][itemid]--;
    Inventory_Save(playerid);
    Needs_UpdateTextDraws(playerid);
    Inventory_Refresh(playerid);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// UI TEXTDRAW
//================================================================

// Inventory_CreateTDs: membuat panel inventory (sekali per sesi).
stock Inventory_CreateTDs(playerid)
{
    if (invTDCreated[playerid]) return 1;
    // Latar panel.
    invBG[playerid] = CreatePlayerTextDraw(playerid, 75.0, 145.0, "_");
    PlayerTextDrawTextSize(playerid, invBG[playerid], 565.0, 320.0);
    PlayerTextDrawUseBox(playerid, invBG[playerid], 1);
    PlayerTextDrawBoxColor(playerid, invBG[playerid], 0x000000CC);
    // Judul.
    invTitle[playerid] = CreatePlayerTextDraw(playerid, 320.0, 150.0, "INVENTORY");
    PlayerTextDrawAlignment(playerid, invTitle[playerid], 2);
    PlayerTextDrawFont(playerid, invTitle[playerid], 2);
    PlayerTextDrawLetterSize(playerid, invTitle[playerid], 0.35, 1.4);
    PlayerTextDrawColor(playerid, invTitle[playerid], 0xFFFF00FF);
    PlayerTextDrawSetOutline(playerid, invTitle[playerid], 1);
    // 5 slot: kotak bisa diklik + label nama + jumlah.
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        new Float:sx = 84.0 + float(i) * 96.0;
        invSlotBox[playerid][i] = CreatePlayerTextDraw(playerid, sx, 185.0, "_");
        PlayerTextDrawTextSize(playerid, invSlotBox[playerid][i], sx + 88.0, 255.0);
        PlayerTextDrawUseBox(playerid, invSlotBox[playerid][i], 1);
        PlayerTextDrawBoxColor(playerid, invSlotBox[playerid][i], 0x333333AA);
        PlayerTextDrawSetSelectable(playerid, invSlotBox[playerid][i], 1);

        invSlotName[playerid][i] = CreatePlayerTextDraw(playerid, sx + 44.0, 192.0, "Roti");
        PlayerTextDrawAlignment(playerid, invSlotName[playerid][i], 2);
        PlayerTextDrawFont(playerid, invSlotName[playerid][i], 1);
        PlayerTextDrawLetterSize(playerid, invSlotName[playerid][i], 0.22, 0.95);
        PlayerTextDrawSetOutline(playerid, invSlotName[playerid][i], 1);

        invSlotAmt[playerid][i] = CreatePlayerTextDraw(playerid, sx + 44.0, 222.0, "x0");
        PlayerTextDrawAlignment(playerid, invSlotAmt[playerid][i], 2);
        PlayerTextDrawFont(playerid, invSlotAmt[playerid][i], 2);
        PlayerTextDrawLetterSize(playerid, invSlotAmt[playerid][i], 0.28, 1.1);
        PlayerTextDrawColor(playerid, invSlotAmt[playerid][i], 0xFFFF00FF);
        PlayerTextDrawSetOutline(playerid, invSlotAmt[playerid][i], 1);
    }
    // Tombol tutup.
    invClose[playerid] = CreatePlayerTextDraw(playerid, 320.0, 285.0, "Tutup");
    PlayerTextDrawAlignment(playerid, invClose[playerid], 2);
    PlayerTextDrawFont(playerid, invClose[playerid], 2);
    PlayerTextDrawLetterSize(playerid, invClose[playerid], 0.3, 1.2);
    PlayerTextDrawColor(playerid, invClose[playerid], 0xFF4444FF);
    PlayerTextDrawSetOutline(playerid, invClose[playerid], 1);
    PlayerTextDrawSetSelectable(playerid, invClose[playerid], 1);

    invTDCreated[playerid] = true;
    return 1;
}

stock Inventory_DestroyTDs(playerid)
{
    if (!invTDCreated[playerid]) return 1;
    PlayerTextDrawDestroy(playerid, invBG[playerid]);
    PlayerTextDrawDestroy(playerid, invTitle[playerid]);
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        PlayerTextDrawDestroy(playerid, invSlotBox[playerid][i]);
        PlayerTextDrawDestroy(playerid, invSlotName[playerid][i]);
        PlayerTextDrawDestroy(playerid, invSlotAmt[playerid][i]);
    }
    PlayerTextDrawDestroy(playerid, invClose[playerid]);
    invTDCreated[playerid] = false;
    return 1;
}

// Inventory_Refresh: menggambar ulang nama & jumlah tiap slot.
stock Inventory_Refresh(playerid)
{
    if (!invTDCreated[playerid]) return 0;
    new str[32];
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        PlayerTextDrawSetString(playerid, invSlotName[playerid][i], InvItemName[i]);
        if (invAmount[playerid][i] > 0)
        {
            format(str, sizeof(str), "x%d", invAmount[playerid][i]);
            PlayerTextDrawColor(playerid, invSlotName[playerid][i], 0xFFFFFFFF);
        }
        else
        {
            format(str, sizeof(str), "-");
            PlayerTextDrawColor(playerid, invSlotName[playerid][i], 0x888888FF);
        }
        PlayerTextDrawSetString(playerid, invSlotAmt[playerid][i], str);
    }
    return 1;
}

// Inventory_Show: /inv - tampilkan panel & aktifkan klik.
stock Inventory_Show(playerid)
{
    Inventory_CreateTDs(playerid);
    Inventory_Refresh(playerid);
    PlayerTextDrawShow(playerid, invBG[playerid]);
    PlayerTextDrawShow(playerid, invTitle[playerid]);
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        PlayerTextDrawShow(playerid, invSlotBox[playerid][i]);
        PlayerTextDrawShow(playerid, invSlotName[playerid][i]);
        PlayerTextDrawShow(playerid, invSlotAmt[playerid][i]);
    }
    PlayerTextDrawShow(playerid, invClose[playerid]);
    invOpen[playerid] = true;
    SelectTextDraw(playerid, 0x00FF00AA);
    return 1;
}

// Inventory_Hide: sembunyikan panel & matikan klik.
stock Inventory_Hide(playerid)
{
    if (!invOpen[playerid]) return 0;
    CancelSelectTextDraw(playerid);
    PlayerTextDrawHide(playerid, invBG[playerid]);
    PlayerTextDrawHide(playerid, invTitle[playerid]);
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        PlayerTextDrawHide(playerid, invSlotBox[playerid][i]);
        PlayerTextDrawHide(playerid, invSlotName[playerid][i]);
        PlayerTextDrawHide(playerid, invSlotAmt[playerid][i]);
    }
    PlayerTextDrawHide(playerid, invClose[playerid]);
    invOpen[playerid] = false;
    return 1;
}

// Inventory_OnClickTD: menangani klik slot/tombol (dari OnPlayerClickPlayerTextDraw).
stock Inventory_OnClickTD(playerid, PlayerText:playertextid)
{
    if (!invOpen[playerid]) return 0;
    if (playertextid == PlayerText:INVALID_TEXT_DRAW)
    {
        Inventory_Hide(playerid);
        return 1;
    }
    if (playertextid == invClose[playerid])
    {
        Inventory_Hide(playerid);
        return 1;
    }
    for (new i = 0; i < MAX_INV_ITEMS; i++)
    {
        if (playertextid == invSlotBox[playerid][i])
        {
            invSelItem[playerid] = i;
            new title[48], list[160];
            format(title, sizeof(title), "%s (x%d)", InvItemName[i], invAmount[playerid][i]);
            format(list, sizeof(list), "Gunakan\n(%s)\nBuang 1\nBeri ke Pemain\nKembali",
                InvItemDesc[i]);
            Dialog_Show(playerid, InvItem, DIALOG_STYLE_LIST, title, list, "Pilih", "Tutup");
            return 1;
        }
    }
    return 0;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:InvItem - aksi untuk item yang diklik: gunakan / buang / beri.
Dialog:InvItem(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new itemid = invSelItem[playerid];
    if (itemid < 0 || itemid >= MAX_INV_ITEMS) return 1;
    if (listitem == 0)
    {
        Inventory_UseItem(playerid, itemid);
    }
    else if (listitem == 2)
    {
        if (invAmount[playerid][itemid] <= 0)
        {
            SendClientMessage(playerid, COLOR_GREY, "Kamu tidak punya item itu.");
            return 1;
        }
        invAmount[playerid][itemid]--;
        Inventory_Save(playerid);
        Inventory_Refresh(playerid);
        new msg[96];
        format(msg, sizeof(msg), "Kamu membuang 1x %s.", InvItemName[itemid]);
        SendClientMessage(playerid, COLOR_YELLOW, msg);
    }
    else if (listitem == 3)
    {
        new msg[160];
        format(msg, sizeof(msg),
            "Beri 1x %s ke pemain lain.\n\nKetik ID pemain yang berdiri di dekatmu (maks 5 meter):",
            InvItemName[itemid]);
        Dialog_Show(playerid, InvGive, DIALOG_STYLE_INPUT, "Beri Item", msg, "Beri", "Batal");
    }
    return 1;
}

// Dialog:InvGive - input ID pemain tujuan.
Dialog:InvGive(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!strlen(inputtext) || !IsNumeric(inputtext))
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain harus berupa angka.");
        return 1;
    }
    new target = strval(inputtext);
    if (target == playerid || !IsPlayerConnected(target))
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid.");
        return 1;
    }
    if (!Society_PlayerData[target][sPLogged] || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu belum memilih karakter.");
        return 1;
    }
    new Float:px, Float:py, Float:pz, Float:tx, Float:ty, Float:tz;
    GetPlayerPos(playerid, px, py, pz);
    GetPlayerPos(target, tx, ty, tz);
    new Float:d = floatsqroot((px-tx)*(px-tx) + (py-ty)*(py-ty) + (pz-tz)*(pz-tz));
    if (d > 5.0)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu terlalu jauh (maks 5 meter).");
        return 1;
    }
    new itemid = invSelItem[playerid];
    if (itemid < 0 || itemid >= MAX_INV_ITEMS || invAmount[playerid][itemid] <= 0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Kamu tidak punya item itu.");
        return 1;
    }
    invAmount[playerid][itemid]--;
    invAmount[target][itemid]++;
    Inventory_Save(playerid);
    Inventory_Save(target);
    Inventory_Refresh(playerid);
    Inventory_Refresh(target);
    new pname[MAX_PLAYER_NAME], tname[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(playerid, pname, sizeof(pname));
    GetPlayerName(target, tname, sizeof(tname));
    format(msg, sizeof(msg), "Kamu memberi 1x %s kepada %s.", InvItemName[itemid], tname);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "%s memberimu 1x %s.", pname, InvItemName[itemid]);
    SendClientMessage(target, COLOR_GREEN, msg);
    return 1;
}
