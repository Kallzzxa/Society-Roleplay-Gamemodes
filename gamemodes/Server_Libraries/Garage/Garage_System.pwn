//================================================================
// Society Roleplay - Garage_System
// Garasi kota dinamis: tempat penitipan kendaraan pribadi.
// Admin membuat garasi di sebuah lokasi (pickup + label 3D).
// Pemain di dekat garasi mengetik /garage lalu bisa:
//   - Simpan Kendaraan: kendaraan pribadi miliknya yang sedang
//     ter-spawn di dekat garasi di-despawn dan tercatat tersimpan
//     di garasi itu (kolom player_vehicles.garage_id). Dikenakan
//     biaya titip sekali per simpan.
//   - Ambil Kendaraan: kendaraan yang tersimpan di garasi ini
//     di-spawn kembali di depan garasi dan pemain langsung
//     dimasukkan ke kursi sopir.
// Solusi parkir saat slot jalanan penuh: kendaraan yang tersimpan
// tidak muncul di dunia sampai diambil lagi, dan tidak ikut
// ter-spawn saat karakter load. Tersimpan di tabel garages.
// Di-include dari gamemodes/Society_Main.pwn (setelah modul
// Vehicle, karena memakai data kendaraan vGarageID).
//================================================================

#if defined _garage_system_included
    #endinput
#endif
#define _garage_system_included

//==== KONSTANTA ====
#define MAX_GARAGE 50            // slot garasi di server
#define GARAGE_RANGE 5.0         // jarak interaksi /garage dari pickup
#define GARAGE_VEH_RANGE 15.0    // kendaraan harus sedekat ini dari garasi agar bisa dititipkan
#define GARAGE_MAX_STORED 20     // maks kendaraan tersimpan per garasi
#define GARAGE_MAX_FEE 500000   // biaya titip tertinggi saat /creategarage
#define GARAGE_TRANSFER_FEE 100000 // biaya transfer kendaraan antar garkot

//==== DATA GARASI ====
new gExists[MAX_GARAGE];         // 1 jika slot terisi
new gDBID[MAX_GARAGE];           // id baris di tabel garages
new gName[MAX_GARAGE][32];       // nama garasi
new gFee[MAX_GARAGE];            // biaya titip per kendaraan (dibayar saat menyimpan)
new Float:gPosX[MAX_GARAGE];
new Float:gPosY[MAX_GARAGE];
new Float:gPosZ[MAX_GARAGE];
new gPickup[MAX_GARAGE];         // id pickup
new Text3D:gLabel[MAX_GARAGE];   // label 3D
new bool:gLabelOn[MAX_GARAGE];   // true jika label sedang tampil

// Data sementara per pemain.
new pGarageSlot[MAX_PLAYERS];    // slot garasi yang sedang dipakai di /garage
new pGarageVehSlot[MAX_PLAYERS]; // slot kendaraan yang dipilih untuk dititipkan
new pGarageName[MAX_PLAYERS][32]; // nama garasi yang sedang dibuat admin
new pGarageFee[MAX_PLAYERS];     // biaya titip garasi yang sedang dibuat admin
new pGarageNewSlot[MAX_PLAYERS]; // slot garasi baru yang menunggu callback INSERT
new pGarageTarget[MAX_PLAYERS];  // slot garasi tujuan transfer kendaraan

//==== FORWARD ====
forward OnGaragesLoaded();
forward OnGarageCreated(playerid);

//================================================================
// UTIL GARASI
//================================================================

// Garage_FreeSlot: mencari slot garasi kosong, -1 jika penuh.
stock Garage_FreeSlot()
{
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (!gExists[i]) return i;
    }
    return -1;
}

// Garage_StoredCount: jumlah kendaraan yang tersimpan di satu garasi.
stock Garage_StoredCount(slot)
{
    if (slot < 0 || slot >= MAX_GARAGE || !gExists[slot]) return 0;
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (vExists[i] && vGarageID[i] == gDBID[slot]) count++;
    }
    return count;
}

// Garage_RefreshLabel: menggambar ulang label 3D garasi.
stock Garage_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_GARAGE || !gExists[slot]) return 0;
    if (gLabelOn[slot])
    {
        Delete3DTextLabel(gLabel[slot]);
        gLabelOn[slot] = false;
    }
    new text[256], biaya[32];
    FormatRupiah(gFee[slot], biaya, sizeof(biaya));
    // Gaya label garkot Indonesia (referensi video): ID kuning, info putih, tombol F merah.
    format(text, sizeof(text),
        "{FFFF00}(GARKOT ID: %d)\n{FFFFFF}%s\nBiaya: %s | Isi: %d/%d\nTekan {FF4444}F{FFFFFF} untuk buka garasi",
        gDBID[slot], gName[slot], biaya, Garage_StoredCount(slot), GARAGE_MAX_STORED);
    gLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        gPosX[slot], gPosY[slot], gPosZ[slot] + 1.2, 20.0, 0, 1);
    gLabelOn[slot] = true;
    return 1;
}

