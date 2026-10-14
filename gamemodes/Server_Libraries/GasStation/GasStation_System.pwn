//================================================================
// Society Roleplay - GasStation_System
// Pom bensin dinamis: stasiun pengisian bahan bakar yang bisa
// dibeli pemain. Admin membuat pom di sebuah lokasi (pickup +
// label 3D). Pemain membeli pom dengan /buygasstation, lalu
// pemilik mengatur harga per liter (/setfuelprice), membeli
// stok bensin dari pemasok, dan mengambil keuntungan penjualan.
// Pengemudi mengisi bensin kendaraannya dengan /refuel saat
// berada di dekat pompa.
//
// Modul ini juga menjalankan SISTEM BENSIN: bensin kendaraan
// pribadi (kolom fuel, 0-100) berkurang saat dikendarai
// (dicek tiap 30 detik via timer FuelTick). Bensin habis =
// pengemudi dikeluarkan dari kendaraan. Indikator bensin tampil
// di textdraw info kendaraan (modul Vehicle) dan diperbarui
// otomatis selama mengemudi.
//
// Skema DB: tabel gasstations (id, name, owner_char_id,
// price, price_per_liter, stock, profit, pos_x/y/z).
// Di-include dari gamemodes/Society_Main.pwn (setelah modul
// Vehicle, karena memakai vFuel & Vehicle_SlotFromVehID).
//================================================================

#if defined _gasstation_system_included
    #endinput
#endif
#define _gasstation_system_included

//==== KONSTANTA ====
#define MAX_GASSTATION 30        // slot pom bensin di server
#define GAS_RANGE 8.0            // jarak interaksi /refuel dari pompa
#define GAS_SELL_RATE 70         // jual kembali pom: 70% dari harga beli
#define GAS_MAX_PRICE 500000000  // harga pom tertinggi saat /creategasstation
#define GAS_DEFAULT_PPL 15000    // harga awal per liter (Rp15.000)
#define GAS_MIN_PPL 1000         // harga per liter terendah (Rp1.000)
#define GAS_MAX_PPL 50000        // harga per liter tertinggi (Rp50.000)
#define GAS_SUPPLY_COST 8000     // harga pemasok per liter saat pemilik isi stok
#define GAS_MAX_STOCK 20000      // kapasitas tangki pom (liter)
#define GAS_START_STOCK 5000     // stok awal pom baru (liter)
#define FUEL_TICK_TIME 30000     // bensin dicek tiap 30 detik
#define FUEL_DRAIN 1.0           // bensin berkurang per tick saat melaju
#define FUEL_DRAIN_IDLE 0.25      // bensin berkurang per tick saat diam

//==== DATA POM BENSIN ====
new gsExists[MAX_GASSTATION];       // 1 jika slot terisi
new gsDBID[MAX_GASSTATION];         // id baris di tabel gasstations
new gsName[MAX_GASSTATION][32];     // nama pom
new gsOwnerCharID[MAX_GASSTATION];  // id karakter pemilik (0 = dijual)
new gsOwnerName[MAX_GASSTATION][24];// nama karakter pemilik
new gsPrice[MAX_GASSTATION];        // harga beli pom (untuk /buygasstation)
new gsPricePerLiter[MAX_GASSTATION];// harga jual bensin per liter
new gsStock[MAX_GASSTATION];        // stok bensin di tangki pom (liter)
new gsProfit[MAX_GASSTATION];       // keuntungan penjualan yang bisa diambil
new Float:gsPosX[MAX_GASSTATION];
new Float:gsPosY[MAX_GASSTATION];
new Float:gsPosZ[MAX_GASSTATION];
new gsPickup[MAX_GASSTATION];       // id pickup (tanda info 1239)
new Text3D:gsLabel[MAX_GASSTATION]; // label 3D nama + harga
new bool:gsLabelOn[MAX_GASSTATION]; // true jika label sedang tampil

// Data sementara per pemain.
new pGasSlot[MAX_PLAYERS];            // slot pom yang sedang dipakai di dialog
new pGasListSlot[MAX_PLAYERS];        // slot pom yang dipilih di /gasstations
new pGasNewName[MAX_PLAYERS][32];     // nama pom baru (admin /creategasstation)
new pGasNewPrice[MAX_PLAYERS];        // harga pom baru
new pGasNewSlot[MAX_PLAYERS];         // slot pom baru yang menunggu callback INSERT

//==== FORWARD ====
forward OnGasStationsLoaded();
forward OnGasStationCreated(playerid);
forward FuelTick();

//================================================================
// UTIL POM BENSIN
//================================================================

// GasStation_FreeSlot: mencari slot pom kosong, -1 jika penuh.
stock GasStation_FreeSlot()
{
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (!gsExists[i]) return i;
    }
    return -1;
}

