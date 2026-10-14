//================================================================
// Society Roleplay - Workshop_System
// Bengkel dinamis: dibuat oleh admin, dibeli & dikelola oleh pemain.
// Pemilik mendapat profit dari jasa pelanggan: /repair (perbaiki
// kendaraan) dan /mod (ganti warna, pasang komponen, pasang neon).
// Pelanggan harus mengemudikan kendaraan di dekat bengkel yang
// SUDAH ada pemiliknya. Setiap bengkel punya pickup + label 3D
// nama bengkel, tersimpan di tabel workshops.
// Di-include dari gamemodes/Society_Main.pwn (setelah bagian UTIL,
// karena memakai pCharName dan stock util dari file utama).
//================================================================

#if defined _workshop_system_included
    #endinput
#endif
#define _workshop_system_included

//==== KONSTANTA ====
#define MAX_WORKSHOP 100
#define WORKSHOP_RANGE 4.0        // jarak interaksi pickup bengkel
#define WORKSHOP_SERVICE_RANGE 10.0 // jarak servis dari titik bengkel
#define WORKSHOP_SELL_RATE 70     // persen harga kembali saat bengkel dijual
#define WORKSHOP_REPAIR_FEE 150000  // biaya perbaikan kendaraan
#define WORKSHOP_COLOR_FEE 200000   // biaya ganti warna kendaraan
#define WORKSHOP_NEON_FEE 500000    // biaya pasang neon

//==== KATALOG KOMPONEN MODIFIKASI ====
#define WS_COMP_CAT 7
new WsCatName[WS_COMP_CAT][16] =
{
    "Spoiler",
    "Hood",
    "Exhaust",
    "Nitro",
    "Stereo",
    "Hidrolik",
    "Lampu"
};
// Indeks awal tiap kategori di tabel komponen di bawah.
new WsCatStart[WS_COMP_CAT] = {0, 8, 12, 18, 21, 22, 23};
new WsCatCount[WS_COMP_CAT] = {8, 4, 6, 3, 1, 1, 1};

new WsCompID[] =
{
    1000, 1001, 1002, 1003, 1014, 1015, 1016, 1017, // Spoiler
    1004, 1005, 1011, 1012,                         // Hood
    1018, 1019, 1020, 1021, 1022, 1023,             // Exhaust
    1008, 1009, 1010,                               // Nitro
    1086,                                           // Stereo
    1087,                                           // Hidrolik
    1013                                            // Lampu
};
new WsCompName[][20] =
{
    "Spoiler Pro", "Spoiler Win", "Spoiler Drag", "Spoiler Alpha",
    "Spoiler Champ", "Spoiler Race", "Spoiler Worx", "Spoiler GTB",
    "Hood Champ Scoop", "Hood Fury Scoop", "Hood Race Scoop", "Hood Worx Scoop",
    "Exhaust Large", "Exhaust Medium", "Exhaust Small",
    "Exhaust Twin S", "Exhaust Twin M", "Exhaust Twin L",
    "Nitro x2", "Nitro x5", "Nitro x10",
    "Stereo Bass", "Hidrolik", "Lampu Fog"
};
new WsCompPrice[] =
{
    150000, 150000, 150000, 150000, 150000, 150000, 150000, 150000,
    150000, 150000, 150000, 150000,
    150000, 150000, 150000, 150000, 150000, 150000,
    250000, 400000, 600000,
    100000, 500000, 100000
};

//==== DATA BENGKEL ====
new wExists[MAX_WORKSHOP];          // 1 jika slot terisi
new wDBID[MAX_WORKSHOP];           // id baris di tabel workshops
new wName[MAX_WORKSHOP][32];       // nama bengkel
new wOwnerCharID[MAX_WORKSHOP];    // id karakter pemilik (0 = belum ada pemilik)
new wOwnerName[MAX_WORKSHOP][24];  // nama karakter pemilik
new wPrice[MAX_WORKSHOP];          // harga beli
new wProfit[MAX_WORKSHOP];         // keuntungan terkumpul (belum diambil)
new Float:wPosX[MAX_WORKSHOP];
new Float:wPosY[MAX_WORKSHOP];
new Float:wPosZ[MAX_WORKSHOP];
new wPickup[MAX_WORKSHOP];         // id pickup
new Text3D:wLabel[MAX_WORKSHOP];   // label 3D
new bool:wLabelOn[MAX_WORKSHOP];   // true jika label sedang tampil

