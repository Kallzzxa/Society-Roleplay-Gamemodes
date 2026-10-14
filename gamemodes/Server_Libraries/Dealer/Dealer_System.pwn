//================================================================
// Society Roleplay - Dealer_System
// Dealer kendaraan dinamis: showroom yang bisa dibeli pemain.
// Admin membuat dealer di sebuah lokasi (pickup dolar emas +
// label 3D gaya Infer). Pemain membeli dealer dengan /buydealer,
// lalu pengunjung memakai /dealer di dealer yang sudah ada
// pemiliknya untuk melihat katalog, test drive (spawn sementara
// 60 detik), dan membeli langsung sebagai kendaraan pribadi
// (maks 2 per karakter). Pemilik mendapat komisi 5% dari setiap
// penjualan di dealernya, bisa diambil dengan /dealerwithdraw.
// Label 3D gaya Infer: ID putih, info kuning, perintah cyan.
// Pickup tanda dolar emas (model 1274).
// Tersimpan di tabel dealers.
// Di-include dari gamemodes/Society_Main.pwn (setelah modul
// Vehicle, karena memakai katalog & Vehicle_Buy dari modul itu).
//================================================================

#if defined _dealer_system_included
    #endinput
#endif
#define _dealer_system_included

//==== KONSTANTA ====
#define MAX_DEALER 50            // slot dealer di server
#define DEALER_RANGE 5.0         // jarak interaksi /dealer dari pickup
#define DEALER_TYPE_COUNT 4      // jumlah tipe dealer
#define DEALER_SELL_RATE 70      // jual kembali dealer: 70% dari harga beli
#define DEALER_COMMISSION 5      // komisi pemilik: 5% dari tiap penjualan
#define DEALER_TEST_TIME 60000   // lama test drive: 60 detik
#define DEALER_MAX_PRICE 1000000000 // harga dealer tertinggi saat /createdealer

// Tipe dealer (kategori stok):
// 0 = Umum (semua 16 model), 1 = Ekonomis (< Rp100jt),
// 2 = Sport (>= Rp150jt), 3 = Motor.
new g_DealerTypeName[DEALER_TYPE_COUNT][16] =
{
    "Umum", "Ekonomis", "Sport", "Motor"
};

