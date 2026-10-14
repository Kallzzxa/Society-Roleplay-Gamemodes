//================================================================
// Society Roleplay - Vehicle_System
// Kendaraan pribadi dinamis: dibeli pemain lewat /buyvehicle,
// tersimpan di tabel player_vehicles, spawn otomatis saat karakter
// load dan despawn saat pemain disconnect. Maksimal 2 kendaraan
// per karakter. Textdraw info kecil tampil saat mengemudi.
// Di-include dari gamemodes/Society_Main.pwn (setelah bagian UTIL,
// karena memakai pCharName dan stock util dari file utama).
//================================================================

#if defined _vehicle_system_included
    #endinput
#endif
#define _vehicle_system_included

//==== KONSTANTA ====
#define MAX_PVEH 200           // slot kendaraan pribadi di server
#define MAX_VEH_PER_CHAR 2     // batas kendaraan per karakter
#define VEH_INTERACT_RANGE 6.0 // jarak interaksi /vlock
#define VEH_CAT_COUNT 16       // jumlah model di katalog jual

// Katalog kendaraan yang bisa dibeli (model, harga, nama).
new g_VehCatModel[VEH_CAT_COUNT] =
{
    400, 402, 405, 411, 415, 418, 420, 426,
    436, 445, 461, 468, 489, 496, 507, 522
};
new g_VehCatPrice[VEH_CAT_COUNT] =
{
    85000000, 120000000, 150000000, 450000000,
    380000000, 60000000, 95000000, 140000000,
    70000000, 110000000, 75000000, 45000000,
    130000000, 55000000, 160000000, 180000000
};
new g_VehCatName[VEH_CAT_COUNT][32] =
{
    "Landstalker", "Buffalo", "Sentinel", "Infernus",
    "Cheetah", "Moonbeam", "Taxi", "Premier",
    "Previon", "Admiral", "PCJ-600", "Sanchez",
    "Rancher", "Blista Compact", "Elegant", "NRG-500"
};

//==== DATA KENDARAAN ====
new vExists[MAX_PVEH];              // 1 jika slot terisi
new vDBID[MAX_PVEH];                // id baris di tabel player_vehicles
new vOwnerCharID[MAX_PVEH];         // id karakter pemilik
new vOwnerName[MAX_PVEH][24];       // nama karakter pemilik
new vModel[MAX_PVEH];               // model id kendaraan
new vColor1[MAX_PVEH];              // warna 1
new vColor2[MAX_PVEH];              // warna 2
new vPlate[MAX_PVEH][16];           // nomor polisi
new vLocked[MAX_PVEH];              // 1 = terkunci
new Float:vFuel[MAX_PVEH];          // 0-100 (dipakai penuh oleh Sistem Bensin nanti)
new Float:vPosX[MAX_PVEH];          // posisi parkir terakhir
new Float:vPosY[MAX_PVEH];
new Float:vPosZ[MAX_PVEH];
new Float:vAngle[MAX_PVEH];         // arah hadap saat parkir
new vVehID[MAX_PVEH];               // id kendaraan di server (INVALID_VEHICLE_ID jika belum spawn)
new bool:vSpawned[MAX_PVEH];        // true jika sedang ter-spawn di dunia
new vGarageID[MAX_PVEH];            // id DB garasi tempat kendaraan dititipkan (0 = di jalanan)

// Data sementara per pemain.
new pVehBuyCat[MAX_PLAYERS];        // indeks katalog yang dipilih di dialog beli
new pVehMenuSlot[MAX_PLAYERS];      // slot kendaraan yang sedang dikelola
new PlayerText:g_VehTD[MAX_PLAYERS] = {PlayerText:INVALID_TEXT_DRAW, ...};

//==== FORWARD ====
forward OnVehiclesLoaded();
forward OnVehicleCreated(playerid, slot);

//================================================================
// UTIL KENDARAAN
//================================================================