// Neon: satu objek underglow per kendaraan (id objek, -1 = tidak ada).
new wNeonObj[MAX_VEHICLES];

// Data sementara: pembuatan bengkel oleh admin & menu pemain.
new pWsName[MAX_PLAYERS][32];
new pWsPrice[MAX_PLAYERS];
new pWsSlot[MAX_PLAYERS];
new pWsMenuSlot[MAX_PLAYERS];      // slot bengkel di menu /wsinfo
new pWsModSlot[MAX_PLAYERS];       // slot bengkel saat /mod
new pWsModVeh[MAX_PLAYERS];        // id kendaraan yang dimodifikasi
new pWsColor1[MAX_PLAYERS];        // warna utama sementara (/mod)
new pWsCompIdx[MAX_PLAYERS];       // indeks komponen sementara (/mod)

//==== FORWARD ====
forward OnWorkshopLoaded();
forward OnWorkshopCreated(playerid);

//================================================================
// UTIL BENGKEL
//================================================================

// Workshop_FreeSlot: mencari slot bengkel kosong, -1 jika penuh.
stock Workshop_FreeSlot()
{
    for (new i = 0; i < MAX_WORKSHOP; i++)
    {
        if (!wExists[i]) return i;
    }
    return -1;
}

// Workshop_RefreshLabel: menggambar ulang label 3D sesuai status bengkel.
stock Workshop_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (wLabelOn[slot])
    {
        Delete3DTextLabel(wLabel[slot]);
        wLabelOn[slot] = false;
    }
    new text[256], harga[32];
    FormatRupiah(wPrice[slot], harga, sizeof(harga));
    if (wOwnerCharID[slot] <= 0)
    {
        // Gaya label Infer: ID putih, info kuning, perintah cyan.
        format(text, sizeof(text), "{FFFFFF}ID: %d\n{FFFF00}%s\nHarga: %s\n{00CCFF}/buyworkshop",
            wDBID[slot], wName[slot], harga);
    }
    else
    {
        format(text, sizeof(text), "{FFFFFF}ID: %d\n{FFFF00}%s\nPemilik: %s\n{00CCFF}/repair",
            wDBID[slot], wName[slot], wOwnerName[slot]);
    }
    wLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        wPosX[slot], wPosY[slot], wPosZ[slot] + 1.2, 20.0, 0, 1);
    wLabelOn[slot] = true;
    return 1;
}

// Workshop_Spawn: membuat pickup + label 3D untuk satu bengkel.
stock Workshop_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    wPickup[slot] = CreatePickup(1239, 23, wPosX[slot], wPosY[slot], wPosZ[slot], 0);
    Workshop_RefreshLabel(slot);
    return 1;
}