// GasStation_Nearest: slot pom terdekat dalam GAS_RANGE, -1 jika tidak ada.
stock GasStation_Nearest(playerid)
{
    new best = -1;
    new Float:bestdist = GAS_RANGE;
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (!gsExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, gsPosX[i], gsPosY[i], gsPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// GasStation_OwnedNear: slot pom MILIK pemain terdekat dalam GAS_RANGE, -1 jika tidak ada.
stock GasStation_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return -1;
    new best = -1;
    new Float:bestdist = GAS_RANGE;
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (!gsExists[i] || gsOwnerCharID[i] != charid) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, gsPosX[i], gsPosY[i], gsPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// GasStation_CountOwned: jumlah pom milik satu karakter (untuk /stats).
stock GasStation_CountOwned(charid)
{
    new count = 0;
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (gsExists[i] && gsOwnerCharID[i] == charid) count++;
    }
    return count;
}

// GasStation_RefreshLabel: menggambar ulang label 3D pom (nama + harga).
//   {FFFF00} [POM BENSIN ID: x]
//   {FFFFFF} nama pom
//   {FFFF00} harga per liter (+ stok bila ada pemilik)
//   {00CCFF} perintah (/buygasstation bila dijual, /refuel bila beroperasi)
stock GasStation_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (gsLabelOn[slot])
    {
        Delete3DTextLabel(gsLabel[slot]);
        gsLabelOn[slot] = false;
    }
    new text[384], harga[32], hargaliter[32];
    FormatRupiah(gsPrice[slot], harga, sizeof(harga));
    FormatRupiah(gsPricePerLiter[slot], hargaliter, sizeof(hargaliter));
    if (gsOwnerCharID[slot] > 0)
    {
        format(text, sizeof(text),
            "{FFFF00}[POM BENSIN ID: %d]\n{FFFFFF}%s\n{FFFF00}Harga: %s/liter\n{FFFFFF}Stok: %d liter\n{FFFFFF}Pemilik: %s\n{00CCFF}/refuel",
            gsDBID[slot], gsName[slot], hargaliter, gsStock[slot], gsOwnerName[slot]);
    }
    else
    {
        format(text, sizeof(text),
            "{FFFF00}[POM BENSIN ID: %d]\n{FFFFFF}%s\n{FFFF00}Harga: %s/liter\n{FFFFFF}Status: {00FF00}DIJUAL\n{FFFF00}Harga Pom: %s\n{00CCFF}/buygasstation",
            gsDBID[slot], gsName[slot], hargaliter, harga);
    }
    gsLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        gsPosX[slot], gsPosY[slot], gsPosZ[slot] + 1.2, 20.0, 0, 1);
    gsLabelOn[slot] = true;
    return 1;
}

// GasStation_Spawn: membuat pickup + label 3D untuk satu pom.
stock GasStation_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    gsPickup[slot] = CreatePickup(1239, 23, gsPosX[slot], gsPosY[slot], gsPosZ[slot], 0);
    GasStation_RefreshLabel(slot);
    return 1;
}

//================================================================
// BUAT / BELI / JUAL POM
//================================================================

// GasStation_Create: admin membuat pom baru di posisinya (simpan ke DB).
stock GasStation_Create(playerid, const name[], price)
{
    new slot = GasStation_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot pom bensin penuh (maksimal 30).");
        return 0;
    }
    format(pGasNewName[playerid], sizeof(pGasNewName[]), "%s", name);
    pGasNewPrice[playerid] = price;
    pGasNewSlot[playerid] = slot;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO gasstations (name, price, price_per_liter, stock, pos_x, pos_y, pos_z) VALUES ('%e', %d, %d, %d, %f, %f, %f)",
        name, price, GAS_DEFAULT_PPL, GAS_START_STOCK, x, y, z);
    mysql_tquery(g_SQL, query, "OnGasStationCreated", "d", playerid);
    return 1;
}