// Vehicle_FreeSlot: mencari slot kendaraan kosong, -1 jika penuh.
stock Vehicle_FreeSlot()
{
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i]) return i;
    }
    return -1;
}

// Vehicle_CountOwned: jumlah kendaraan milik satu karakter.
stock Vehicle_CountOwned(charid)
{
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (vExists[i] && vOwnerCharID[i] == charid) count++;
    }
    return count;
}

// Vehicle_CatName: nama katalog dari model id, "Tidak Dikenal" jika tak ada.
stock Vehicle_CatName(model, dest[], len)
{
    for (new i = 0; i < VEH_CAT_COUNT; i++)
    {
        if (g_VehCatModel[i] == model)
        {
            format(dest, len, "%s", g_VehCatName[i]);
            return 1;
        }
    }
    format(dest, len, "Tidak Dikenal");
    return 0;
}

// Vehicle_SlotFromVehID: mencari slot dari id kendaraan server, -1 jika bukan milik sistem.
stock Vehicle_SlotFromVehID(vehicleid)
{
    if (vehicleid == INVALID_VEHICLE_ID) return -1;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (vExists[i] && vSpawned[i] && vVehID[i] == vehicleid) return i;
    }
    return -1;
}

// Vehicle_OwnedNear: slot kendaraan MILIK pemain terdekat (VEH_INTERACT_RANGE), -1 jika tidak ada.
stock Vehicle_OwnedNear(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    new best = -1;
    new Float:bestdist = VEH_INTERACT_RANGE;
    new Float:px, Float:py, Float:pz, Float:vx, Float:vy, Float:vz;
    GetPlayerPos(playerid, px, py, pz);
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || !vSpawned[i] || vOwnerCharID[i] != charid) continue;
        GetVehiclePos(vVehID[i], vx, vy, vz);
        new Float:d = floatsqroot((px - vx) * (px - vx) + (py - vy) * (py - vy) + (pz - vz) * (pz - vz));
        if (d < bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Vehicle_MakePlate: membuat nomor polisi unik "SRP XXXX".
stock Vehicle_MakePlate(dest[], len)
{
    new used = 1;
    while (used)
    {
        used = 0;
        format(dest, len, "SRP %04d", 1000 + random(9000));
        for (new i = 0; i < MAX_PVEH; i++)
        {
            if (vExists[i] && strcmp(vPlate[i], dest, true) == 0)
            {
                used = 1;
                break;
            }
        }
    }
    return 1;
}

//================================================================
// SPAWN / DESPAWN / SIMPAN
//================================================================

// Vehicle_Spawn: memunculkan satu kendaraan dari slot ke dunia.
// Kendaraan yang dititipkan di garasi tidak boleh ter-spawn.
stock Vehicle_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 0;
    if (vGarageID[slot] > 0) return 0;
    if (vSpawned[slot]) return 1;
    vVehID[slot] = CreateVehicle(vModel[slot],
        vPosX[slot], vPosY[slot], vPosZ[slot], vAngle[slot],
        vColor1[slot], vColor2[slot], -1);
    if (vVehID[slot] == INVALID_VEHICLE_ID) return 0;
    SetVehicleNumberPlate(vVehID[slot], vPlate[slot]);
    SetVehicleToRespawn(vVehID[slot]);
    vSpawned[slot] = true;
    return 1;
}

// Vehicle_Destroy: menghapus kendaraan dari dunia (data slot tetap ada).
stock Vehicle_Destroy(slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 0;
    if (vSpawned[slot])
    {
        DestroyVehicle(vVehID[slot]);
        vVehID[slot] = INVALID_VEHICLE_ID;
        vSpawned[slot] = false;
    }
    return 1;
}