// Workshop_Nearest: slot bengkel terdekat dalam WORKSHOP_RANGE, -1 jika tidak ada.
stock Workshop_Nearest(playerid)
{
    new best = -1;
    new Float:bestdist = WORKSHOP_RANGE;
    for (new i = 0; i < MAX_WORKSHOP; i++)
    {
        if (!wExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, wPosX[i], wPosY[i], wPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Workshop_NearestOwned: bengkel terdekat yang SUDAH ada pemiliknya
// dalam WORKSHOP_SERVICE_RANGE, -1 jika tidak ada.
stock Workshop_NearestOwned(playerid)
{
    new best = -1;
    new Float:bestdist = WORKSHOP_SERVICE_RANGE;
    for (new i = 0; i < MAX_WORKSHOP; i++)
    {
        if (!wExists[i] || wOwnerCharID[i] <= 0) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, wPosX[i], wPosY[i], wPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Workshop_OwnedNear: slot bengkel milik pemain dalam 10 meter, -1 jika tidak ada.
stock Workshop_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return -1;
    new best = -1;
    new Float:bestdist = 10.0;
    for (new i = 0; i < MAX_WORKSHOP; i++)
    {
        if (!wExists[i] || wOwnerCharID[i] != charid) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, wPosX[i], wPosY[i], wPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Workshop_CountOwned: jumlah bengkel milik satu karakter (untuk /stats).
stock Workshop_CountOwned(charid)
{
    new count = 0;
    for (new i = 0; i < MAX_WORKSHOP; i++)
    {
        if (wExists[i] && wOwnerCharID[i] == charid) count++;
    }
    return count;
}

// Workshop_AddProfit: menambah keuntungan bengkel (in-memory + DB).
stock Workshop_AddProfit(slot, amount)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot] || amount <= 0) return 0;
    wProfit[slot] += amount;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE workshops SET profit = %d WHERE id = %d", wProfit[slot], wDBID[slot]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Workshop_Charge: menagih biaya jasa ke pelanggan. Pemilik bengkel
// gratis. Mengembalikan 1 jika lunas/gratis, 0 jika uang kurang.
stock Workshop_Charge(playerid, slot, amount, const desc[])
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (wOwnerCharID[slot] == charid)
    {
        new msg[160];
        format(msg, sizeof(msg), "Sebagai pemilik bengkel, %s gratis untukmu.", desc);
        SendClientMessage(playerid, COLOR_GREEN, msg);
        return 1;
    }
    if (GetPlayerMoney(playerid) < amount)
    {
        new kurang[32], msg[160];
        FormatRupiah(amount, kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Biaya %s: %s.", desc, kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -amount);
    Workshop_AddProfit(slot, amount);
    new rp[32], msg[192];
    FormatRupiah(amount, rp, sizeof(rp));
    format(msg, sizeof(msg), "Kamu membayar %s untuk %s di bengkel \"%s\".",
        rp, desc, wName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Workshop_CheckService: syarat umum /mod & /repair — pemain harus
// mengemudi dan berada di dekat bengkel yang sudah ada pemiliknya.
// Mengisi pWsModVeh & pWsModSlot, mengembalikan slot atau -1.
stock Workshop_CheckService(playerid)
{
    if (GetPlayerState(playerid) != PLAYER_STATE_DRIVER)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu harus mengemudikan kendaraan.");
        return -1;
    }
    new slot = Workshop_NearestOwned(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada bengkel (yang sudah ada pemiliknya) di dekat sini.");
        return -1;
    }
    pWsModVeh[playerid] = GetPlayerVehicleID(playerid);
    pWsModSlot[playerid] = slot;
    return slot;
}

//================================================================
// NEON
//================================================================

// Workshop_RemoveNeon: menghapus neon yang terpasang di kendaraan.
stock Workshop_RemoveNeon(vehicleid)
{
    if (vehicleid < 0 || vehicleid >= MAX_VEHICLES) return 0;
    if (wNeonObj[vehicleid] != -1 && IsValidObject(wNeonObj[vehicleid]))
    {
        DestroyObject(wNeonObj[vehicleid]);
    }
    wNeonObj[vehicleid] = -1;
    return 1;
}

// Workshop_AttachNeon: memasang neon underglow di kendaraan (color:
// 0 = biru 18647, 1 = pink 18648). Neon lama diganti.
stock Workshop_AttachNeon(vehicleid, color)
{
    if (vehicleid < 0 || vehicleid >= MAX_VEHICLES) return 0;
    Workshop_RemoveNeon(vehicleid);
    new objid = color ? 18648 : 18647;
    wNeonObj[vehicleid] = CreateObject(objid, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    if (wNeonObj[vehicleid] == INVALID_OBJECT_ID) return 0;
    AttachObjectToVehicle(wNeonObj[vehicleid], vehicleid, 0.0, 0.0, -0.4, 0.0, 0.0, 0.0);
    return 1;
}

//================================================================
// AKSI BENGKEL
//================================================================

// Workshop_Create: admin membuat bengkel baru di posisinya (simpan ke DB).
stock Workshop_Create(playerid, const name[], price)
{
    new slot = Workshop_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot bengkel penuh (maksimal 100).");
        return 0;
    }
    format(pWsName[playerid], sizeof(pWsName[]), "%s", name);
    pWsPrice[playerid] = price;
    pWsSlot[playerid] = slot;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO workshops (name, owner_char_id, price, profit, pos_x, pos_y, pos_z) VALUES ('%e', 0, %d, 0, %f, %f, %f)",
        name, price, x, y, z);
    mysql_tquery(g_SQL, query, "OnWorkshopCreated", "d", playerid);
    return 1;
}

// Workshop_Buy: /buyworkshop - pemain membeli bengkel yang belum ada pemiliknya.
stock Workshop_Buy(playerid, slot)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (wOwnerCharID[slot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Bengkel ini sudah ada pemiliknya.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < wPrice[slot])
    {
        new kurang[32], msg[160];
        FormatRupiah(wPrice[slot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Harga bengkel ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -wPrice[slot]);
    wOwnerCharID[slot] = Society_PlayerData[playerid][sPCharID];
    format(wOwnerName[slot], sizeof(wOwnerName[]), "%s", pCharName[playerid]);
    new query[160];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE workshops SET owner_char_id = %d WHERE id = %d",
        wOwnerCharID[slot], wDBID[slot]);
    mysql_tquery(g_SQL, query);
    Workshop_RefreshLabel(slot);
    new harga[32], msg[192];
    FormatRupiah(wPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg), "Selamat! Kamu membeli bengkel \"%s\" seharga %s.", wName[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Ketik /wsinfo di dekat bengkelmu untuk mengelolanya.");
    SendClientMessage(playerid, COLOR_GREY, "Pelanggan yang /repair & /mod di bengkelmu menambah keuntunganmu.");
    return 1;
}

// Workshop_Collect: /wswithdraw - pemilik mengambil keuntungan yang terkumpul.
stock Workshop_Collect(playerid, slot)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (wProfit[slot] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada keuntungan yang bisa diambil.");
        return 0;
    }
    new rp[32], msg[192];
    FormatRupiah(wProfit[slot], rp, sizeof(rp));
    GivePlayerMoney(playerid, wProfit[slot]);
    format(msg, sizeof(msg), "Kamu mengambil keuntungan bengkel \"%s\": %s.", wName[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    wProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE workshops SET profit = 0 WHERE id = %d", wDBID[slot]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Workshop_Sell: menjual bengkel kembali (70% dari harga beli).
stock Workshop_Sell(playerid, slot)
{
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    new kembali = (wPrice[slot] * WORKSHOP_SELL_RATE) / 100;
    GivePlayerMoney(playerid, kembali);
    wOwnerCharID[slot] = 0;
    wOwnerName[slot][0] = EOS;
    wProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE workshops SET owner_char_id = 0, profit = 0 WHERE id = %d", wDBID[slot]);
    mysql_tquery(g_SQL, query);
    Workshop_RefreshLabel(slot);
    new rp[32], msg[192];
    FormatRupiah(kembali, rp, sizeof(rp));
    format(msg, sizeof(msg), "Bengkel \"%s\" terjual kembali. Kamu menerima %s.", wName[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Workshop_ShowInfo: /wsinfo - dialog kelola bengkel milik pemain.
stock Workshop_ShowInfo(playerid)
{
    new slot = Workshop_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada bengkelmu di dekat sini.");
        return 0;
    }
    pWsMenuSlot[playerid] = slot;
    new profit[32], list[256], title[64];
    FormatRupiah(wProfit[slot], profit, sizeof(profit));
    format(list, sizeof(list), "Ambil Keuntungan (%s)\nJual Bengkel", profit);
    format(title, sizeof(title), "Bengkel: %s", wName[slot]);
    Dialog_Show(playerid, WsInfo, DIALOG_STYLE_LIST, title, list, "Pilih", "Tutup");
    return 1;
}

// Workshop_Repair: /repair - memperbaiki kendaraan yang dikemudikan
// di dekat bengkel (biaya masuk ke keuntungan pemilik bengkel).
stock Workshop_Repair(playerid)
{
    new slot = Workshop_CheckService(playerid);
    if (slot == -1) return 0;
    new vehicleid = pWsModVeh[playerid];
    new Float:hp;
    GetVehicleHealth(vehicleid, hp);
    if (hp >= 990.0)
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Kendaraanmu tidak rusak, tidak perlu diperbaiki.");
        return 0;
    }
    if (!Workshop_Charge(playerid, slot, WORKSHOP_REPAIR_FEE, "perbaikan kendaraan")) return 0;
    RepairVehicle(vehicleid);
    SendClientMessage(playerid, COLOR_GREEN, "Kendaraanmu sudah diperbaiki seperti baru.");
    return 1;
}

// Workshop_ModColor: menerapkan warna baru ke kendaraan (setelah /mod).
stock Workshop_ModColor(playerid, color1, color2)
{
    new slot = pWsModSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (!Workshop_Charge(playerid, slot, WORKSHOP_COLOR_FEE, "ganti warna kendaraan")) return 0;
    ChangeVehicleColor(pWsModVeh[playerid], color1, color2);
    SendClientMessage(playerid, COLOR_GREEN, "Warna kendaraanmu sudah diganti.");
    return 1;
}

// Workshop_ModComponent: memasang satu komponen ke kendaraan (setelah /mod).
stock Workshop_ModComponent(playerid, compidx)
{
    new slot = pWsModSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (compidx < 0 || compidx >= sizeof(WsCompID)) return 0;
    if (!Workshop_Charge(playerid, slot, WsCompPrice[compidx], "pasang komponen")) return 0;
    AddVehicleComponent(pWsModVeh[playerid], WsCompID[compidx]);
    new msg[128];
    format(msg, sizeof(msg), "\"%s\" terpasang di kendaraanmu.", WsCompName[compidx]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Workshop_ModNeon: memasang neon underglow (setelah /mod).
stock Workshop_ModNeon(playerid, color)
{
    new slot = pWsModSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 0;
    if (!Workshop_Charge(playerid, slot, WORKSHOP_NEON_FEE, "pasang neon")) return 0;
    if (Workshop_AttachNeon(pWsModVeh[playerid], color))
    {
        SendClientMessage(playerid, COLOR_GREEN, "Neon terpasang di bawah kendaraanmu. Keren!");
    }
    else
    {
        SendClientMessage(playerid, COLOR_RED, "Gagal memasang neon, coba lagi.");
    }
    return 1;
}

// Workshop_LoadAll: memuat semua bengkel dari database saat gamemode mulai.
stock Workshop_LoadAll()
{
    // Neon: tandai semua slot kendaraan belum terpasang neon.
    for (new v = 0; v < MAX_VEHICLES; v++)
    {
        wNeonObj[v] = -1;
    }
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT w.id, w.name, w.owner_char_id, IFNULL(c.name, '') AS owner_name, w.price, w.profit, w.pos_x, w.pos_y, w.pos_z FROM workshops w LEFT JOIN characters c ON c.id = w.owner_char_id",
        "OnWorkshopLoaded");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:WsInfo - menu kelola bengkel: ambil untung, jual.
Dialog:WsInfo(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pWsMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 1;
    if (wOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan bengkelmu.");
        return 1;
    }
    if (listitem == 0)
    {
        Workshop_Collect(playerid, slot);
    }
    else if (listitem == 1)
    {
        new harga[32], msg[256];
        FormatRupiah((wPrice[slot] * WORKSHOP_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual bengkel \"%s\"?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            wName[slot], harga, WORKSHOP_SELL_RATE);
        Dialog_Show(playerid, WsSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Bengkel", msg, "Jual", "Batal");
    }
    return 1;
}

// Dialog:WsSellConfirm - konfirmasi sebelum bengkel dijual kembali.
Dialog:WsSellConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pWsMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP || !wExists[slot]) return 1;
    if (wOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan bengkelmu.");
        return 1;
    }
    Workshop_Sell(playerid, slot);
    return 1;
}

// Dialog:WsModMenu - menu utama /mod untuk pelanggan.
Dialog:WsModMenu(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (listitem == 0) // Ganti warna
    {
        Dialog_Show(playerid, WsColor1, DIALOG_STYLE_INPUT,
            "Ganti Warna", "Masukkan WARNA UTAMA kendaraan (angka 0-126):", "Lanjut", "Batal");
    }
    else if (listitem == 1) // Pasang komponen
    {
        new list[256];
        format(list, sizeof(list), "%s\n%s\n%s\n%s\n%s\n%s\n%s",
            WsCatName[0], WsCatName[1], WsCatName[2], WsCatName[3],
            WsCatName[4], WsCatName[5], WsCatName[6]);
        Dialog_Show(playerid, WsCompCat, DIALOG_STYLE_LIST, "Pilih Kategori Komponen", list, "Pilih", "Kembali");
    }
    else if (listitem == 2) // Pasang neon
    {
        new biaya[32], list[128];
        FormatRupiah(WORKSHOP_NEON_FEE, biaya, sizeof(biaya));
        format(list, sizeof(list), "Neon Biru (%s)\nNeon Pink (%s)", biaya, biaya);
        Dialog_Show(playerid, WsNeonMenu, DIALOG_STYLE_LIST, "Pilih Warna Neon", list, "Pasang", "Kembali");
    }
    else if (listitem == 3) // Lepas neon
    {
        Workshop_RemoveNeon(pWsModVeh[playerid]);
        SendClientMessage(playerid, COLOR_GREEN, "Neon dilepas dari kendaraanmu.");
    }
    return 1;
}

// Dialog:WsColor1 - input warna utama kendaraan.
Dialog:WsColor1(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!IsNumeric(inputtext))
    {
        SendClientMessage(playerid, COLOR_RED, "Warna harus berupa angka 0-126.");
        return 1;
    }
    new c1 = strval(inputtext);
    if (c1 < 0 || c1 > 126)
    {
        SendClientMessage(playerid, COLOR_RED, "Warna harus 0-126.");
        return 1;
    }
    pWsColor1[playerid] = c1;
    Dialog_Show(playerid, WsColor2, DIALOG_STYLE_INPUT,
        "Ganti Warna", "Masukkan WARNA KEDUA kendaraan (angka 0-126):", "Pasang", "Batal");
    return 1;
}

// Dialog:WsColor2 - input warna kedua, lalu terapkan.
Dialog:WsColor2(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!IsNumeric(inputtext))
    {
        SendClientMessage(playerid, COLOR_RED, "Warna harus berupa angka 0-126.");
        return 1;
    }
    new c2 = strval(inputtext);
    if (c2 < 0 || c2 > 126)
    {
        SendClientMessage(playerid, COLOR_RED, "Warna harus 0-126.");
        return 1;
    }
    Workshop_ModColor(playerid, pWsColor1[playerid], c2);
    return 1;
}

// Dialog:WsCompCat - daftar kategori komponen.
Dialog:WsCompCat(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Workshop_ShowModMenu(playerid);
        return 1;
    }
    if (listitem < 0 || listitem >= WS_COMP_CAT) return 1;
    new list[1024], item[64], rp[32];
    list[0] = EOS;
    for (new i = 0; i < WsCatCount[listitem]; i++)
    {
        new idx = WsCatStart[listitem] + i;
        FormatRupiah(WsCompPrice[idx], rp, sizeof(rp));
        format(item, sizeof(item), "%s (%s)\n", WsCompName[idx], rp);
        strcat(list, item);
    }
    pWsCompIdx[playerid] = listitem; // simpan kategori terpilih
    Dialog_Show(playerid, WsCompList, DIALOG_STYLE_LIST,
        WsCatName[listitem], list, "Pasang", "Kembali");
    return 1;
}

// Dialog:WsCompList - daftar komponen dalam satu kategori.
Dialog:WsCompList(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        // Kembali ke daftar kategori.
        new list[256];
        format(list, sizeof(list), "%s\n%s\n%s\n%s\n%s\n%s\n%s",
            WsCatName[0], WsCatName[1], WsCatName[2], WsCatName[3],
            WsCatName[4], WsCatName[5], WsCatName[6]);
        Dialog_Show(playerid, WsCompCat, DIALOG_STYLE_LIST, "Pilih Kategori Komponen", list, "Pilih", "Kembali");
        return 1;
    }
    new cat = pWsCompIdx[playerid];
    if (cat < 0 || cat >= WS_COMP_CAT || listitem < 0 || listitem >= WsCatCount[cat]) return 1;
    new idx = WsCatStart[cat] + listitem;
    pWsCompIdx[playerid] = idx; // simpan indeks komponen terpilih
    new rp[32], msg[256];
    FormatRupiah(WsCompPrice[idx], rp, sizeof(rp));
    format(msg, sizeof(msg),
        "Pasang \"%s\" di kendaraanmu?\n\nBiaya: %s\n\nKomponen langsung terpasang setelah pembayaran.",
        WsCompName[idx], rp);
    Dialog_Show(playerid, WsCompConfirm, DIALOG_STYLE_MSGBOX, "Konfirmasi Komponen", msg, "Pasang", "Batal");
    return 1;
}

// Dialog:WsCompConfirm - konfirmasi sebelum komponen dipasang.
Dialog:WsCompConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    Workshop_ModComponent(playerid, pWsCompIdx[playerid]);
    return 1;
}

// Dialog:WsNeonMenu - pilihan warna neon.
Dialog:WsNeonMenu(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Workshop_ShowModMenu(playerid);
        return 1;
    }
    if (listitem < 0 || listitem > 1) return 1;
    Workshop_ModNeon(playerid, listitem);
    return 1;
}

// Workshop_ShowModMenu: menampilkan menu utama /mod (dipakai ulang saat kembali).
stock Workshop_ShowModMenu(playerid)
{
    new slot = Workshop_CheckService(playerid);
    if (slot == -1) return 0;
    new warna[32], neon[32], list[256];
    FormatRupiah(WORKSHOP_COLOR_FEE, warna, sizeof(warna));
    FormatRupiah(WORKSHOP_NEON_FEE, neon, sizeof(neon));
    format(list, sizeof(list),
        "Ganti Warna Kendaraan (%s)\nPasang Komponen\nPasang Neon (%s)\nLepas Neon (gratis)",
        warna, neon);
    Dialog_Show(playerid, WsModMenu, DIALOG_STYLE_LIST,
        "Bengkel: Modifikasi", list, "Pilih", "Tutup");
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnWorkshopLoaded: mengisi slot bengkel dari database lalu spawn pickup+label.
public OnWorkshopLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_WORKSHOP; i++)
    {
        cache_get_value_name_int(i, "id", tmp);           wDBID[i] = tmp;
        cache_get_value_name(i, "name", wName[i], sizeof(wName[]));
        cache_get_value_name_int(i, "owner_char_id", tmp); wOwnerCharID[i] = tmp;
        cache_get_value_name(i, "owner_name", wOwnerName[i], sizeof(wOwnerName[]));
        cache_get_value_name_int(i, "price", tmp);        wPrice[i] = tmp;
        cache_get_value_name_int(i, "profit", tmp);      wProfit[i] = tmp;
        cache_get_value_name_float(i, "pos_x", ftmp);     wPosX[i] = ftmp;
        cache_get_value_name_float(i, "pos_y", ftmp);     wPosY[i] = ftmp;
        cache_get_value_name_float(i, "pos_z", ftmp);     wPosZ[i] = ftmp;
        wExists[i] = 1;
        wLabelOn[i] = false;
        Workshop_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d bengkel dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnWorkshopCreated: setelah INSERT bengkel berhasil, spawn pickup+label.
public OnWorkshopCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pWsSlot[playerid];
    if (slot < 0 || slot >= MAX_WORKSHOP) return 1;
    wExists[slot] = 1;
    wDBID[slot] = cache_insert_id();
    format(wName[slot], sizeof(wName[]), "%s", pWsName[playerid]);
    wOwnerCharID[slot] = 0;
    wOwnerName[slot][0] = EOS;
    wPrice[slot] = pWsPrice[playerid];
    wProfit[slot] = 0;
    GetPlayerPos(playerid, wPosX[slot], wPosY[slot], wPosZ[slot]);
    wLabelOn[slot] = false;
    Workshop_Spawn(slot);
    new msg[128];
    format(msg, sizeof(msg), "Bengkel \"%s\" berhasil dibuat (ID database %d).", wName[slot], wDBID[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}