// GasStation_Buy: membeli pom yang belum ada pemiliknya (di dekat pompa).
stock GasStation_Buy(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 0;
    }
    if (gsOwnerCharID[slot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Pom bensin ini sudah ada pemiliknya.");
        return 0;
    }
    pMoney[playerid] = GetPlayerMoney(playerid);
    if (pMoney[playerid] < gsPrice[slot])
    {
        new kurang[32], msg[160];
        FormatRupiah(gsPrice[slot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Harga pom ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -gsPrice[slot]);
    pMoney[playerid] = GetPlayerMoney(playerid);
    gsOwnerCharID[slot] = charid;
    format(gsOwnerName[slot], sizeof(gsOwnerName[]), "%s", pCharName[playerid]);
    gsProfit[slot] = 0;
    GasStation_RefreshLabel(slot);

    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE gasstations SET owner_char_id = %d, profit = 0 WHERE id = %d", charid, gsDBID[slot]);
    mysql_tquery(g_SQL, query);

    new harga[32], msg[256];
    FormatRupiah(gsPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Selamat! Kamu membeli pom bensin \"%s\" seharga %s.\nAtur harga per liter dengan /setfuelprice di sini.",
        gsName[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Kelola pom dengan /gasinfo. Isi ulang stok bensin dari pemasok lewat menu itu.");
    return 1;
}

// GasStation_Sell: menjual kembali pom milik pemain (70% dari harga beli).
stock GasStation_Sell(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || gsOwnerCharID[slot] != charid)
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 0;
    }
    new payout = (gsPrice[slot] * GAS_SELL_RATE) / 100;
    GivePlayerMoney(playerid, payout);
    pMoney[playerid] = GetPlayerMoney(playerid);
    gsOwnerCharID[slot] = 0;
    gsOwnerName[slot][0] = EOS;
    gsProfit[slot] = 0;
    gsPricePerLiter[slot] = GAS_DEFAULT_PPL;
    GasStation_RefreshLabel(slot);

    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE gasstations SET owner_char_id = 0, profit = 0, price_per_liter = %d WHERE id = %d",
        GAS_DEFAULT_PPL, gsDBID[slot]);
    mysql_tquery(g_SQL, query);

    new uang[32], msg[160];
    FormatRupiah(payout, uang, sizeof(uang));
    format(msg, sizeof(msg), "Kamu menjual pom \"%s\" dan menerima %s (%d%% dari harga beli).",
        gsName[slot], uang, GAS_SELL_RATE);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// GasStation_Collect: mengambil keuntungan penjualan bensin pom milik pemain.
stock GasStation_Collect(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0 || gsOwnerCharID[slot] != charid)
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 0;
    }
    if (gsProfit[slot] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada keuntungan yang bisa diambil.");
        return 0;
    }
    new uang[32], msg[160];
    FormatRupiah(gsProfit[slot], uang, sizeof(uang));
    GivePlayerMoney(playerid, gsProfit[slot]);
    pMoney[playerid] = GetPlayerMoney(playerid);
    gsProfit[slot] = 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE gasstations SET profit = 0 WHERE id = %d", gsDBID[slot]);
    mysql_tquery(g_SQL, query);
    format(msg, sizeof(msg), "Kamu mengambil keuntungan pom \"%s\" sebesar %s.", gsName[slot], uang);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// GasStation_NotifyOwner: memberitahu pemilik pom yang online tentang penjualan baru.
stock GasStation_NotifyOwner(slot, drivername[], liters, revenue)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (gsOwnerCharID[slot] <= 0) return 0;
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Society_PlayerData[i][sPCharID] == gsOwnerCharID[slot])
        {
            new uang[32], msg[256];
            FormatRupiah(revenue, uang, sizeof(uang));
            format(msg, sizeof(msg),
                "[POM] %s mengisi %d liter di pom \"%s\". %s masuk ke keuntunganmu (stok tersisa %d liter).",
                drivername, liters, gsName[slot], uang, gsStock[slot]);
            SendClientMessage(i, COLOR_YELLOW, msg);
        }
    }
    return 1;
}