// Vehicle_SaveSlot: menyimpan posisi, sudut, bensin & kunci satu slot ke database.
stock Vehicle_SaveSlot(slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    if (vSpawned[slot])
    {
        GetVehiclePos(vVehID[slot], vPosX[slot], vPosY[slot], vPosZ[slot]);
        GetVehicleZAngle(vVehID[slot], vAngle[slot]);
    }
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE player_vehicles SET pos_x = %f, pos_y = %f, pos_z = %f, angle = %f, fuel = %f, locked = %d, garage_id = %d WHERE id = %d",
        vPosX[slot], vPosY[slot], vPosZ[slot], vAngle[slot], vFuel[slot], vLocked[slot], vGarageID[slot], vDBID[slot]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Vehicle_LoadAll: memuat semua kendaraan dari database lalu spawn.
stock Vehicle_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL, "SELECT * FROM player_vehicles", "OnVehiclesLoaded");
    return 1;
}

// Vehicle_OnCharLoad: spawn ulang kendaraan milik karakter yang baru load.
stock Vehicle_OnCharLoad(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (vExists[i] && !vSpawned[i] && vOwnerCharID[i] == charid)
        {
            Vehicle_Spawn(i);
        }
    }
    Vehicle_TDCreate(playerid);
    return 1;
}

// Vehicle_IsOccupied: true jika ada pemain di dalam kendaraan slot.
stock Vehicle_IsOccupied(slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot] || !vSpawned[slot]) return 0;
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && GetPlayerVehicleID(i) == vVehID[slot]) return 1;
    }
    return 0;
}

// Vehicle_OnDisconnect: simpan posisi lalu despawn kendaraan milik pemain
// (hanya yang kosong; yang sedang dipakai orang lain dibiarkan dulu).
stock Vehicle_OnDisconnect(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vSpawned[i])
        {
            Vehicle_SaveSlot(i);
            if (!Vehicle_IsOccupied(i)) Vehicle_Destroy(i);
        }
    }
    Vehicle_TDDestroy(playerid);
    return 1;
}

//================================================================
// TEXTDRAW INFO KENDARAAN (saat mengemudi)
//================================================================

// Vehicle_TDCreate: membuat PlayerTextDraw info kendaraan untuk pemain.
stock Vehicle_TDCreate(playerid)
{
    if (UI_IsCef(playerid)) return 1; // info kendaraan dirender via WebView
    Vehicle_TDDestroy(playerid);
    g_VehTD[playerid] = CreatePlayerTextDraw(playerid, 545.0, 400.0, "_");
    PlayerTextDrawFont(playerid, g_VehTD[playerid], 1);
    PlayerTextDrawLetterSize(playerid, g_VehTD[playerid], 0.28, 1.1);
    PlayerTextDrawAlignment(playerid, g_VehTD[playerid], 3);
    PlayerTextDrawColor(playerid, g_VehTD[playerid], 0xFFFFFFFF);
    PlayerTextDrawSetOutline(playerid, g_VehTD[playerid], 1);
    PlayerTextDrawSetProportional(playerid, g_VehTD[playerid], 1);
    return 1;
}

// Vehicle_TDDestroy: menghapus PlayerTextDraw info kendaraan.
stock Vehicle_TDDestroy(playerid)
{
    if (g_VehTD[playerid] != PlayerText:INVALID_TEXT_DRAW)
    {
        PlayerTextDrawDestroy(playerid, g_VehTD[playerid]);
        g_VehTD[playerid] = PlayerText:INVALID_TEXT_DRAW;
    }
    return 1;
}

// Vehicle_TDShow: menampilkan info kendaraan yang sedang dikemudikan.
stock Vehicle_TDShow(playerid, slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 0;
    new nama[32], kunci[16], text[128];
    Vehicle_CatName(vModel[slot], nama, sizeof(nama));
    if (vLocked[slot]) format(kunci, sizeof(kunci), "Terkunci");
    else format(kunci, sizeof(kunci), "Terbuka");
    if (UI_IsCef(playerid))
    {
        return UI_HudVehicle(playerid, vPlate[slot], nama, kunci,
            floatround(vFuel[slot], floatround_round));
    }
    format(text, sizeof(text), "[%s]~n~%s | %s~n~Bensin: %d%%",
        vPlate[slot], nama, kunci, floatround(vFuel[slot], floatround_round));
    PlayerTextDrawSetString(playerid, g_VehTD[playerid], text);
    PlayerTextDrawShow(playerid, g_VehTD[playerid]);
    return 1;
}