// Indeks katalog (ke g_VehCatModel di modul Vehicle) per tipe dealer.
new g_DealerStock[DEALER_TYPE_COUNT][VEH_CAT_COUNT] =
{
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {0, 5, 6, 8, 10, 11, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {2, 3, 4, 14, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {10, 11, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
};
new g_DealerStockCount[DEALER_TYPE_COUNT] = {16, 7, 5, 3};

//==== DATA DEALER ====
new dExists[MAX_DEALER];          // 1 jika slot terisi
new dDBID[MAX_DEALER];            // id baris di tabel dealers
new dName[MAX_DEALER][32];        // nama dealer
new dType[MAX_DEALER];            // tipe stok: 0=Umum, 1=Ekonomis, 2=Sport, 3=Motor
new dPrice[MAX_DEALER];           // harga beli dealer (untuk /buydealer)
new dProfit[MAX_DEALER];          // komisi penjualan yang bisa diambil pemilik
new dOwnerCharID[MAX_DEALER];     // id karakter pemilik (0 = dijual)
new dOwnerName[MAX_DEALER][24];   // nama karakter pemilik
new Float:dPosX[MAX_DEALER];
new Float:dPosY[MAX_DEALER];
new Float:dPosZ[MAX_DEALER];
new dPickup[MAX_DEALER];          // id pickup (dolar emas 1274)
new Text3D:dLabel[MAX_DEALER];    // label 3D gaya Infer
new bool:dLabelOn[MAX_DEALER];    // true jika label sedang tampil

// Data sementara per pemain.
new pDealerSlot[MAX_PLAYERS];       // slot dealer yang sedang dipakai di dialog
new pDealerStock[MAX_PLAYERS];      // indeks katalog yang dipilih di dialog showroom
new pDealerListSlot[MAX_PLAYERS];   // slot dealer yang dipilih di /dealers
new pDealerNewName[MAX_PLAYERS][32]; // nama dealer baru (admin /createdealer)
new pDealerNewType[MAX_PLAYERS];    // tipe dealer baru
new pDealerNewPrice[MAX_PLAYERS];   // harga dealer baru
new pDealerNewSlot[MAX_PLAYERS];    // slot dealer baru yang menunggu callback INSERT
new pDealerTest[MAX_PLAYERS] = {INVALID_VEHICLE_ID, ...}; // kendaraan test drive

//==== FORWARD ====
forward OnDealersLoaded();
forward OnDealerCreated(playerid);
forward Dealer_TestEnd(playerid, vehicleid);

//================================================================
// UTIL DEALER
//================================================================

// Dealer_FreeSlot: mencari slot dealer kosong, -1 jika penuh.
stock Dealer_FreeSlot()
{
    for (new i = 0; i < MAX_DEALER; i++)
    {
        if (!dExists[i]) return i;
    }
    return -1;
}

// Dealer_TypeName: nama tipe dealer dari id tipe.
stock Dealer_TypeName(type, dest[], len)
{
    if (type < 0 || type >= DEALER_TYPE_COUNT)
    {
        format(dest, len, "Tidak Dikenal");
        return 0;
    }
    format(dest, len, "%s", g_DealerTypeName[type]);
    return 1;
}

// Dealer_Nearest: slot dealer terdekat dalam DEALER_RANGE, -1 jika tidak ada.
stock Dealer_Nearest(playerid)
{
    new best = -1;
    new Float:bestdist = DEALER_RANGE;
    for (new i = 0; i < MAX_DEALER; i++)
    {
        if (!dExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, dPosX[i], dPosY[i], dPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Dealer_OwnedNear: slot dealer MILIK pemain terdekat dalam DEALER_RANGE, -1 jika tidak ada.
stock Dealer_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return -1;
    new best = -1;
    new Float:bestdist = DEALER_RANGE;
    for (new i = 0; i < MAX_DEALER; i++)
    {
        if (!dExists[i] || dOwnerCharID[i] != charid) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, dPosX[i], dPosY[i], dPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Dealer_RefreshLabel: menggambar ulang label 3D dealer (gaya Infer).
//   {FFFFFF} ID: X
//   {FFFF00} nama dealer (atau "Location: ..." bila dijual)
//   {FFFF00} "Pemilik: ..." (atau "Harga: Rp..." bila dijual)
//   {FFFF00} "Tipe: ..."
//   {00CCFF} perintah (/buydealer bila dijual, /dealer bila dimiliki)
stock Dealer_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    if (dLabelOn[slot])
    {
        Delete3DTextLabel(dLabel[slot]);
        dLabelOn[slot] = false;
    }
    new text[384], line2[64], line3[64], cmdline[16], tipe[16], harga[32];
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    FormatRupiah(dPrice[slot], harga, sizeof(harga));
    if (dOwnerCharID[slot] > 0)
    {
        format(line2, sizeof(line2), "%s", dName[slot]);
        format(line3, sizeof(line3), "Pemilik: %s", dOwnerName[slot]);
        format(cmdline, sizeof(cmdline), "/dealer");
    }
    else
    {
        format(line2, sizeof(line2), "Location: %s", dName[slot]);
        format(line3, sizeof(line3), "Harga: %s", harga);
        format(cmdline, sizeof(cmdline), "/buydealer");
    }
    format(text, sizeof(text),
        "{FFFFFF}ID: %d\n{FFFF00}%s\n{FFFF00}%s\n{FFFF00}Tipe: %s\n{00CCFF}%s",
        dDBID[slot], line2, line3, tipe, cmdline);
    dLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        dPosX[slot], dPosY[slot], dPosZ[slot] + 1.2, 20.0, 0, 1);
    dLabelOn[slot] = true;
    return 1;
}

// Dealer_Spawn: membuat pickup dolar emas + label 3D untuk satu dealer.
stock Dealer_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    dPickup[slot] = CreatePickup(1274, 23, dPosX[slot], dPosY[slot], dPosZ[slot], 0);
    Dealer_RefreshLabel(slot);
    return 1;
}

//================================================================
// BUAT / BELI / JUAL DEALER
//================================================================

// Dealer_Create: admin membuat dealer baru di posisinya (simpan ke DB).
stock Dealer_Create(playerid, const name[], type, price)
{
    new slot = Dealer_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot dealer penuh (maksimal 50).");
        return 0;
    }
    format(pDealerNewName[playerid], sizeof(pDealerNewName[]), "%s", name);
    pDealerNewType[playerid] = type;
    pDealerNewPrice[playerid] = price;
    pDealerNewSlot[playerid] = slot;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO dealers (name, type, price, pos_x, pos_y, pos_z) VALUES ('%e', %d, %d, %f, %f, %f)",
        name, type, price, x, y, z);
    mysql_tquery(g_SQL, query, "OnDealerCreated", "d", playerid);
    return 1;
}

// Dealer_Buy: membeli dealer yang belum ada pemiliknya (di dekat pickup).
stock Dealer_Buy(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 0;
    }
    if (dOwnerCharID[slot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Dealer ini sudah ada pemiliknya.");
        return 0;
    }
    pMoney[playerid] = GetPlayerMoney(playerid);
    if (pMoney[playerid] < dPrice[slot])
    {
        new kurang[32], msg[160];
        FormatRupiah(dPrice[slot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Harga dealer ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -dPrice[slot]);
    pMoney[playerid] = GetPlayerMoney(playerid);
    dOwnerCharID[slot] = charid;
    format(dOwnerName[slot], sizeof(dOwnerName[]), "%s", pCharName[playerid]);
    dProfit[slot] = 0;
    Dealer_RefreshLabel(slot);

    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE dealers SET owner_char_id = %d, profit = 0 WHERE id = %d", charid, dDBID[slot]);
    mysql_tquery(g_SQL, query);

    new harga[32], msg[256], tipe[16];
    FormatRupiah(dPrice[slot], harga, sizeof(harga));
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    format(msg, sizeof(msg),
        "Selamat! Kamu membeli dealer \"%s\" (Tipe: %s) seharga %s.\nSetiap ada yang beli kendaraan di sini, kamu dapat komisi %d%%.",
        dName[slot], tipe, harga, DEALER_COMMISSION);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Ketik /dealer di sini untuk membuka showroom, /dealerinfo untuk mengelola dealer.");
    return 1;
}

// Dealer_Sell: menjual kembali dealer milik pemain (70% dari harga beli).
stock Dealer_Sell(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || dOwnerCharID[slot] != charid)
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan dealermu.");
        return 0;
    }
    new payout = (dPrice[slot] * DEALER_SELL_RATE) / 100;
    GivePlayerMoney(playerid, payout);
    pMoney[playerid] = GetPlayerMoney(playerid);
    dOwnerCharID[slot] = 0;
    dOwnerName[slot][0] = EOS;
    dProfit[slot] = 0;
    Dealer_RefreshLabel(slot);

    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE dealers SET owner_char_id = 0, profit = 0 WHERE id = %d", dDBID[slot]);
    mysql_tquery(g_SQL, query);

    new uang[32], msg[160];
    FormatRupiah(payout, uang, sizeof(uang));
    format(msg, sizeof(msg), "Kamu menjual dealer \"%s\" dan menerima %s (%d%% dari harga beli).",
        dName[slot], uang, DEALER_SELL_RATE);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Dealer_Collect: mengambil komisi penjualan dealer milik pemain.
stock Dealer_Collect(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || dOwnerCharID[slot] != charid)
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan dealermu.");
        return 0;
    }
    if (dProfit[slot] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada komisi yang bisa diambil.");
        return 0;
    }
    new uang[32], msg[160];
    FormatRupiah(dProfit[slot], uang, sizeof(uang));
    GivePlayerMoney(playerid, dProfit[slot]);
    pMoney[playerid] = GetPlayerMoney(playerid);
    dProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE dealers SET profit = 0 WHERE id = %d", dDBID[slot]);
    mysql_tquery(g_SQL, query);
    format(msg, sizeof(msg), "Kamu mengambil komisi dealer \"%s\" sebesar %s.", dName[slot], uang);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Dealer_NotifyOwner: memberitahu pemilik dealer yang online tentang komisi baru.
stock Dealer_NotifyOwner(slot, buyerid, buyername[], price)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    if (dOwnerCharID[slot] <= 0) return 0;
    new commission = (price * DEALER_COMMISSION) / 100;
    dProfit[slot] += commission;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE dealers SET profit = %d WHERE id = %d", dProfit[slot], dDBID[slot]);
    mysql_tquery(g_SQL, query);
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && i != buyerid && Society_PlayerData[i][sPCharID] == dOwnerCharID[slot])
        {
            new uang[32], total[32], msg[256];
            FormatRupiah(commission, uang, sizeof(uang));
            FormatRupiah(dProfit[slot], total, sizeof(total));
            format(msg, sizeof(msg),
                "[DEALER] %s membeli kendaraan di dealer \"%s\". Komisi %s masuk (total komisi: %s).",
                buyername, dName[slot], uang, total);
            SendClientMessage(i, COLOR_YELLOW, msg);
        }
    }
    return 1;
}