// GasStation_SetPrice: pemilik mengatur harga jual bensin per liter.
stock GasStation_SetPrice(playerid, slot, priceper)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (gsOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 0;
    }
    if (priceper < GAS_MIN_PPL || priceper > GAS_MAX_PPL)
    {
        SendClientMessage(playerid, COLOR_RED, "Harga per liter harus Rp1.000 - Rp50.000.");
        return 0;
    }
    gsPricePerLiter[slot] = priceper;
    GasStation_RefreshLabel(slot);
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE gasstations SET price_per_liter = %d WHERE id = %d", priceper, gsDBID[slot]);
    mysql_tquery(g_SQL, query);
    new harga[32], msg[160];
    FormatRupiah(priceper, harga, sizeof(harga));
    format(msg, sizeof(msg), "Harga bensin di pom \"%s\" kini %s per liter.", gsName[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// GasStation_BuyStock: pemilik membeli stok bensin dari pemasok (Rp8.000/liter).
stock GasStation_BuyStock(playerid, slot, liters)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (gsOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 0;
    }
    if (liters <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Jumlah liter harus lebih dari 0.");
        return 0;
    }
    if (gsStock[slot] + liters > GAS_MAX_STOCK)
    {
        new msg[160];
        format(msg, sizeof(msg), "Tangki pom maksimal %d liter (saat ini %d liter).",
            GAS_MAX_STOCK, gsStock[slot]);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    new cost = liters * GAS_SUPPLY_COST;
    pMoney[playerid] = GetPlayerMoney(playerid);
    if (pMoney[playerid] < cost)
    {
        new kurang[32], msg[160];
        FormatRupiah(cost, kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. %d liter dari pemasok harganya %s.", liters, kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -cost);
    pMoney[playerid] = GetPlayerMoney(playerid);
    gsStock[slot] += liters;
    GasStation_RefreshLabel(slot);
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE gasstations SET stock = %d WHERE id = %d", gsStock[slot], gsDBID[slot]);
    mysql_tquery(g_SQL, query);
    new uang[32], msg[192];
    FormatRupiah(cost, uang, sizeof(uang));
    format(msg, sizeof(msg), "Kamu membeli %d liter bensin dari pemasok seharga %s. Stok pom: %d liter.",
        liters, uang, gsStock[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// /refuel: ISI BENSIN DI POMPA
//================================================================

// GasStation_ShowRefuel: dialog info pengisian bensin sebelum konfirmasi.
stock GasStation_ShowRefuel(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (GetPlayerState(playerid) != PLAYER_STATE_DRIVER)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu harus mengemudi untuk mengisi bensin.");
        return 0;
    }
    new vslot = Vehicle_SlotFromVehID(GetPlayerVehicleID(playerid));
    if (vslot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya kendaraan pribadi yang bisa diisi bensin di sini.");
        return 0;
    }
    new Float:need = 100.0 - vFuel[vslot];
    if (need < 1.0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tangki kendaraanmu sudah penuh.");
        return 0;
    }
    new liters = floatround(need, floatround_floor);
    if (liters < 1) liters = 1;
    if (gsOwnerCharID[slot] > 0 && gsStock[slot] < liters) liters = gsStock[slot];
    if (liters <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Stok bensin pom ini habis.");
        return 0;
    }
    pGasSlot[playerid] = slot;
    new harga[32], total[32], msg[384], namakend[32], opts[2][64];
    FormatRupiah(gsPricePerLiter[slot], harga, sizeof(harga));
    FormatRupiah(liters * gsPricePerLiter[slot], total, sizeof(total));
    Vehicle_CatName(vModel[vslot], namakend, sizeof(namakend));
    format(msg, sizeof(msg),
        "Pom: %s~n~Harga: %s/liter~n~~n~Kendaraan: %s (%s)~n~Bensin saat ini: %d%%~n~Akan diisi: %d liter~n~Total bayar: %s~n~~n~Uang kurang atau stok menipis? Tangki diisi semampunya.",
        gsName[slot], harga, namakend, vPlate[vslot],
        floatround(vFuel[vslot], floatround_round), liters, total);
    format(opts[0], 64, "Isi");
    format(opts[1], 64, "Batal");
    UI_ShowMenu(playerid, "dialog_GasRefuel", "ISI BENSIN", msg, opts, 2);
    return 1;
}

// GasStation_Refuel: mengisi bensin kendaraan pribadi (isi penuh, atau semampunya).
stock GasStation_Refuel(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (GetPlayerState(playerid) != PLAYER_STATE_DRIVER)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu harus mengemudi untuk mengisi bensin.");
        return 0;
    }
    new vslot = Vehicle_SlotFromVehID(GetPlayerVehicleID(playerid));
    if (vslot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya kendaraan pribadi yang bisa diisi bensin di sini.");
        return 0;
    }
    new Float:need = 100.0 - vFuel[vslot];
    if (need < 1.0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tangki kendaraanmu sudah penuh.");
        return 0;
    }
    new liters = floatround(need, floatround_floor);
    if (liters < 1) liters = 1;
    if (gsOwnerCharID[slot] > 0 && gsStock[slot] < liters) liters = gsStock[slot];
    if (liters <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Stok bensin pom ini habis.");
        return 0;
    }
    new cost = liters * gsPricePerLiter[slot];
    pMoney[playerid] = GetPlayerMoney(playerid);
    if (pMoney[playerid] < cost)
    {
        // Isi semampunya uang.
        liters = pMoney[playerid] / gsPricePerLiter[slot];
        if (liters <= 0)
        {
            SendClientMessage(playerid, COLOR_RED, "Uangmu tidak cukup untuk membeli bensin.");
            return 0;
        }
        cost = liters * gsPricePerLiter[slot];
        SendClientMessage(playerid, COLOR_YELLOW, "Uangmu tidak cukup untuk penuh. Tangki diisi semampunya.");
    }
    GivePlayerMoney(playerid, -cost);
    pMoney[playerid] = GetPlayerMoney(playerid);
    vFuel[vslot] += float(liters);
    if (vFuel[vslot] > 100.0) vFuel[vslot] = 100.0;
    Vehicle_SaveSlot(vslot);
    Vehicle_TDShow(playerid, vslot);

    if (gsOwnerCharID[slot] > 0)
    {
        gsProfit[slot] += cost;
        gsStock[slot] -= liters;
        if (gsStock[slot] < 0) gsStock[slot] = 0;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE gasstations SET profit = %d, stock = %d WHERE id = %d",
            gsProfit[slot], gsStock[slot], gsDBID[slot]);
        mysql_tquery(g_SQL, query);
        GasStation_NotifyOwner(slot, pCharName[playerid], liters, cost);
        GasStation_RefreshLabel(slot);
    }

    new uang[32], msg[192];
    FormatRupiah(cost, uang, sizeof(uang));
    format(msg, sizeof(msg), "Kamu mengisi %d liter bensin seharga %s. Bensin kendaraan: %d%%.",
        liters, uang, floatround(vFuel[vslot], floatround_round));
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// SISTEM BENSIN: PENGURANGAN SAAT MENGEMUDI
//================================================================

// GasStation_OnEnterVehicle: dipanggil dari OnPlayerEnterVehicle di file utama.
// Kendaraan pribadi yang bensinnya habis tidak bisa dikendarai.
stock GasStation_OnEnterVehicle(playerid, vehicleid)
{
    new slot = Vehicle_SlotFromVehID(vehicleid);
    if (slot == -1) return 1;
    if (vFuel[slot] <= 0.0)
    {
        RemovePlayerFromVehicle(playerid);
        SendClientMessage(playerid, COLOR_RED, "Bensin kendaraan ini habis! Isi dulu di pom bensin terdekat (/gasstations).");
    }
    return 1;
}

//================================================================
// INFO & DAFTAR
//================================================================

// GasStation_ShowInfoText: teks info pom untuk menu modern (subtitle pakai ~n~).
stock GasStation_ShowInfoText(playerid, slot, dest[], len)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    new harga[32], hargaliter[32], profit[32];
    FormatRupiah(gsPrice[slot], harga, sizeof(harga));
    FormatRupiah(gsPricePerLiter[slot], hargaliter, sizeof(hargaliter));
    FormatRupiah(gsProfit[slot], profit, sizeof(profit));
    format(dest, len,
        "ID: %d~n~Nama: %s~n~Harga Beli: %s~n~Pemilik: %s~n~Harga Bensin: %s/liter~n~Stok: %d liter (maks %d)~n~Keuntungan: %s~n~Harga pemasok: Rp%d/liter",
        gsDBID[slot], gsName[slot], harga, gsOwnerName[slot], hargaliter,
        gsStock[slot], GAS_MAX_STOCK, profit, GAS_SUPPLY_COST);
    return 1;
}

// GasStation_ShowInfo: menu modern kelola pom milik pemain.
stock GasStation_ShowInfo(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    if (gsOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 0;
    }
    pGasSlot[playerid] = slot;
    new profit[32], opts[4][64], title[64];
    FormatRupiah(gsProfit[slot], profit, sizeof(profit));
    format(opts[0], 64, "Info Pom");
    format(opts[1], 64, "Isi Ulang Stok Bensin");
    format(opts[2], 64, "Ambil Keuntungan (%s)", profit);
    format(opts[3], 64, "Jual Pom");
    format(title, sizeof(title), "POM BENSIN: %s", gsName[slot]);
    UI_ShowMenu(playerid, "dialog_GasInfo", title, "Pilih salah satu opsi:", opts, 4);
    return 1;
}

// GasStation_ShowForSale: dialog info pom yang belum ada pemiliknya.
stock GasStation_ShowForSale(playerid, slot)
{
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 0;
    new harga[32], hargaliter[32], msg[384];
    FormatRupiah(gsPrice[slot], harga, sizeof(harga));
    FormatRupiah(gsPricePerLiter[slot], hargaliter, sizeof(hargaliter));
    format(msg, sizeof(msg),
        "Pom bensin ini belum ada pemiliknya.~n~~n~Nama: %s~n~Harga Beli: %s~n~Harga Bensin: %s/liter~n~Stok Awal: %d liter~n~~n~Ketik /buygasstation untuk membeli pom ini.",
        gsName[slot], harga, hargaliter, gsStock[slot]);
    new opts[1][64] = {"Tutup"};
    UI_ShowMenu(playerid, "dialog_GasForSale", "POM DIJUAL", msg, opts, 1);
    return 1;
}

// GasStation_ShowList: menu modern daftar semua pom di server.
stock GasStation_ShowList(playerid)
{
    new opts[MAX_GASSTATION][64], baris[128], status[24], harga[32];
    new count = 0;
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (!gsExists[i]) continue;
        FormatRupiah(gsPricePerLiter[i], harga, sizeof(harga));
        if (gsOwnerCharID[i] > 0) format(status, sizeof(status), "Beroperasi");
        else format(status, sizeof(status), "Dijual");
        format(baris, sizeof(baris), "%s - %s/liter (%s)", gsName[i], harga, status);
        format(opts[count], 64, "%s", baris); // otomatis dipotong jadi 63 char
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada pom bensin di server.");
        return 0;
    }
    UI_ShowMenu(playerid, "dialog_GasList", "DAFTAR POM BENSIN", "Pilih pom bensin untuk melihat detail:", opts, count);
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:GasRefuel - konfirmasi pengisian bensin.
Dialog:GasRefuel(playerid, response, listitem, inputtext[])
{
    if (!response || listitem != 0) return 1; // "Batal" (opsi 1) atau ESC
    GasStation_Refuel(playerid, pGasSlot[playerid]);
    return 1;
}

// Dialog:GasInfo - kelola pom milik pemain.
Dialog:GasInfo(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pGasSlot[playerid];
    if (slot < 0 || slot >= MAX_GASSTATION || !gsExists[slot]) return 1;
    if (gsOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan pom bensinmu.");
        return 1;
    }
    if (listitem == 0)
    {
        new msg[384], opts[1][64];
        GasStation_ShowInfoText(playerid, slot, msg, sizeof(msg));
        format(opts[0], 64, "Kembali");
        UI_ShowMenu(playerid, "dialog_GasInfoBack", "INFO POM", msg, opts, 1);
    }
    else if (listitem == 1)
    {
        new msg[192], biaya[32];
        FormatRupiah(GAS_SUPPLY_COST, biaya, sizeof(biaya));
        format(msg, sizeof(msg),
            "Beli stok bensin dari pemasok (%s/liter).\nStok saat ini: %d liter (maks %d).\n\nKetik jumlah liter yang ingin dibeli:",
            biaya, gsStock[slot], GAS_MAX_STOCK);
        Dialog_Show(playerid, GasBuyStock, DIALOG_STYLE_INPUT, "Isi Ulang Stok", msg, "Beli", "Batal");
    }
    else if (listitem == 2)
    {
        GasStation_Collect(playerid, slot);
    }
    else if (listitem == 3)
    {
        new harga[32], msg[256], opts[2][64];
        FormatRupiah((gsPrice[slot] * GAS_SELL_RATE) / 100, harga, sizeof(harga));
        format(msg, sizeof(msg),
            "Yakin ingin menjual pom \"%s\"?~n~~n~Kamu akan menerima %s (%d%% dari harga beli).",
            gsName[slot], harga, GAS_SELL_RATE);
        format(opts[0], 64, "Jual");
        format(opts[1], 64, "Batal");
        UI_ShowMenu(playerid, "dialog_GasSellConfirm", "JUAL POM", msg, opts, 2);
    }
    return 1;
}

// Dialog:GasInfoBack - kembali ke menu kelola pom setelah melihat info.
Dialog:GasInfoBack(playerid, response, listitem, inputtext[])
{
    GasStation_ShowInfo(playerid, pGasSlot[playerid]);
    return 1;
}

// Dialog:GasBuyStock - input jumlah liter stok dari pemasok.
Dialog:GasBuyStock(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!IsNumeric(inputtext))
    {
        SendClientMessage(playerid, COLOR_RED, "Jumlah liter harus berupa angka.");
        return 1;
    }
    GasStation_BuyStock(playerid, pGasSlot[playerid], strval(inputtext));
    return 1;
}

// Dialog:GasSellConfirm - konfirmasi jual pom.
Dialog:GasSellConfirm(playerid, response, listitem, inputtext[])
{
    if (!response || listitem != 0) return 1; // "Batal" (opsi 1) atau ESC
    GasStation_Sell(playerid, pGasSlot[playerid]);
    return 1;
}

// Dialog:GasForSale - info pom yang dijual (dialog info, abaikan respon).
Dialog:GasForSale(playerid, response, listitem, inputtext[])
{
    return 1;
}

// Dialog:GasList - daftar pom, pilih untuk melihat detail.
Dialog:GasList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new count = 0, slot = -1;
    for (new i = 0; i < MAX_GASSTATION; i++)
    {
        if (!gsExists[i]) continue;
        if (count == listitem)
        {
            slot = i;
            break;
        }
        count++;
    }
    if (slot == -1) return 1;
    pGasListSlot[playerid] = slot;
    new msg[384], opts[1][64];
    GasStation_ShowInfoText(playerid, slot, msg, sizeof(msg));
    format(opts[0], 64, "Kembali");
    UI_ShowMenu(playerid, "dialog_GasListBack", "DETAIL POM BENSIN", msg, opts, 1);
    return 1;
}

// Dialog:GasListBack - kembali ke daftar pom setelah melihat detail.
Dialog:GasListBack(playerid, response, listitem, inputtext[])
{
    GasStation_ShowList(playerid);
    return 1;
}

// Dialog:GasSetPrice - input harga jual bensin per liter.
Dialog:GasSetPrice(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!IsNumeric(inputtext))
    {
        SendClientMessage(playerid, COLOR_RED, "Harga harus berupa angka.");
        return 1;
    }
    GasStation_SetPrice(playerid, pGasSlot[playerid], strval(inputtext));
    return 1;
}

//================================================================
// LOAD
//================================================================

// GasStation_LoadAll: memuat semua pom dari database.
stock GasStation_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT g.id, g.name, g.owner_char_id, IFNULL(c.name, '') AS owner_name, g.price, g.price_per_liter, g.stock, g.profit, g.pos_x, g.pos_y, g.pos_z FROM gasstations g LEFT JOIN characters c ON c.id = g.owner_char_id",
        "OnGasStationsLoaded");
    return 1;
}