// Vehicle_TDHide: menyembunyikan info kendaraan.
stock Vehicle_TDHide(playerid)
{
    if (UI_IsCef(playerid)) return UI_HudVehicleHide(playerid);
    PlayerTextDrawHide(playerid, g_VehTD[playerid]);
    return 1;
}

// Vehicle_OnStateChange: dipanggil dari OnPlayerStateChange di file utama.
stock Vehicle_OnStateChange(playerid, newstate, oldstate)
{
    if (newstate == PLAYER_STATE_DRIVER)
    {
        new slot = Vehicle_SlotFromVehID(GetPlayerVehicleID(playerid));
        if (slot != -1) Vehicle_TDShow(playerid, slot);
    }
    else if (oldstate == PLAYER_STATE_DRIVER)
    {
        Vehicle_TDHide(playerid);
    }
    return 1;
}

// Vehicle_OnEnterVehicle: dipanggil dari OnPlayerEnterVehicle di file utama.
// Kendaraan terkunci tidak bisa dimasuki selain oleh pemiliknya.
stock Vehicle_OnEnterVehicle(playerid, vehicleid, ispassenger)
{
    new slot = Vehicle_SlotFromVehID(vehicleid);
    if (slot == -1) return 1;
    if (vLocked[slot] && vOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        RemovePlayerFromVehicle(playerid);
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini terkunci.");
    }
    return 1;
}

//================================================================
// PEMBELIAN
//================================================================

// Vehicle_BuildBuyList: menyusun daftar katalog untuk dialog /buyvehicle.
stock Vehicle_BuildBuyList(dest[], len)
{
    dest[0] = EOS;
    new harga[32], baris[96];
    for (new i = 0; i < VEH_CAT_COUNT; i++)
    {
        FormatRupiah(g_VehCatPrice[i], harga, sizeof(harga));
        format(baris, sizeof(baris), "%s - %s", g_VehCatName[i], harga);
        if (i > 0) strcat(dest, "\n", len);
        strcat(dest, baris, len);
    }
    return 1;
}

// Vehicle_Buy: membeli kendaraan dari katalog (dipanggil setelah konfirmasi dialog).
stock Vehicle_Buy(playerid, catidx)
{
    if (catidx < 0 || catidx >= VEH_CAT_COUNT) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 0;
    }
    if (Vehicle_CountOwned(charid) >= MAX_VEH_PER_CHAR)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu sudah punya 2 kendaraan (maksimal).");
        return 0;
    }
    new slot = Vehicle_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot kendaraan server penuh.");
        return 0;
    }
    pMoney[playerid] = GetPlayerMoney(playerid);
    if (pMoney[playerid] < g_VehCatPrice[catidx])
    {
        SendClientMessage(playerid, COLOR_RED, "Uangmu tidak cukup untuk membeli kendaraan ini.");
        return 0;
    }
    new Float:px, Float:py, Float:pz, Float:pa;
    GetPlayerPos(playerid, px, py, pz);
    GetPlayerFacingAngle(playerid, pa);
    px += 3.0 * floatsin(-pa, degrees);
    py += 3.0 * floatcos(-pa, degrees);

    vExists[slot] = 1;
    vDBID[slot] = 0; // diisi dari cache_insert_id di OnVehicleCreated
    vOwnerCharID[slot] = charid;
    format(vOwnerName[slot], sizeof(vOwnerName[]), "%s", pCharName[playerid]);
    vModel[slot] = g_VehCatModel[catidx];
    vColor1[slot] = random(126);
    vColor2[slot] = random(126);
    Vehicle_MakePlate(vPlate[slot], sizeof(vPlate[]));
    vLocked[slot] = 0;
    vFuel[slot] = 100.0;
    vPosX[slot] = px;
    vPosY[slot] = py;
    vPosZ[slot] = pz;
    vAngle[slot] = pa;
    vVehID[slot] = INVALID_VEHICLE_ID;
    vSpawned[slot] = false;
    vGarageID[slot] = 0; // kendaraan baru langsung ada di jalanan
    Vehicle_Spawn(slot);

    GivePlayerMoney(playerid, -g_VehCatPrice[catidx]);
    pMoney[playerid] = GetPlayerMoney(playerid);

    new query[320];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO player_vehicles (char_id, model, pos_x, pos_y, pos_z, angle, color1, color2, plate, locked, fuel) VALUES (%d, %d, %f, %f, %f, %f, %d, %d, '%e', 0, 100.0)",
        charid, vModel[slot], px, py, pz, pa, vColor1[slot], vColor2[slot], vPlate[slot]);
    mysql_tquery(g_SQL, query, "OnVehicleCreated", "dd", playerid, slot);

    new harga[32], msg[160];
    FormatRupiah(g_VehCatPrice[catidx], harga, sizeof(harga));
    format(msg, sizeof(msg), "Selamat! Kamu membeli %s (%s) seharga %s.", g_VehCatName[catidx], vPlate[slot], harga);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Kelola kendaraanmu dengan /vlist. Kunci dengan /vlock, simpan posisi dengan /vpark.");
    PutPlayerInVehicle(playerid, vVehID[slot], 0);
    return 1;
}