//================================================================
// SHOWROOM: TEST DRIVE & BELI
//================================================================

// Dealer_BuildStockList: menyusun daftar stok showroom untuk dialog.
stock Dealer_BuildStockList(slot, dest[], len)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    dest[0] = EOS;
    new harga[32], baris[96], count = g_DealerStockCount[dType[slot]];
    for (new i = 0; i < count; i++)
    {
        new catidx = g_DealerStock[dType[slot]][i];
        FormatRupiah(g_VehCatPrice[catidx], harga, sizeof(harga));
        format(baris, sizeof(baris), "%s - %s", g_VehCatName[catidx], harga);
        if (i > 0) strcat(dest, "\n", len);
        strcat(dest, baris, len);
    }
    return count;
}

// Dealer_ShowShowroom: dialog daftar stok dealer (untuk pembeli).
stock Dealer_ShowShowroom(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new list[1024];
    Dealer_BuildStockList(slot, list, sizeof(list));
    pDealerSlot[playerid] = slot;
    new title[48];
    format(title, sizeof(title), "Showroom: %s", dName[slot]);
    Dialog_Show(playerid, DealerStock, DIALOG_STYLE_LIST, title, list, "Pilih", "Tutup");
    return 1;
}

// Dealer_ShowForSale: dialog info dealer yang belum ada pemiliknya.
stock Dealer_ShowForSale(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new tipe[16], harga[32], msg[384];
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    FormatRupiah(dPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Dealer ini belum ada pemiliknya.\n\nNama: %s\nTipe: %s (%d kendaraan)\nHarga Beli: %s\n\nKetik /buydealer untuk membeli dealer ini.",
        dName[slot], tipe, g_DealerStockCount[dType[slot]], harga);
    Dialog_Show(playerid, DealerForSale, DIALOG_STYLE_MSGBOX, "Dealer Dijual", msg, "Tutup", "");
    return 1;
}