// Garage_Spawn: membuat pickup + label 3D untuk satu garasi.
stock Garage_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_GARAGE || !gExists[slot]) return 0;
    gPickup[slot] = CreatePickup(1318, 23, gPosX[slot], gPosY[slot], gPosZ[slot], 0);
    Garage_RefreshLabel(slot);
    return 1;
}

// Garage_Nearest: slot garasi terdekat dalam GARAGE_RANGE, -1 jika tidak ada.
stock Garage_Nearest(playerid)
{
    new best = -1;
    new Float:bestdist = GARAGE_RANGE;
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (!gExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, gPosX[i], gPosY[i], gPosZ[i]);
        if (d <= bestdist)
        {
            bestdist = d;
            best = i;
        }
    }
    return best;
}

// Garage_NameFromDBID: nama garasi dari id database, untuk pesan /vlist.
stock Garage_NameFromDBID(dbid, dest[], len)
{
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (gExists[i] && gDBID[i] == dbid)
        {
            format(dest, len, "%s", gName[i]);
            return 1;
        }
    }
    format(dest, len, "Garasi");
    return 0;
}

//================================================================
// BUAT GARASI
//================================================================

// Garage_Create: admin membuat garasi baru di posisinya (simpan ke DB).
stock Garage_Create(playerid, const name[], fee)
{
    new slot = Garage_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot garasi penuh (maksimal 50).");
        return 0;
    }
    format(pGarageName[playerid], sizeof(pGarageName[]), "%s", name);
    pGarageFee[playerid] = fee;
    pGarageNewSlot[playerid] = slot;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO garages (name, pos_x, pos_y, pos_z, fee) VALUES ('%e', %f, %f, %f, %d)",
        name, x, y, z, fee);
    mysql_tquery(g_SQL, query, "OnGarageCreated", "d", playerid);
    return 1;
}

//================================================================
// SIMPAN & AMBIL KENDARAAN
//================================================================