// Vehicle_GiveFree: memberikan kendaraan gratis (mis. starterpack) ke pemain.
stock Vehicle_GiveFree(playerid, model)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return 0;
    if (Vehicle_CountOwned(charid) >= MAX_VEH_PER_CHAR)
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Slot kendaraanmu penuh, kendaraan gratis tidak dapat diberikan.");
        return 0;
    }
    new slot = Vehicle_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot kendaraan server penuh.");
        return 0;
    }
    new Float:px, Float:py, Float:pz, Float:pa;
    GetPlayerPos(playerid, px, py, pz);
    GetPlayerFacingAngle(playerid, pa);
    px += 3.0 * floatsin(-pa, degrees);
    py += 3.0 * floatcos(-pa, degrees);

    vExists[slot] = 1;
    vDBID[slot] = 0; // diisi dari cache_insert_id di OnVehicleCreated
    vOwnerCharID[slot] = charid;
    format(vOwnerName[slot], sizeof(vOwnerName[]), "%s", pCharName[playerid]);
    vModel[slot] = model;
    vColor1[slot] = random(126);
    vColor2[slot] = random(126);
    Vehicle_MakePlate(vPlate[slot], sizeof(vPlate[]));
    vLocked[slot] = 0;
    vFuel[slot] = 100.0;
    vPosX[slot] = px;
    vPosY[slot] = py;
    vPosZ[slot] = pz;
    vAngle[slot] = pa;
    vVehID[slot] = INVALID_VEHICLE_ID;
    vSpawned[slot] = false;
    vGarageID[slot] = 0;
    Vehicle_Spawn(slot);

    new query[320];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO player_vehicles (char_id, model, pos_x, pos_y, pos_z, angle, color1, color2, plate, locked, fuel) VALUES (%d, %d, %f, %f, %f, %f, %d, %d, '%e', 0, 100.0)",
        charid, model, px, py, pz, pa, vColor1[slot], vColor2[slot], vPlate[slot]);
    mysql_tquery(g_SQL, query, "OnVehicleCreated", "dd", playerid, slot);

    new nama[32], msg[160];
    Vehicle_CatName(model, nama, sizeof(nama));
    format(msg, sizeof(msg), "Kamu mendapatkan %s (%s) gratis!", nama, vPlate[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    PutPlayerInVehicle(playerid, vVehID[slot], 0);
    return 1;
}

// Vehicle_ToggleLock: mengunci/membuka kendaraan milik pemain.
stock Vehicle_ToggleLock(playerid, slot)
{
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 0;
    if (vOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 0;
    }
    vLocked[slot] = !vLocked[slot];
    Vehicle_SaveSlot(slot);
    if (vLocked[slot])
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Kendaraanmu sekarang TERKUNCI.");
    }
    else
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Kendaraanmu sekarang TERBUKA.");
    }
    return 1;
}