//================================================================
// CALLBACK MYSQL & TIMER
//================================================================

// OnGasStationsLoaded: mengisi slot pom dari database lalu spawn pickup+label.
public OnGasStationsLoaded()
{
    new rows = cache_num_rows(), tmp, count = 0;
    for (new i = 0; i < rows && i < MAX_GASSTATION; i++)
    {
        new Float:fx, Float:fy, Float:fz;
        cache_get_value_name_int(i, "id", tmp);            gsDBID[i] = tmp;
        cache_get_value_name(i, "name", gsName[i], sizeof(gsName[]));
        cache_get_value_name_int(i, "owner_char_id", tmp); gsOwnerCharID[i] = tmp;
        cache_get_value_name(i, "owner_name", gsOwnerName[i], sizeof(gsOwnerName[]));
        cache_get_value_name_int(i, "price", tmp);         gsPrice[i] = tmp;
        cache_get_value_name_int(i, "price_per_liter", tmp); gsPricePerLiter[i] = tmp;
        cache_get_value_name_int(i, "stock", tmp);         gsStock[i] = tmp;
        cache_get_value_name_int(i, "profit", tmp);        gsProfit[i] = tmp;
        cache_get_value_name_float(i, "pos_x", fx);        gsPosX[i] = fx;
        cache_get_value_name_float(i, "pos_y", fy);        gsPosY[i] = fy;
        cache_get_value_name_float(i, "pos_z", fz);        gsPosZ[i] = fz;
        gsExists[i] = 1;
        GasStation_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d pom bensin dinamis dimuat.", count);
    print(msg);
    return 1;
}

// OnGasStationCreated: menyimpan id database hasil INSERT pom baru.
public OnGasStationCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pGasNewSlot[playerid];
    if (slot < 0 || slot >= MAX_GASSTATION) return 1;
    new id = cache_insert_id();
    gsDBID[slot] = id;
    format(gsName[slot], sizeof(gsName[]), "%s", pGasNewName[playerid]);
    gsPrice[slot] = pGasNewPrice[playerid];
    gsPricePerLiter[slot] = GAS_DEFAULT_PPL;
    gsStock[slot] = GAS_START_STOCK;
    gsProfit[slot] = 0;
    gsOwnerCharID[slot] = 0;
    gsOwnerName[slot][0] = EOS;
    GetPlayerPos(playerid, gsPosX[slot], gsPosY[slot], gsPosZ[slot]);
    gsExists[slot] = 1;
    GasStation_Spawn(slot);
    new harga[32], msg[256];
    FormatRupiah(gsPrice[slot], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "[POM] Pom bensin \"%s\" (ID %d) dibuat di lokasimu. Harga: %s.",
        gsName[slot], id, harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// FuelTick: dipanggil tiap 30 detik via SetTimer di OnGameModeInit.
// Bensin kendaraan pribadi berkurang saat dikendarai.
public FuelTick()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (!IsPlayerConnected(i)) continue;
        if (!Society_PlayerData[i][sPLogged] || Society_PlayerData[i][sPCharID] <= 0) continue;
        if (GetPlayerState(i) != PLAYER_STATE_DRIVER) continue;
        new vehicleid = GetPlayerVehicleID(i);
        new slot = Vehicle_SlotFromVehID(vehicleid);
        if (slot == -1) continue;

        // Kurangi bensin lebih cepat saat melaju, pelan saat diam.
        new Float:vx, Float:vy, Float:vz;
        GetVehicleVelocity(vehicleid, vx, vy, vz);
        new Float:speed = floatsqroot(vx * vx + vy * vy + vz * vz) * 180.0;
        if (speed > 10.0) vFuel[slot] -= FUEL_DRAIN;
        else vFuel[slot] -= FUEL_DRAIN_IDLE;

        if (vFuel[slot] <= 0.0)
        {
            vFuel[slot] = 0.0;
            Vehicle_SaveSlot(slot);
            RemovePlayerFromVehicle(i);
            Vehicle_TDHide(i);
            SendClientMessage(i, COLOR_RED, "Bensin kendaraanmu habis! Isi di pom bensin terdekat (/gasstations).");
            continue;
        }
        Vehicle_SaveSlot(slot);
        Vehicle_TDShow(i, slot);
    }
    return 1;
}