// Garage_Store: menitipkan kendaraan milik pemain ke garasi.
stock Garage_Store(playerid, gslot, vslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot]) return 0;
    if (vOwnerCharID[vslot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 0;
    }
    if (vGarageID[vslot] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini sudah tersimpan di garasi.");
        return 0;
    }
    if (!vSpawned[vslot])
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini sedang tidak aktif di dunia.");
        return 0;
    }
    if (Garage_StoredCount(gslot) >= GARAGE_MAX_STORED)
    {
        SendClientMessage(playerid, COLOR_RED, "Garasi ini sudah penuh.");
        return 0;
    }
    new Float:vx, Float:vy, Float:vz;
    GetVehiclePos(vVehID[vslot], vx, vy, vz);
    new Float:d = floatsqroot(
        (vx - gPosX[gslot]) * (vx - gPosX[gslot]) +
        (vy - gPosY[gslot]) * (vy - gPosY[gslot]) +
        (vz - gPosZ[gslot]) * (vz - gPosZ[gslot]));
    if (d > GARAGE_VEH_RANGE)
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraanmu terlalu jauh dari garasi ini (maks 15 meter).");
        return 0;
    }
    if (Vehicle_IsOccupied(vslot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan sedang dipakai orang lain, tidak bisa dititipkan.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < gFee[gslot])
    {
        new kurang[32], msg[160];
        FormatRupiah(gFee[gslot], kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Biaya titip di garasi ini %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    if (gFee[gslot] > 0) GivePlayerMoney(playerid, -gFee[gslot]);

    // Pemain yang sedang mengemudikan kendaraan ini dikeluarkan dulu.
    if (GetPlayerVehicleID(playerid) == vVehID[vslot])
    {
        RemovePlayerFromVehicle(playerid);
    }
    vGarageID[vslot] = gDBID[gslot];
    Vehicle_SaveSlot(vslot);
    Vehicle_Destroy(vslot);
    Garage_RefreshLabel(gslot);

    new nama[32], biaya[32], msg[256];
    Vehicle_CatName(vModel[vslot], nama, sizeof(nama));
    FormatRupiah(gFee[gslot], biaya, sizeof(biaya));
    format(msg, sizeof(msg),
        "Kendaraan %s (%s) dititipkan di garasi \"%s\". Biaya titip: %s.\nAmbil lagi kapan saja dengan /garage di sini.",
        nama, vPlate[vslot], gName[gslot], biaya);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Garage_Retrieve: mengambil kendaraan yang tersimpan di garasi.
stock Garage_Retrieve(playerid, gslot, vslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot]) return 0;
    if (vOwnerCharID[vslot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 0;
    }
    if (vGarageID[vslot] != gDBID[gslot])
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini tidak tersimpan di garasi ini.");
        return 0;
    }
    if (vSpawned[vslot])
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini sudah aktif di dunia.");
        return 0;
    }
    // Spawn di depan garasi, menghadap keluar dari titik garasi.
    vPosX[vslot] = gPosX[gslot] + 4.0;
    vPosY[vslot] = gPosY[gslot];
    vPosZ[vslot] = gPosZ[gslot];
    vAngle[vslot] = 0.0;
    vGarageID[vslot] = 0;
    Vehicle_Spawn(vslot);
    Vehicle_SaveSlot(vslot);
    Garage_RefreshLabel(gslot);
    PutPlayerInVehicle(playerid, vVehID[vslot], 0);

    new nama[32], msg[192];
    Vehicle_CatName(vModel[vslot], nama, sizeof(nama));
    format(msg, sizeof(msg), "Kendaraan %s (%s) dikeluarkan dari garasi \"%s\". Selamat jalan!",
        nama, vPlate[vslot], gName[gslot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Garage_Transfer: pindahkan kendaraan yang tersimpan ke garasi kota lain (kena biaya).
stock Garage_Transfer(playerid, gslot, vslot, targetslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    if (targetslot < 0 || targetslot >= MAX_GARAGE || !gExists[targetslot]) return 0;
    if (targetslot == gslot) return 0;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot]) return 0;
    if (vOwnerCharID[vslot] != Society_PlayerData[playerid][sPCharID])
    {
        SendClientMessage(playerid, COLOR_RED, "Ini bukan kendaraanmu.");
        return 0;
    }
    if (vGarageID[vslot] != gDBID[gslot])
    {
        SendClientMessage(playerid, COLOR_RED, "Kendaraan ini tidak tersimpan di garasi ini.");
        return 0;
    }
    if (Garage_StoredCount(targetslot) >= GARAGE_MAX_STORED)
    {
        SendClientMessage(playerid, COLOR_RED, "Garasi tujuan sudah penuh.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < GARAGE_TRANSFER_FEE)
    {
        new kurang[32], msg[160];
        FormatRupiah(GARAGE_TRANSFER_FEE, kurang, sizeof(kurang));
        format(msg, sizeof(msg), "Uang tidak cukup. Biaya transfer %s.", kurang);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, -GARAGE_TRANSFER_FEE);
    vGarageID[vslot] = gDBID[targetslot];
    Vehicle_SaveSlot(vslot);
    Garage_RefreshLabel(gslot);
    Garage_RefreshLabel(targetslot);

    new nama[32], biaya[32], msg[256];
    Vehicle_CatName(vModel[vslot], nama, sizeof(nama));
    FormatRupiah(GARAGE_TRANSFER_FEE, biaya, sizeof(biaya));
    format(msg, sizeof(msg),
        "Kendaraan %s (%s) ditransfer ke garasi \"%s\". Biaya transfer: %s.",
        nama, vPlate[vslot], gName[targetslot], biaya);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// MENU GARASI
//================================================================

// Garage_ShowMain: menu utama /garage (simpan / ambil / transfer / info).
stock Garage_ShowMain(playerid, gslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    pGarageSlot[playerid] = gslot;
    Dialog_Show(playerid, GarageMain, DIALOG_STYLE_LIST, gName[gslot],
        "Simpan Kendaraan\nAmbil Kendaraan\nTransfer Kendaraan\nInfo Garasi", "Pilih", "Tutup");
    return 1;
}

// Garage_ShowStoreList: daftar kendaraan milik pemain yang bisa dititipkan.
stock Garage_ShowStoreList(playerid, gslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    new list[1024], nama[32], baris[128], Float:vx, Float:vy, Float:vz;
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] > 0 || !vSpawned[i]) continue;
        GetVehiclePos(vVehID[i], vx, vy, vz);
        new Float:d = floatsqroot(
            (vx - gPosX[gslot]) * (vx - gPosX[gslot]) +
            (vy - gPosY[gslot]) * (vy - gPosY[gslot]) +
            (vz - gPosZ[gslot]) * (vz - gPosZ[gslot]));
        if (d > GARAGE_VEH_RANGE) continue;
        Vehicle_CatName(vModel[i], nama, sizeof(nama));
        format(baris, sizeof(baris), "%s (%s) - %.0f m", nama, vPlate[i], d);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada kendaraanmu yang aktif dalam 15 meter dari garasi ini.");
        SendClientMessage(playerid, COLOR_GREY, "Parkirkan kendaraanmu di dekat garasi lalu ulangi /garage.");
        return 0;
    }
    Dialog_Show(playerid, GarageStore, DIALOG_STYLE_LIST, "Simpan Kendaraan", list, "Simpan", "Kembali");
    return 1;
}

// Garage_ShowRetrieveList: daftar kendaraan milik pemain yang tersimpan di garasi ini.
stock Garage_ShowRetrieveList(playerid, gslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    new list[1024], nama[32], baris[96];
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] != gDBID[gslot]) continue;
        Vehicle_CatName(vModel[i], nama, sizeof(nama));
        format(baris, sizeof(baris), "%s (%s)", nama, vPlate[i]);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada kendaraanmu yang tersimpan di garasi ini.");
        return 0;
    }
    Dialog_Show(playerid, GarageRetrieve, DIALOG_STYLE_LIST, "Ambil Kendaraan", list, "Ambil", "Kembali");
    return 1;
}