// Dealer_StartTestDrive: spawn kendaraan sementara 60 detik untuk test drive.
stock Dealer_StartTestDrive(playerid, slot, catidx)
{
    if (pDealerTest[playerid] != INVALID_VEHICLE_ID)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu masih dalam test drive. Selesaikan dulu.");
        return 0;
    }
    if (IsPlayerInAnyVehicle(playerid))
    {
        SendClientMessage(playerid, COLOR_RED, "Turun dulu dari kendaraanmu untuk test drive.");
        return 0;
    }
    new Float:px, Float:py, Float:pz, Float:pa;
    GetPlayerPos(playerid, px, py, pz);
    GetPlayerFacingAngle(playerid, pa);
    new Float:sx = px + 4.0 * floatsin(-pa, degrees);
    new Float:sy = py + 4.0 * floatcos(-pa, degrees);
    new veh = CreateVehicle(g_VehCatModel[catidx], sx, sy, pz, pa, random(126), random(126), -1);
    if (veh == INVALID_VEHICLE_ID)
    {
        SendClientMessage(playerid, COLOR_RED, "Gagal membuat kendaraan test drive. Coba lagi.");
        return 0;
    }
    pDealerTest[playerid] = veh;
    SetTimerEx("Dealer_TestEnd", DEALER_TEST_TIME, false, "dd", playerid, veh);
    PutPlayerInVehicle(playerid, veh, 0);
    new msg[160];
    format(msg, sizeof(msg),
        "Test drive %s dimulai! Kendaraan ini akan hilang setelah 60 detik.",
        g_VehCatName[catidx]);
    SendClientMessage(playerid, COLOR_YELLOW, msg);
    return 1;
}