//================================================================
// COMMAND (dipanggil dari OnPlayerCommandText di file utama)
//================================================================

// GasStation_CmdCreate: /creategasstation [nama] [harga] - admin level 3+.
stock GasStation_CmdCreate(playerid, const cmdtext[], idx)
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
        SendClientMessage(playerid, COLOR_GREY, "Gunakan: /creategasstation [nama] [harga]");
        SendClientMessage(playerid, COLOR_GREY, "Contoh: /creategasstation Pom_Surya 200000000 (spasi diganti _)");
        return 1;
    }
    if (strlen(snama) < 3)
    {
        SendClientMessage(playerid, COLOR_RED, "Nama pom minimal 3 karakter.");
        return 1;
    }
    if (!IsNumeric(sharga))
    {
        SendClientMessage(playerid, COLOR_RED, "Harga harus berupa angka.");
        return 1;
    }
    new price = strval(sharga);
    if (price < 10000000 || price > GAS_MAX_PRICE)
    {
        SendClientMessage(playerid, COLOR_RED, "Harga pom harus Rp10.000.000 - Rp500.000.000.");
        return 1;
    }
    for (new i = 0; snama[i] != EOS; i++)
    {
        if (snama[i] == '_') snama[i] = ' ';
    }
    GasStation_Create(playerid, snama, price);
    return 1;
}