// Garage_ShowTransferList: daftar kendaraan tersimpan untuk ditransfer ke garkot lain.
stock Garage_ShowTransferList(playerid, gslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    new charid = Society_PlayerData[playerid][sPCharID];
    new list[1024], nama[32], baris[96];
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] != gDBID[gslot]) continue;
        Vehicle_CatName(vModel[i], nama, sizeof(nama));
        format(baris, sizeof(baris), "%s (%s)", nama, vPlate[i]);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada kendaraanmu yang tersimpan di garasi ini.");
        return 0;
    }
    Dialog_Show(playerid, GarageTransfer, DIALOG_STYLE_LIST, "Transfer Kendaraan", list, "Pilih", "Kembali");
    return 1;
}

// Garage_ShowTransferTarget: daftar garasi kota lain sebagai tujuan transfer.
stock Garage_ShowTransferTarget(playerid, gslot, vslot)
{
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 0;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot]) return 0;
    pGarageSlot[playerid] = gslot;
    pGarageVehSlot[playerid] = vslot;
    new list[1024], baris[128], biaya[32];
    FormatRupiah(GARAGE_TRANSFER_FEE, biaya, sizeof(biaya));
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (!gExists[i] || i == gslot) continue;
        format(baris, sizeof(baris), "%s (ID %d) - Isi %d/%d - Biaya %s",
            gName[i], gDBID[i], Garage_StoredCount(i), GARAGE_MAX_STORED, biaya);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada garasi kota lain.");
        return 0;
    }
    Dialog_Show(playerid, GarageTransferTarget, DIALOG_STYLE_LIST, "Tujuan Transfer", list, "Pilih", "Kembali");
    return 1;
}

// Garage_ShowList: daftar semua garasi di server (/garages).
stock Garage_ShowList(playerid)
{
    new list[2048], biaya[32], baris[128];
    list[0] = EOS;
    new count = 0;
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (!gExists[i]) continue;
        FormatRupiah(gFee[i], biaya, sizeof(biaya));
        format(baris, sizeof(baris), "%s - Titip %s - Tersimpan %d/%d",
            gName[i], biaya, Garage_StoredCount(i), GARAGE_MAX_STORED);
        if (count > 0) strcat(list, "\n", sizeof(list));
        strcat(list, baris, sizeof(list));
        count++;
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Belum ada garasi di server ini.");
        return 0;
    }
    Dialog_Show(playerid, GarageList, DIALOG_STYLE_LIST, "Daftar Garasi Kota", list, "Tutup", "");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:GarageMain - menu utama garasi.