// Vehicle_Park: menyimpan posisi parkir kendaraan yang sedang dikemudikan.
stock Vehicle_Park(playerid)
{
    if (!IsPlayerInAnyVehicle(playerid) || GetPlayerState(playerid) != PLAYER_STATE_DRIVER)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu harus menjadi pengemudi kendaraanmu.");
        return 0;
    }
    new slot = Vehicle_SlotFromVehID(GetPlayerVehicleID(playerid));
    if (slot == -1 || vOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 0;
    }
    Vehicle_SaveSlot(slot);
    SendClientMessage(playerid, COLOR_GREEN, "Posisi kendaraan tersimpan. Ia akan muncul di sini lagi.");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:VehBuy - daftar kendaraan yang bisa dibeli.
Dialog:VehBuy(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (listitem < 0 || listitem >= VEH_CAT_COUNT) return 1;
    pVehBuyCat[playerid] = listitem;
    new harga[32], msg[256];
    FormatRupiah(g_VehCatPrice[listitem], harga, sizeof(harga));
    format(msg, sizeof(msg),
        "Kamu akan membeli:\n\n%s\nHarga: %s\n\nKendaraan akan muncul di depanmu.",
        g_VehCatName[listitem], harga);
    Dialog_Show(playerid, VehBuyConfirm, DIALOG_STYLE_MSGBOX, "Beli Kendaraan", msg, "Beli", "Batal");
    return 1;
}

// Dialog:VehBuyConfirm - konfirmasi sebelum uang dipotong.
Dialog:VehBuyConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    Vehicle_Buy(playerid, pVehBuyCat[playerid]);
    return 1;
}

// Dialog:VehList - daftar kendaraan milik pemain.
Dialog:VehList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new charid = Society_PlayerData[playerid][sPCharID];
    new count = 0, slot = -1;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (vExists[i] && vOwnerCharID[i] == charid)
        {
            if (count == listitem)
            {
                slot = i;
                break;
            }
            count++;
        }
    }
    if (slot == -1) return 1;
    pVehMenuSlot[playerid] = slot;
    new nama[32];
    Vehicle_CatName(vModel[slot], nama, sizeof(nama));
    Dialog_Show(playerid, VehManage, DIALOG_STYLE_LIST, nama,
        "Lihat Info\nKunci/Buka\nLacak Lokasi", "Pilih", "Kembali");
    return 1;
}

// Dialog:VehManage - kelola satu kendaraan: info, kunci/buka, lacak.
Dialog:VehManage(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Vehicle_ShowList(playerid);
        return 1;
    }
    new slot = pVehMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 1;
    if (vOwnerCharID[slot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 1;
    }
    if (listitem == 0)
    {
        new nama[32], kunci[16], msg[320];
        Vehicle_CatName(vModel[slot], nama, sizeof(nama));
        if (vLocked[slot]) format(kunci, sizeof(kunci), "Terkunci");
        else format(kunci, sizeof(kunci), "Terbuka");
        format(msg, sizeof(msg),
            "Model: %s (ID %d)\nPlat: %s\nPemilik: %s\nStatus: %s\nBensin: %d%%",
            nama, vModel[slot], vPlate[slot], vOwnerName[slot], kunci,
            floatround(vFuel[slot], floatround_round));
        Dialog_Show(playerid, VehInfoBack, DIALOG_STYLE_MSGBOX, "Info Kendaraan", msg, "Kembali", "");
    }
    else if (listitem == 1)
    {
        Vehicle_ToggleLock(playerid, slot);
    }
    else if (listitem == 2)
    {
        if (vGarageID[slot] > 0)
        {
            SendClientMessage(playerid, COLOR_YELLOW, "Kendaraan ini tersimpan di garasi. Ambil dengan /garage di garasi tersebut.");
        }
        else if (vSpawned[slot])
        {
            SetPlayerCheckpoint(playerid, vPosX[slot], vPosY[slot], vPosZ[slot], 4.0);
            SendClientMessage(playerid, COLOR_YELLOW, "Lokasi kendaraanmu ditandai di peta (checkpoint merah).");
        }
        else
        {
            SendClientMessage(playerid, COLOR_RED, "Kendaraanmu sedang tidak aktif di dunia.");
        }
    }
    return 1;
}