// GasStation_CmdBuy: /buygasstation - membeli pom di dekatmu (yang dijual).
stock GasStation_CmdBuy(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_Nearest(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensin di dekatmu.");
        return 1;
    }
    GasStation_Buy(playerid, slot);
    return 1;
}

// GasStation_CmdInfo: /gasinfo - dialog kelola pom milikmu.
stock GasStation_CmdInfo(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensinmu di dekat sini.");
        return 1;
    }
    GasStation_ShowInfo(playerid, slot);
    return 1;
}

// GasStation_CmdSetPrice: /setfuelprice - atur harga bensin per liter (pemilik).
stock GasStation_CmdSetPrice(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensinmu di dekat sini.");
        return 1;
    }
    pGasSlot[playerid] = slot;
    new harga[32], msg[256];
    FormatRupiah(gsPricePerLiter[slot], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Harga bensin saat ini: %s/liter.\n\nKetik harga baru per liter (Rp1.000 - Rp50.000):",
        harga);
    Dialog_Show(playerid, GasSetPrice, DIALOG_STYLE_INPUT, "Harga Bensin", msg, "Ubah", "Batal");
    return 1;
}

// GasStation_CmdRefuel: /refuel - isi bensin kendaraan di pom terdekat.
stock GasStation_CmdRefuel(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_Nearest(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensin di dekatmu. Cari daftar pom dengan /gasstations.");
        return 1;
    }
    GasStation_ShowRefuel(playerid, slot);
    return 1;
}