// Dealer_EndTestDrive: menghentikan test drive pemain (dipakai timer & disconnect).
stock Dealer_EndTestDrive(playerid, vehicleid, silent)
{
    if (playerid < 0 || playerid >= MAX_PLAYERS) return 0;
    if (pDealerTest[playerid] == INVALID_VEHICLE_ID) return 0;
    if (vehicleid != INVALID_VEHICLE_ID && pDealerTest[playerid] != vehicleid) return 0;
    pDealerTest[playerid] = INVALID_VEHICLE_ID;
    if (vehicleid != INVALID_VEHICLE_ID) DestroyVehicle(vehicleid);
    if (!silent && IsPlayerConnected(playerid))
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Test drive selesai. Ketik /dealer lagi bila ingin membeli.");
    }
    return 1;
}

// Dealer_BuyVehicle: membeli satu kendaraan dari showroom (jadi kendaraan pribadi).
stock Dealer_BuyVehicle(playerid, slot, catidx)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    if (dOwnerCharID[slot] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Dealer ini belum ada pemiliknya.");
        return 0;
    }
    if (pDealerTest[playerid] != INVALID_VEHICLE_ID)
    {
        SendClientMessage(playerid, COLOR_RED, "Selesaikan dulu test drive-mu sebelum membeli.");
        return 0;
    }
    new price = g_VehCatPrice[catidx];
    if (Vehicle_Buy(playerid, catidx) != 1) return 0;
    // Komisi untuk pemilik dealer.
    Dealer_NotifyOwner(slot, playerid, pCharName[playerid], price);
    return 1;
}

// Dealer_ShowInfo: dialog kelola dealer milik pemain (info + komisi + jual).
stock Dealer_ShowInfo(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    if (dOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan dealermu.");
        return 0;
    }
    pDealerSlot[playerid] = slot;
    new tipe[16], profit[32], title[48];
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    FormatRupiah(dProfit[slot], profit, sizeof(profit));
    format(title, sizeof(title), "Dealer: %s", dName[slot]);
    new menu[256];
    format(menu, sizeof(menu),
        "Info Dealer\nAmbil Komisi (%s)\nJual Dealer", profit);
    Dialog_Show(playerid, DealerInfo, DIALOG_STYLE_LIST, title, menu, "Pilih", "Tutup");
    return 1;
}

// Dealer_ShowInfoText: teks info dealer untuk dialog.
stock Dealer_ShowInfoText(playerid, slot, dest[], len)
{
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 0;
    new tipe[16], harga[32], profit[32];
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    FormatRupiah(dPrice[slot], harga, sizeof(harga));
    FormatRupiah(dProfit[slot], profit, sizeof(profit));
    format(dest, len,
        "ID: %d\nNama: %s\nTipe: %s (%d kendaraan)\nHarga Beli: %s\nPemilik: %s\nKomisi: %s (%d%% tiap penjualan)",
        dDBID[slot], dName[slot], tipe, g_DealerStockCount[dType[slot]],
        harga, dOwnerName[slot], profit, DEALER_COMMISSION);
    return 1;
}

//================================================================
// /dealers: DAFTAR SEMUA DEALER
//================================================================

// Dealer_ShowList: dialog daftar semua dealer di server.
stock Dealer_ShowList(playerid)
{
    new list[1024], baris[128], tipe[16], status[16];
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_DEALER; i++)
    {
        if (!dExists[i]) continue;
        Dealer_TypeName(dType[i], tipe, sizeof(tipe));
        if (dOwnerCharID[i] > 0) format(status, sizeof(status), "Dimiliki");
        else format(status, sizeof(status), "Dijual");
        format(baris, sizeof(baris), "%s (%s) - %s", dName[i], tipe, status);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada dealer di server.");
        return 0;
    }
    Dialog_Show(playerid, DealerList, DIALOG_STYLE_LIST, "Daftar Dealer", list, "Lihat", "Tutup");
    return 1;
}