// Dialog:VehInfoBack - kembali ke daftar kendaraan setelah melihat info.
Dialog:VehInfoBack(playerid, response, listitem, inputtext[])
{
    Vehicle_ShowList(playerid);
    return 1;
}

// Vehicle_ShowList: menampilkan dialog daftar kendaraan milik pemain.
stock Vehicle_ShowList(playerid)
{
    new charid = Society_PlayerData[playerid][sPCharID];
    new list[512], nama[32], kunci[16], baris[96];
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        Vehicle_CatName(vModel[i], nama, sizeof(nama));
        if (vGarageID[i] > 0) format(kunci, sizeof(kunci), "Di Garasi");
        else if (vLocked[i]) format(kunci, sizeof(kunci), "Terkunci");
        else format(kunci, sizeof(kunci), "Terbuka");
        format(baris, sizeof(baris), "%s (%s) - %s", nama, vPlate[i], kunci);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu belum punya kendaraan. Beli dulu dengan /buyvehicle.");
        return 0;
    }
    Dialog_Show(playerid, VehList, DIALOG_STYLE_LIST, "Kendaraanku", list, "Pilih", "Tutup");
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnVehiclesLoaded: mengisi slot kendaraan dari database lalu spawn.
public OnVehiclesLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_PVEH; i++)
    {
        cache_get_value_name_int(i, "id", tmp);            vDBID[i] = tmp;
        cache_get_value_name_int(i, "char_id", tmp);       vOwnerCharID[i] = tmp;
        cache_get_value_name_int(i, "model", tmp);         vModel[i] = tmp;
        cache_get_value_name_float(i, "pos_x", ftmp);      vPosX[i] = ftmp;
        cache_get_value_name_float(i, "pos_y", ftmp);      vPosY[i] = ftmp;
        cache_get_value_name_float(i, "pos_z", ftmp);      vPosZ[i] = ftmp;
        cache_get_value_name_float(i, "angle", ftmp);      vAngle[i] = ftmp;
        cache_get_value_name_int(i, "color1", tmp);        vColor1[i] = tmp;
        cache_get_value_name_int(i, "color2", tmp);        vColor2[i] = tmp;
        cache_get_value_name(i, "plate", vPlate[i], sizeof(vPlate[]));
        cache_get_value_name_int(i, "locked", tmp);        vLocked[i] = tmp;
        cache_get_value_name_float(i, "fuel", ftmp);       vFuel[i] = ftmp;
        cache_get_value_name_int(i, "garage_id", tmp);     vGarageID[i] = tmp;
        vOwnerName[i][0] = EOS;
        vVehID[i] = INVALID_VEHICLE_ID;
        vSpawned[i] = false;
        vExists[i] = 1;
        Vehicle_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d kendaraan pribadi dimuat.", count);
    print(msg);
    return 1;
}

// OnVehicleCreated: menyimpan id database hasil INSERT kendaraan baru.
public OnVehicleCreated(playerid, slot)
{
    if (!IsPlayerConnected(playerid)) return 1;
    if (slot < 0 || slot >= MAX_PVEH || !vExists[slot]) return 1;
    vDBID[slot] = cache_insert_id();
    return 1;
}