// GasStation_CmdWithdraw: /gaswithdraw - mengambil keuntungan pom milikmu.
stock GasStation_CmdWithdraw(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensinmu di dekat sini.");
        return 1;
    }
    GasStation_Collect(playerid, slot);
    return 1;
}

// GasStation_CmdSell: /sellgasstation - menjual kembali pommu (70%).
stock GasStation_CmdSell(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = GasStation_OwnedNear(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pom bensinmu di dekat sini.");
        return 1;
    }
    pGasSlot[playerid] = slot;
    new harga[32], msg[256], opts[2][64];
    FormatRupiah((gsPrice[slot] * GAS_SELL_RATE) / 100, harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Yakin ingin menjual pom \"%s\"?~n~~n~Kamu akan menerima %s (%d%% dari harga beli).",
        gsName[slot], harga, GAS_SELL_RATE);
    format(opts[0], 64, "Jual");
    format(opts[1], 64, "Batal");
    UI_ShowMenu(playerid, "dialog_GasSellConfirm", "JUAL POM", msg, opts, 2);
    return 1;
}

// GasStation_CmdList: /gasstations - daftar semua pom di server.
stock GasStation_CmdList(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged])
    {
        SendClientMessage(playerid, COLOR_RED, "Anda harus login terlebih dahulu.");
        return 1;
    }
    GasStation_ShowList(playerid);
    return 1;
}