//================================================================
// ON DISCONNECT
//================================================================

// Dealer_OnDisconnect: hapus kendaraan test drive saat pemain keluar.
stock Dealer_OnDisconnect(playerid)
{
    Dealer_EndTestDrive(playerid, pDealerTest[playerid], 1);
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:DealerStock - daftar stok showroom, pilih untuk detail.
Dialog:DealerStock(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDealerSlot[playerid];
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 1;
    new count = g_DealerStockCount[dType[slot]];
    if (listitem < 0 || listitem >= count) return 1;
    pDealerStock[playerid] = g_DealerStock[dType[slot]][listitem];
    new catidx = pDealerStock[playerid];
    new harga[32], msg[256];
    FormatRupiah(g_VehCatPrice[catidx], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Kamu memilih:\n\n%s\nHarga: %s\n\nMau coba dulu atau beli langsung?",
        g_VehCatName[catidx], harga);
    Dialog_Show(playerid, DealerDetail, DIALOG_STYLE_LIST, g_VehCatName[catidx],
        "Test Drive (60 detik)\nBeli Sekarang\nKembali", "Pilih", "Tutup");
    return 1;
}

// Dialog:DealerDetail - test drive atau beli kendaraan yang dipilih.
Dialog:DealerDetail(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDealerSlot[playerid];
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 1;
    if (listitem == 0)
    {
        Dealer_StartTestDrive(playerid, slot, pDealerStock[playerid]);
    }
    else if (listitem == 1)
    {
        new catidx = pDealerStock[playerid];
        new harga[32], msg[320];
        FormatRupiah(g_VehCatPrice[catidx], harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Kamu akan membeli:\n\n%s\nHarga: %s\n\nKendaraan ini menjadi kendaraan pribadimu (maks 2 per karakter).\nKetik /vlist untuk mengelolanya.",
            g_VehCatName[catidx], harga);
        Dialog_Show(playerid, DealerBuyConfirm, DIALOG_STYLE_MSGBOX, "Beli Kendaraan", msg, "Beli", "Batal");
    }
    else
    {
        Dealer_ShowShowroom(playerid, slot);
    }
    return 1;
}

// Dialog:DealerBuyConfirm - konfirmasi sebelum uang dipotong.
Dialog:DealerBuyConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    Dealer_BuyVehicle(playerid, pDealerSlot[playerid], pDealerStock[playerid]);
    return 1;
}

// Dialog:DealerForSale - info dealer yang dijual (dialog info, abaikan respon).
Dialog:DealerForSale(playerid, response, listitem, inputtext[])
{
    return 1;
}

// Dialog:DealerInfo - kelola dealer milik pemain: info, ambil komisi, jual.
Dialog:DealerInfo(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDealerSlot[playerid];
    if (slot < 0 || slot >= MAX_DEALER || !dExists[slot]) return 1;
    if (dOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan dealermu.");
        return 1;
    }
    if (listitem == 0)
    {
        new msg[384];
        Dealer_ShowInfoText(playerid, slot, msg, sizeof(msg));
        Dialog_Show(playerid, DealerInfoBack, DIALOG_STYLE_MSGBOX, "Info Dealer", msg, "Kembali", "");
    }
    else if (listitem == 1)
    {
        Dealer_Collect(playerid, slot);
    }
    else if (listitem == 2)
    {
        new harga[32], msg[256];
        FormatRupiah((dPrice[slot] * DEALER_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual dealer \"%s\"?\n\nKamu akan menerima %s (%d%% dari harga beli).",
            dName[slot], harga, DEALER_SELL_RATE);
        Dialog_Show(playerid, DealerSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Dealer", msg, "Jual", "Batal");
    }
    return 1;
}

// Dialog:DealerInfoBack - kembali ke menu kelola dealer setelah melihat info.
Dialog:DealerInfoBack(playerid, response, listitem, inputtext[])
{
    Dealer_ShowInfo(playerid, pDealerSlot[playerid]);
    return 1;
}

// Dialog:DealerSellConfirm - konfirmasi jual dealer.
Dialog:DealerSellConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    Dealer_Sell(playerid, pDealerSlot[playerid]);
    return 1;
}

// Dialog:DealerList - daftar dealer, pilih untuk melihat detail.
Dialog:DealerList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new count = 0, slot = -1;
    for (new i = 0; i < MAX_DEALER; i++)
    {
        if (!dExists[i]) continue;
        if (count == listitem)
        {
            slot = i;
            break;
        }
        count++;
    }
    if (slot == -1) return 1;
    pDealerListSlot[playerid] = slot;
    new msg[384];
    Dealer_ShowInfoText(playerid, slot, msg, sizeof(msg));
    Dialog_Show(playerid, DealerListBack, DIALOG_STYLE_MSGBOX, "Detail Dealer", msg, "Kembali", "");
    return 1;
}