Dialog:GarageMain(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new gslot = pGarageSlot[playerid];
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 1;
    if (listitem == 0)
    {
        Garage_ShowStoreList(playerid, gslot);
    }
    else if (listitem == 1)
    {
        Garage_ShowRetrieveList(playerid, gslot);
    }
    else if (listitem == 2)
    {
        Garage_ShowTransferList(playerid, gslot);
    }
    else if (listitem == 3)
    {
        new biaya[32], msg[320];
        FormatRupiah(gFee[gslot], biaya, sizeof(biaya));
        format(msg, sizeof(msg),
            "Garasi: %s\nBiaya titip: %s per kendaraan\nTersimpan: %d/%d kendaraan\n\nTitipkan kendaraanmu di sini agar tidak memenuhi jalanan.\nKendaraan yang dititipkan tidak muncul di dunia sampai\nkamu mengambilnya lagi dengan /garage di garasi ini.",
            gName[gslot], biaya, Garage_StoredCount(gslot), GARAGE_MAX_STORED);
        Dialog_Show(playerid, GarageInfoBack, DIALOG_STYLE_MSGBOX, "Info Garasi", msg, "Kembali", "");
    }
    return 1;
}

// Dialog:GarageStore - pilih kendaraan yang akan dititipkan.
Dialog:GarageStore(playerid, response, listitem, inputtext[])
{
    new gslot = pGarageSlot[playerid];
    if (!response)
    {
        Garage_ShowMain(playerid, gslot);
        return 1;
    }
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 1;
    new charid = Society_PlayerData[playerid][sPCharID];
    new count = 0, vslot = -1, Float:vx, Float:vy, Float:vz;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] > 0 || !vSpawned[i]) continue;
        GetVehiclePos(vVehID[i], vx, vy, vz);
        new Float:d = floatsqroot(
            (vx - gPosX[gslot]) * (vx - gPosX[gslot]) +
            (vy - gPosY[gslot]) * (vy - gPosY[gslot]) +
            (vz - gPosZ[gslot]) * (vz - gPosZ[gslot]));
        if (d > GARAGE_VEH_RANGE) continue;
        if (count == listitem)
        {
            vslot = i;
            break;
        }
        count++;
    }
    if (vslot == -1) return 1;
    pGarageVehSlot[playerid] = vslot;
    new nama[32], biaya[32], msg[256];
    Vehicle_CatName(vModel[vslot], nama, sizeof(nama));
    FormatRupiah(gFee[gslot], biaya, sizeof(biaya));
    format(msg, sizeof(msg),
        "Titipkan kendaraan ini?\n\n%s (%s)\nGarasi: %s\nBiaya titip: %s\n\nKendaraan akan hilang dari jalanan sampai kamu mengambilnya lagi.",
        nama, vPlate[vslot], gName[gslot], biaya);
    Dialog_Show(playerid, GarageStoreConfirm, DIALOG_STYLE_MSGBOX, "Konfirmasi Titip", msg, "Titipkan", "Batal");
    return 1;
}

// Dialog:GarageStoreConfirm - konfirmasi sebelum biaya dipotong.
Dialog:GarageStoreConfirm(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Garage_ShowStoreList(playerid, pGarageSlot[playerid]);
        return 1;
    }
    Garage_Store(playerid, pGarageSlot[playerid], pGarageVehSlot[playerid]);
    return 1;
}

// Dialog:GarageRetrieve - pilih kendaraan yang akan diambil.
Dialog:GarageRetrieve(playerid, response, listitem, inputtext[])
{
    new gslot = pGarageSlot[playerid];
    if (!response)
    {
        Garage_ShowMain(playerid, gslot);
        return 1;
    }
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 1;
    new charid = Society_PlayerData[playerid][sPCharID];
    new count = 0, vslot = -1;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] != gDBID[gslot]) continue;
        if (count == listitem)
        {
            vslot = i;
            break;
        }
        count++;
    }
    if (vslot == -1) return 1;
    Garage_Retrieve(playerid, gslot, vslot);
    return 1;
}

// Dialog:GarageTransfer - pilih kendaraan yang akan ditransfer ke garkot lain.
Dialog:GarageTransfer(playerid, response, listitem, inputtext[])
{
    new gslot = pGarageSlot[playerid];
    if (!response)
    {
        Garage_ShowMain(playerid, gslot);
        return 1;
    }
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 1;
    new charid = Society_PlayerData[playerid][sPCharID];
    new count = 0, vslot = -1;
    for (new i = 0; i < MAX_PVEH; i++)
    {
        if (!vExists[i] || vOwnerCharID[i] != charid) continue;
        if (vGarageID[i] != gDBID[gslot]) continue;
        if (count == listitem)
        {
            vslot = i;
            break;
        }
        count++;
    }
    if (vslot == -1) return 1;
    Garage_ShowTransferTarget(playerid, gslot, vslot);
    return 1;
}