// Dialog:DealerListBack - kembali ke daftar dealer setelah melihat detail.
Dialog:DealerListBack(playerid, response, listitem, inputtext[])
{
    Dealer_ShowList(playerid);
    return 1;
}

//================================================================
// LOAD
//================================================================

// Dealer_LoadAll: memuat semua dealer dari database.
stock Dealer_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT d.id, d.name, d.owner_char_id, IFNULL(c.name, '') AS owner_name, d.type, d.price, d.profit, d.pos_x, d.pos_y, d.pos_z FROM dealers d LEFT JOIN characters c ON c.id = d.owner_char_id",
        "OnDealersLoaded");
    return 1;
}

//================================================================
// CALLBACK MYSQL & TIMER
//================================================================

// OnDealersLoaded: mengisi slot dealer dari database lalu spawn pickup+label.
public OnDealersLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_DEALER; i++)
    {
        cache_get_value_name_int(i, "id", tmp);            dDBID[i] = tmp;
        cache_get_value_name(i, "name", dName[i], sizeof(dName[]));
        cache_get_value_name_int(i, "owner_char_id", tmp); dOwnerCharID[i] = tmp;
        cache_get_value_name(i, "owner_name", dOwnerName[i], sizeof(dOwnerName[]));
        cache_get_value_name_int(i, "type", tmp);          dType[i] = tmp;
        cache_get_value_name_int(i, "price", tmp);         dPrice[i] = tmp;
        cache_get_value_name_int(i, "profit", tmp);        dProfit[i] = tmp;
        cache_get_value_name_float(i, "pos_x", ftmp);      dPosX[i] = ftmp;
        cache_get_value_name_float(i, "pos_y", ftmp);      dPosY[i] = ftmp;
        cache_get_value_name_float(i, "pos_z", ftmp);      dPosZ[i] = ftmp;
        dExists[i] = 1;
        Dealer_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d dealer dinamis dimuat.", count);
    print(msg);
    return 1;
}

// OnDealerCreated: menyimpan id database hasil INSERT dealer baru.
public OnDealerCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pDealerNewSlot[playerid];
    if (slot < 0 || slot >= MAX_DEALER) return 1;
    new id = cache_insert_id();
    dDBID[slot] = id;
    format(dName[slot], sizeof(dName[]), "%s", pDealerNewName[playerid]);
    dType[slot] = pDealerNewType[playerid];
    dPrice[slot] = pDealerNewPrice[playerid];
    dProfit[slot] = 0;
    dOwnerCharID[slot] = 0;
    dOwnerName[slot][0] = EOS;
    GetPlayerPos(playerid, dPosX[slot], dPosY[slot], dPosZ[slot]);
    dExists[slot] = 1;
    Dealer_Spawn(slot);
    new harga[32], tipe[16], msg[256];
    FormatRupiah(dPrice[slot], harga, sizeof(harga));
    Dealer_TypeName(dType[slot], tipe, sizeof(tipe));
    format(msg, sizeof(msg),
        "[DEALER] Dealer \"%s\" (ID %d, Tipe: %s) dibuat di lokasimu. Harga: %s.",
        dName[slot], id, tipe, harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Dealer_TestEnd: timer test drive — kendaraan sementara dihapus.
public Dealer_TestEnd(playerid, vehicleid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    Dealer_EndTestDrive(playerid, vehicleid, 0);
    return 1;
}

//================================================================
// COMMAND (dipanggil dari OnPlayerCommandText di file utama)
//================================================================

// Dealer_CmdCreate: /createdealer [nama] [tipe] [harga] - admin level 3+.
// Tipe: 0=Umum, 1=Ekonomis, 2=Sport, 3=Motor. Spasi pada nama diganti _.
stock Dealer_CmdCreate(playerid, const cmdtext[], idx)
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
        SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createdealer [nama] [tipe] [harga]");
        SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=Umum (16 model), 1=Ekonomis (murah), 2=Sport (mahal), 3=Motor");
        SendClientMessage(playerid, COLOR_GREY, "Contoh: /createdealer Mobil_Surya 0 250000000 (spasi diganti _)");
        return 1;
    }
    if (strlen(snama) < 3)
    {
        SendClientMessage(playerid, COLOR_RED, "Nama dealer minimal 3 karakter.");
        return 1;
    }
    if (!IsNumeric(stipe) || !IsNumeric(sharga))
    {
        SendClientMessage(playerid, COLOR_RED, "Tipe dan harga harus berupa angka.");
        return 1;
    }
    new type = strval(stipe), price = strval(sharga);
    if (type < 0 || type >= DEALER_TYPE_COUNT)
    {
        SendClientMessage(playerid, COLOR_RED, "Tipe dealer harus 0-3.");
        return 1;
    }
    if (price < 10000000 || price > DEALER_MAX_PRICE)
    {
        SendClientMessage(playerid, COLOR_RED, "Harga dealer harus Rp10.000.000 - Rp1.000.000.000.");
        return 1;
    }
    for (new i = 0; snama[i] != EOS; i++)
    {
        if (snama[i] == '_') snama[i] = ' ';
    }
    Dealer_Create(playerid, snama, type, price);
    return 1;
}

// Dealer_CmdBuy: /buydealer - membeli dealer di dekatmu (yang dijual).
stock Dealer_CmdBuy(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Dealer_Nearest(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada dealer di dekatmu.");
        return 1;
    }
    Dealer_Buy(playerid, slot);
    return 1;
}

// Dealer_CmdShowroom: /dealer - showroom di dealer terdekat.
stock Dealer_CmdShowroom(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Dealer_Nearest(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada dealer di dekatmu.");
        return 1;
    }
    if (dOwnerCharID[slot] <= 0)
    {
        Dealer_ShowForSale(playerid, slot);
    }
    else
    {
        Dealer_ShowShowroom(playerid, slot);
    }
    return 1;
}

// Dealer_CmdInfo: /dealerinfo - dialog kelola dealer milikmu.
stock Dealer_CmdInfo(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Dealer_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada dealermu di dekat sini.");
        return 1;
    }
    Dealer_ShowInfo(playerid, slot);
    return 1;
}

// Dealer_CmdWithdraw: /dealerwithdraw - mengambil komisi dealer milikmu.
stock Dealer_CmdWithdraw(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Dealer_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada dealermu di dekat sini.");
        return 1;
    }
    Dealer_Collect(playerid, slot);
    return 1;
}

// Dealer_CmdSell: /selldealer - menjual kembali dealermu (70%).
stock Dealer_CmdSell(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Dealer_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada dealermu di dekat sini.");
        return 1;
    }
    pDealerSlot[playerid] = slot;
    new harga[32], msg[256];
    FormatRupiah((dPrice[slot] * DEALER_SELL_RATE) / 100, harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Yakin ingin menjual dealer \"%s\"?\n\nKamu akan menerima %s (%d%% dari harga beli).",
        dName[slot], harga, DEALER_SELL_RATE);
    Dialog_Show(playerid, DealerSellConfirm, DIALOG_STYLE_MSGBOX, "Jual Dealer", msg, "Jual", "Batal");
    return 1;
}

// Dealer_CmdList: /dealers - daftar semua dealer di server.
stock Dealer_CmdList(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged])
    {
        SendClientMessage(playerid, COLOR_RED, "Anda harus login terlebih dahulu.");
        return 1;
    }
    Dealer_ShowList(playerid);
    return 1;
}