// Dialog:GarageTransferTarget - pilih garasi kota tujuan transfer.
Dialog:GarageTransferTarget(playerid, response, listitem, inputtext[])
{
    new gslot = pGarageSlot[playerid];
    new vslot = pGarageVehSlot[playerid];
    if (!response)
    {
        Garage_ShowTransferList(playerid, gslot);
        return 1;
    }
    if (gslot < 0 || gslot >= MAX_GARAGE || !gExists[gslot]) return 1;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot]) return 1;
    new count = 0, target = -1;
    for (new i = 0; i < MAX_GARAGE; i++)
    {
        if (!gExists[i] || i == gslot) continue;
        if (count == listitem)
        {
            target = i;
            break;
        }
        count++;
    }
    if (target == -1) return 1;
    pGarageTarget[playerid] = target;
    new nama[32], biaya[32], msg[256];
    Vehicle_CatName(vModel[vslot], nama, sizeof(nama));
    FormatRupiah(GARAGE_TRANSFER_FEE, biaya, sizeof(biaya));
    format(msg, sizeof(msg),
        "Transfer kendaraan ini?\n\n%s (%s)\nDari: %s\nKe: %s\nBiaya transfer: %s",
        nama, vPlate[vslot], gName[gslot], gName[target], biaya);
    Dialog_Show(playerid, GarageTransferConfirm, DIALOG_STYLE_MSGBOX, "Konfirmasi Transfer", msg, "Transfer", "Batal");
    return 1;
}

// Dialog:GarageTransferConfirm - konfirmasi sebelum biaya transfer dipotong.
Dialog:GarageTransferConfirm(playerid, response, listitem, inputtext[])
{
    if (!response)
    {
        Garage_ShowTransferTarget(playerid, pGarageSlot[playerid], pGarageVehSlot[playerid]);
        return 1;
    }
    Garage_Transfer(playerid, pGarageSlot[playerid], pGarageVehSlot[playerid], pGarageTarget[playerid]);
    return 1;
}

// Dialog:GarageInfoBack - kembali ke menu utama setelah melihat info.
Dialog:GarageInfoBack(playerid, response, listitem, inputtext[])
{
    Garage_ShowMain(playerid, pGarageSlot[playerid]);
    return 1;
}

// Dialog:GarageList - daftar garasi (hanya info, tidak ada aksi).
Dialog:GarageList(playerid, response, listitem, inputtext[])
{
    return 1;
}

//================================================================
// MUAT DARI DATABASE
//================================================================

// Garage_LoadAll: memuat semua garasi dari database lalu buat pickup + label.
stock Garage_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL, "SELECT * FROM garages", "OnGaragesLoaded");
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnGaragesLoaded: mengisi slot garasi dari database lalu spawn.
public OnGaragesLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_GARAGE; i++)
    {
        cache_get_value_name_int(i, "id", tmp);       gDBID[i] = tmp;
        cache_get_value_name(i, "name", gName[i], sizeof(gName[]));
        cache_get_value_name_float(i, "pos_x", ftmp); gPosX[i] = ftmp;
        cache_get_value_name_float(i, "pos_y", ftmp); gPosY[i] = ftmp;
        cache_get_value_name_float(i, "pos_z", ftmp); gPosZ[i] = ftmp;
        cache_get_value_name_int(i, "fee", tmp);      gFee[i] = tmp;
        gPickup[i] = -1;
        gLabel[i] = Text3D:INVALID_3DTEXT_ID;
        gLabelOn[i] = false;
        gExists[i] = 1;
        Garage_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d garasi kota dimuat.", count);
    print(msg);
    return 1;
}

// OnGarageCreated: menyimpan id database hasil INSERT garasi baru.
public OnGarageCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pGarageNewSlot[playerid];
    if (slot < 0 || slot >= MAX_GARAGE) return 1;
    gExists[slot] = 1;
    gDBID[slot] = cache_insert_id();
    format(gName[slot], sizeof(gName[]), "%s", pGarageName[playerid]);
    gFee[slot] = pGarageFee[playerid];
    GetPlayerPos(playerid, gPosX[slot], gPosY[slot], gPosZ[slot]);
    gPickup[slot] = -1;
    gLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    gLabelOn[slot] = false;
    Garage_Spawn(slot);
    new msg[128];
    format(msg, sizeof(msg), "Garasi \"%s\" berhasil dibuat (ID database %d).", gName[slot], gDBID[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Pemain bisa menitipkan & mengambil kendaraan di sini dengan /garage.");
    return 1;
}
