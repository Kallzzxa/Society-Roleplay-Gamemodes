//================================================================
// Society Roleplay - Door_System
// Pintu dinamis: dibuat admin (level 3+) atau pemilik entitas
// (rumah/bisnis/fraksi), menghubungkan dua titik (luar <-> interior
// apa pun). Setiap pintu punya pickup + label 3D di kedua sisi,
// bisa dikunci, tersimpan di tabel doors.
// Di-include dari gamemodes/Society_Main.pwn (setelah modul House,
// Business & Faction, karena memakai data kepemilikan mereka).
//================================================================

#if defined _door_system_included
    #endinput
#endif
#define _door_system_included

//==== KONSTANTA ====
#define MAX_DOOR 100
#define DOOR_RANGE 4.0       // jarak interaksi pintu
#define DOOR_TYPE_HOUSE 0    // pemilik = id rumah (tabel houses)
#define DOOR_TYPE_BIZ 1      // pemilik = id bisnis (tabel businesses)
#define DOOR_TYPE_FACTION 2  // pemilik = id fraksi (tabel factions)

// Nama tipe pemilik pintu.
new Door_TypeName[3][8] = {"Rumah", "Bisnis", "Fraksi"};

//==== DATA PINTU ====
new drExists[MAX_DOOR];            // 1 jika slot terisi
new drDBID[MAX_DOOR];              // id baris di tabel doors
new drOwnerType[MAX_DOOR];         // 0=rumah, 1=bisnis, 2=fraksi
new drOwnerID[MAX_DOOR];           // id baris entitas pemilik
new drName[MAX_DOOR][32];          // nama pintu (mis. "Pintu Belakang")
new Float:drExtX[MAX_DOOR];        // sisi luar (pintu masuk)
new Float:drExtY[MAX_DOOR];
new Float:drExtZ[MAX_DOOR];
new drExtInt[MAX_DOOR];            // interior sisi luar
new drExtVW[MAX_DOOR];             // virtual world sisi luar
new Float:drIntX[MAX_DOOR];        // sisi dalam (interior tujuan)
new Float:drIntY[MAX_DOOR];
new Float:drIntZ[MAX_DOOR];
new drIntInt[MAX_DOOR];            // interior sisi dalam
new drIntVW[MAX_DOOR];             // virtual world sisi dalam
new drLocked[MAX_DOOR];            // 1 = terkunci
new drExtPickup[MAX_DOOR];         // pickup sisi luar
new drIntPickup[MAX_DOOR];         // pickup sisi dalam
new Text3D:drExtLabel[MAX_DOOR];   // label 3D sisi luar
new Text3D:drIntLabel[MAX_DOOR];   // label 3D sisi dalam
new bool:drExtLabelOn[MAX_DOOR];
new bool:drIntLabelOn[MAX_DOOR];

// Data sementara: pembuatan pintu dua langkah oleh admin/pemilik.
new pDoorStep[MAX_PLAYERS];       // 0 = belum mulai, 1 = sisi luar tercatat
new pDoorType[MAX_PLAYERS];       // tipe pemilik (0/1/2)
new pDoorOwnerID[MAX_PLAYERS];    // id baris entitas pemilik
new pDoorName[MAX_PLAYERS][32];   // nama pintu
new Float:pDoorExtX[MAX_PLAYERS];
new Float:pDoorExtY[MAX_PLAYERS];
new Float:pDoorExtZ[MAX_PLAYERS];
new pDoorExtInt[MAX_PLAYERS];
new pDoorExtVW[MAX_PLAYERS];
new pDoorMenuSlot[MAX_PLAYERS];   // slot pintu untuk dialog
new pDoorListSlot[MAX_PLAYERS][40]; // slot pintu pada dialog /doors

//==== FORWARD ====
forward OnDoorLoaded();
forward OnDoorCreated(playerid);

//================================================================
// UTIL PINTU
//================================================================

// Door_FreeSlot: mencari slot pintu kosong, -1 jika penuh.
stock Door_FreeSlot()
{
    for (new i = 0; i < MAX_DOOR; i++)
    {
        if (!drExists[i]) return i;
    }
    return -1;
}

// Door_FindOwnerSlot: mencari slot entitas pemilik berdasar tipe & id DB.
// Dipakai untuk cek kepemilikan; -1 jika entitas tidak ditemukan.
stock Door_FindOwnerSlot(type, ownerid)
{
    new i;
    if (type == DOOR_TYPE_HOUSE)
    {
        for (i = 0; i < MAX_HOUSE; i++)
        {
            if (hExists[i] && hDBID[i] == ownerid) return i;
        }
    }
    else if (type == DOOR_TYPE_BIZ)
    {
        for (i = 0; i < MAX_BUSINESS; i++)
        {
            if (bExists[i] && bDBID[i] == ownerid) return i;
        }
    }
    else if (type == DOOR_TYPE_FACTION)
    {
        for (i = 0; i < MAX_FACTION; i++)
        {
            if (fExists[i] && fDBID[i] == ownerid) return i;
        }
    }
    return -1;
}

// Door_OwnerName: nama entitas pemilik pintu (untuk label & dialog).
stock Door_OwnerName(slot, dest[], len)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot])
    {
        dest[0] = EOS;
        return 0;
    }
    new eslot = Door_FindOwnerSlot(drOwnerType[slot], drOwnerID[slot]);
    if (eslot == -1)
    {
        format(dest, len, "%s #%d", Door_TypeName[drOwnerType[slot]], drOwnerID[slot]);
        return 0;
    }
    if (drOwnerType[slot] == DOOR_TYPE_HOUSE)
    {
        format(dest, len, "Rumah #%d (%s)", drOwnerID[slot], hLocation[eslot]);
    }
    else if (drOwnerType[slot] == DOOR_TYPE_BIZ)
    {
        format(dest, len, "Bisnis #%d (%s)", drOwnerID[slot], bName[eslot]);
    }
    else
    {
        format(dest, len, "Fraksi #%d (%s)", drOwnerID[slot], fName[eslot]);
    }
    return 1;
}

// Door_CanManage: true jika pemain boleh mengelola pintu (admin 3+ atau
// pemilik entitas: pemilik rumah/bisnis atau ketua fraksi).
stock Door_CanManage(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (IsAdmin(playerid, 3)) return 1;
    new charid = Society_PlayerData[playerid][sPCharID];
    if (charid <= 0) return 0;
    new eslot = Door_FindOwnerSlot(drOwnerType[slot], drOwnerID[slot]);
    if (eslot == -1) return 0;
    if (drOwnerType[slot] == DOOR_TYPE_HOUSE) return (hOwnerCharID[eslot] == charid);
    if (drOwnerType[slot] == DOOR_TYPE_BIZ) return (bOwnerCharID[eslot] == charid);
    return (fLeaderCharID[eslot] == charid);
}

// Door_RefreshLabels: menggambar ulang kedua label 3D sesuai status pintu.
stock Door_RefreshLabels(slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (drExtLabelOn[slot])
    {
        Delete3DTextLabel(drExtLabel[slot]);
        drExtLabelOn[slot] = false;
    }
    if (drIntLabelOn[slot])
    {
        Delete3DTextLabel(drIntLabel[slot]);
        drIntLabelOn[slot] = false;
    }
    new text[256], owner[64];
    Door_OwnerName(slot, owner, sizeof(owner));
    if (drLocked[slot])
    {
        format(text, sizeof(text), "{33AA33}[PINTU ID:%d]\n{FFFF00}%s\n{FFFFFF}%s\n{FF4444}[TERKUNCI]",
            drDBID[slot], drName[slot], owner);
    }
    else
    {
        format(text, sizeof(text), "{33AA33}[PINTU ID:%d]\n{FFFF00}%s\n{FFFFFF}%s\n{00CCFF}Tekan ENTER untuk masuk",
            drDBID[slot], drName[slot], owner);
    }
    drExtLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        drExtX[slot], drExtY[slot], drExtZ[slot] + 1.0, 15.0, drExtVW[slot], 1);
    drExtLabelOn[slot] = true;
    format(text, sizeof(text), "{33AA33}[PINTU ID:%d]\n{FFFF00}%s\n{00CCFF}Tekan ENTER untuk keluar",
        drDBID[slot], drName[slot]);
    drIntLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        drIntX[slot], drIntY[slot], drIntZ[slot] + 1.0, 15.0, drIntVW[slot], 1);
    drIntLabelOn[slot] = true;
    return 1;
}

// Door_Spawn: membuat pickup kedua sisi + label 3D untuk satu pintu.
stock Door_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    drExtPickup[slot] = CreatePickup(1239, 23, drExtX[slot], drExtY[slot], drExtZ[slot], drExtVW[slot]);
    drIntPickup[slot] = CreatePickup(1239, 23, drIntX[slot], drIntY[slot], drIntZ[slot], drIntVW[slot]);
    Door_RefreshLabels(slot);
    return 1;
}

// Door_Despawn: menghapus pickup & label 3D satu pintu.
stock Door_Despawn(slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    DestroyPickup(drExtPickup[slot]);
    DestroyPickup(drIntPickup[slot]);
    if (drExtLabelOn[slot]) Delete3DTextLabel(drExtLabel[slot]);
    if (drIntLabelOn[slot]) Delete3DTextLabel(drIntLabel[slot]);
    drExtLabelOn[slot] = false;
    drIntLabelOn[slot] = false;
    return 1;
}

// Door_NearestExt: slot pintu terdekat dari sisi luar (DOOR_RANGE), -1 jika tidak ada.
stock Door_NearestExt(playerid)
{
    new best = -1;
    new Float:bestdist = DOOR_RANGE;
    for (new i = 0; i < MAX_DOOR; i++)
    {
        if (!drExists[i]) continue;
        if (GetPlayerInterior(playerid) != drExtInt[i]) continue;
        if (GetPlayerVirtualWorld(playerid) != drExtVW[i]) continue;
        new Float:dist = GetPlayerDistanceFromPoint(playerid, drExtX[i], drExtY[i], drExtZ[i]);
        if (dist <= bestdist)
        {
            bestdist = dist;
            best = i;
        }
    }
    return best;
}

// Door_NearestInt: slot pintu terdekat dari sisi dalam (DOOR_RANGE), -1 jika tidak ada.
stock Door_NearestInt(playerid)
{
    new best = -1;
    new Float:bestdist = DOOR_RANGE;
    for (new i = 0; i < MAX_DOOR; i++)
    {
        if (!drExists[i]) continue;
        if (GetPlayerInterior(playerid) != drIntInt[i]) continue;
        if (GetPlayerVirtualWorld(playerid) != drIntVW[i]) continue;
        new Float:dist = GetPlayerDistanceFromPoint(playerid, drIntX[i], drIntY[i], drIntZ[i]);
        if (dist <= bestdist)
        {
            bestdist = dist;
            best = i;
        }
    }
    return best;
}

// Door_OnDisconnect: mereset data sementara pembuatan pintu saat pemain keluar.
stock Door_OnDisconnect(playerid)
{
    pDoorStep[playerid] = 0;
    pDoorType[playerid] = 0;
    pDoorOwnerID[playerid] = 0;
    pDoorName[playerid][0] = EOS;
    return 1;
}

//================================================================
// AKSI PINTU
//================================================================

// Door_OwnerNameSafe: nama entitas berdasar tipe & id DB (dipakai sebelum pintu tersimpan).
stock Door_OwnerNameSafe(type, ownerid, dest[], len)
{
    new eslot = Door_FindOwnerSlot(type, ownerid);
    if (eslot == -1)
    {
        format(dest, len, "%s #%d", Door_TypeName[type], ownerid);
        return 0;
    }
    if (type == DOOR_TYPE_HOUSE)
    {
        format(dest, len, "Rumah #%d (%s)", ownerid, hLocation[eslot]);
    }
    else if (type == DOOR_TYPE_BIZ)
    {
        format(dest, len, "Bisnis #%d (%s)", ownerid, bName[eslot]);
    }
    else
    {
        format(dest, len, "Fraksi #%d (%s)", ownerid, fName[eslot]);
    }
    return 1;
}

// Door_CreateStep1: langkah pertama /createdoor — catat sisi luar (posisi admin/pemilik).
stock Door_CreateStep1(playerid, type, ownerid, const name[])
{
    pDoorType[playerid] = type;
    pDoorOwnerID[playerid] = ownerid;
    format(pDoorName[playerid], sizeof(pDoorName[]), "%s", name);
    GetPlayerPos(playerid, pDoorExtX[playerid], pDoorExtY[playerid], pDoorExtZ[playerid]);
    pDoorExtInt[playerid] = GetPlayerInterior(playerid);
    pDoorExtVW[playerid] = GetPlayerVirtualWorld(playerid);
    pDoorStep[playerid] = 1;
    new owner[64], msg[192];
    Door_OwnerNameSafe(type, ownerid, owner, sizeof(owner));
    format(msg, sizeof(msg), "Sisi luar tercatat untuk \"%s\" (%s).", name, owner);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_YELLOW, "Sekarang pergi ke titik INTERIOR tujuan,");
    SendClientMessage(playerid, COLOR_YELLOW, "lalu ketik /createdoor (tanpa argumen) untuk menyelesaikan.");
    return 1;
}

// Door_CreateStep2: langkah kedua /createdoor — catat sisi dalam & simpan ke DB.
stock Door_CreateStep2(playerid)
{
    if (pDoorStep[playerid] != 1) return 0;
    new slot = Door_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot pintu penuh (maksimal 100).");
        pDoorStep[playerid] = 0;
        return 0;
    }
    new Float:ix, Float:iy, Float:iz;
    GetPlayerPos(playerid, ix, iy, iz);
    new iint = GetPlayerInterior(playerid);
    new ivw = GetPlayerVirtualWorld(playerid);
    new query[640];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO doors (owner_type, owner_id, name, ext_x, ext_y, ext_z, ext_int, ext_vw, int_x, int_y, int_z, int_int, int_vw, locked) VALUES (%d, %d, '%e', %f, %f, %f, %d, %d, %f, %f, %f, %d, %d, 0)",
        pDoorType[playerid], pDoorOwnerID[playerid], pDoorName[playerid],
        pDoorExtX[playerid], pDoorExtY[playerid], pDoorExtZ[playerid],
        pDoorExtInt[playerid], pDoorExtVW[playerid],
        ix, iy, iz, iint, ivw);
    mysql_tquery(g_SQL, query, "OnDoorCreated", "d", playerid);
    return 1;
}

// Door_Enter: teleport dari sisi luar ke sisi dalam (cek kunci).
stock Door_Enter(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (drLocked[slot] && !Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Pintu ini terkunci.");
        return 0;
    }
    SetPlayerInterior(playerid, drIntInt[slot]);
    SetPlayerVirtualWorld(playerid, drIntVW[slot]);
    SetPlayerPos(playerid, drIntX[slot], drIntY[slot], drIntZ[slot]);
    new msg[96];
    format(msg, sizeof(msg), "Kamu memasuki \"%s\". Tekan ENTER untuk keluar.", drName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Door_Exit: teleport dari sisi dalam kembali ke sisi luar.
stock Door_Exit(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    SetPlayerInterior(playerid, drExtInt[slot]);
    SetPlayerVirtualWorld(playerid, drExtVW[slot]);
    SetPlayerPos(playerid, drExtX[slot], drExtY[slot], drExtZ[slot]);
    new msg[96];
    format(msg, sizeof(msg), "Kamu keluar lewat \"%s\".", drName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Door_ToggleLock: mengunci/membuka pintu (admin 3+ atau pemilik entitas).
stock Door_ToggleLock(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (!Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu tidak berhak mengelola pintu ini.");
        return 0;
    }
    drLocked[slot] = !drLocked[slot];
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE doors SET locked = %d WHERE id = %d", drLocked[slot], drDBID[slot]);
    mysql_tquery(g_SQL, query);
    Door_RefreshLabels(slot);
    if (drLocked[slot])
    {
        SendClientMessage(playerid, COLOR_YELLOW, "Pintu dikunci.");
    }
    else
    {
        SendClientMessage(playerid, COLOR_GREEN, "Pintu dibuka.");
    }
    return 1;
}

// Door_Delete: menghapus pintu (admin 4+ atau pemilik entitas).
stock Door_Delete(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (!IsAdmin(playerid, 4) && !Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu tidak berhak menghapus pintu ini.");
        return 0;
    }
    new dbid = drDBID[slot];
    Door_Despawn(slot);
    drExists[slot] = 0;
    new query[96];
    mysql_format(g_SQL, query, sizeof(query), "DELETE FROM doors WHERE id = %d", dbid);
    mysql_tquery(g_SQL, query);
    new msg[96];
    format(msg, sizeof(msg), "Pintu #%d dihapus.", dbid);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Door_Rename: mengganti nama pintu (admin 3+ atau pemilik entitas).
stock Door_Rename(playerid, slot, const name[])
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    if (!Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu tidak berhak mengelola pintu ini.");
        return 0;
    }
    if (strlen(name) < 2 || strlen(name) > 31)
    {
        SendClientMessage(playerid, COLOR_RED, "Nama pintu 2-31 karakter.");
        return 0;
    }
    format(drName[slot], sizeof(drName[]), "%s", name);
    new query[192];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE doors SET name = '%e' WHERE id = %d", name, drDBID[slot]);
    mysql_tquery(g_SQL, query);
    Door_RefreshLabels(slot);
    new msg[96];
    format(msg, sizeof(msg), "Nama pintu diubah menjadi \"%s\".", name);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// COMMAND
//================================================================

// Door_CmdCreate: /createdoor [tipe] [id pemilik] [nama] — dua langkah.
// Admin 3+ boleh untuk semua entitas; pemilik entitas hanya untuk miliknya.
// Tipe: 0 = rumah, 1 = bisnis, 2 = fraksi. Nama: spasi diganti _.
stock Door_CmdCreate(playerid, const cmdtext[], idx)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    // Tanpa argumen = langkah kedua (selesaikan pembuatan).
    new i = idx;
    while (cmdtext[i] == ' ') i++;
    if (cmdtext[i] == EOS)
    {
        if (pDoorStep[playerid] == 1)
        {
            Door_CreateStep2(playerid);
        }
        else
        {
            SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createdoor [tipe] [id_pemilik] [nama]");
            SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=Rumah, 1=Bisnis, 2=Fraksi (spasi pada nama diganti _)");
        }
        return 1;
    }
    // Langkah pertama: parse tipe, id pemilik, nama.
    new stype[8], sid[12], name[32];
    new n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(stype) - 1)
    {
        stype[n++] = cmdtext[i++];
    }
    stype[n] = EOS;
    while (cmdtext[i] == ' ') i++;
    n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(sid) - 1)
    {
        sid[n++] = cmdtext[i++];
    }
    sid[n] = EOS;
    while (cmdtext[i] == ' ') i++;
    n = 0;
    while (cmdtext[i] != EOS && n < sizeof(name) - 1)
    {
        name[n++] = (cmdtext[i] == '_') ? ' ' : cmdtext[i++];
    }
    name[n] = EOS;
    if (!IsNumeric(stype) || !IsNumeric(sid) || name[0] == EOS)
    {
        SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createdoor [tipe] [id_pemilik] [nama]");
        SendClientMessage(playerid, COLOR_GREY, "Tipe: 0=Rumah, 1=Bisnis, 2=Fraksi (spasi pada nama diganti _)");
        SendClientMessage(playerid, COLOR_GREY, "Contoh: /createdoor 0 3 Pintu_Belakang (rumah ID 3)");
        return 1;
    }
    new type = strval(stype);
    new ownerid = strval(sid);
    if (type < 0 || type > 2)
    {
        SendClientMessage(playerid, COLOR_RED, "Tipe harus 0 (Rumah), 1 (Bisnis), atau 2 (Fraksi).");
        return 1;
    }
    if (strlen(name) < 2)
    {
        SendClientMessage(playerid, COLOR_RED, "Nama pintu minimal 2 karakter.");
        return 1;
    }
    if (Door_FindOwnerSlot(type, ownerid) == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Entitas pemilik tidak ditemukan (cek ID rumah/bisnis/fraksi).");
        return 1;
    }
    // Hak akses: admin 3+ bebas; selain itu harus pemilik entitas.
    if (!IsAdmin(playerid, 3))
    {
        new charid = Society_PlayerData[playerid][sPCharID];
        new eslot = Door_FindOwnerSlot(type, ownerid);
        new ok = 0;
        if (type == DOOR_TYPE_HOUSE) ok = (hOwnerCharID[eslot] == charid);
        else if (type == DOOR_TYPE_BIZ) ok = (bOwnerCharID[eslot] == charid);
        else ok = (fLeaderCharID[eslot] == charid);
        if (!ok)
        {
            SendClientMessage(playerid, COLOR_RED, "Hanya admin level 3+ atau pemilik entitas yang boleh membuat pintu.");
            return 1;
        }
    }
    Door_CreateStep1(playerid, type, ownerid, name);
    return 1;
}

// Door_CmdList: /doors — daftar semua pintu (dialog, admin 4+/pemilik bisa kelola dari detail).
stock Door_CmdList(playerid)
{
    new list[2048], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_DOOR && count < 40; i++)
    {
        if (!drExists[i]) continue;
        new owner[64], baris[96];
        Door_OwnerName(i, owner, sizeof(owner));
        format(baris, sizeof(baris), "[ID:%d] %s (%s)%s\n",
            drDBID[i], drName[i], owner, drLocked[i] ? " [Terkunci]" : "");
        if (strlen(list) + strlen(baris) < sizeof(list) - 1)
        {
            strcat(list, baris, sizeof(list));
            pDoorListSlot[playerid][count] = i;
            count++;
        }
    }
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Belum ada pintu dinamis di server.");
        return 1;
    }
    Dialog_Show(playerid, DoorList, DIALOG_STYLE_LIST, "Pintu Dinamis", list, "Detail", "Tutup");
    return 1;
}

// Door_ShowInfo: dialog info pintu + opsi kelola untuk yang berhak.
stock Door_ShowInfo(playerid, slot)
{
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 0;
    pDoorMenuSlot[playerid] = slot;
    new owner[64], kunci[16], list[128], title[64], status[16];
    Door_OwnerName(slot, owner, sizeof(owner));
    if (drLocked[slot])
    {
        format(status, sizeof(status), "Terkunci");
        format(kunci, sizeof(kunci), "Buka Pintu");
    }
    else
    {
        format(status, sizeof(status), "Terbuka");
        format(kunci, sizeof(kunci), "Kunci Pintu");
    }
    format(title, sizeof(title), "[PINTU ID:%d] %s", drDBID[slot], drName[slot]);
    if (Door_CanManage(playerid, slot))
    {
        new msg[192];
        format(msg, sizeof(msg), "Pemilik: %s | Status: %s", owner, status);
        SendClientMessage(playerid, COLOR_GREY, msg);
        format(list, sizeof(list), "%s\nGanti Nama\nHapus Pintu", kunci);
        Dialog_Show(playerid, DoorManage, DIALOG_STYLE_LIST, title, list, "Pilih", "Tutup");
    }
    else
    {
        new info[256];
        format(info, sizeof(info), "Pemilik: %s\nStatus: %s\n\nTekan ENTER di depan pintu untuk masuk/keluar.", owner, status);
        Dialog_Show(playerid, DoorPublic, DIALOG_STYLE_MSGBOX, title, info, "Tutup", "");
    }
    return 1;
}

// Door_CmdInfo: /doorinfo — info & kelola pintu terdekat.
stock Door_CmdInfo(playerid)
{
    new slot = Door_NearestExt(playerid);
    if (slot == -1) slot = Door_NearestInt(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pintu di dekatmu.");
        return 1;
    }
    Door_ShowInfo(playerid, slot);
    return 1;
}

// Door_CmdLock: /lockdoor — kunci/buka pintu terdekat (pemilik/admin 3+).
stock Door_CmdLock(playerid)
{
    new slot = Door_NearestExt(playerid);
    if (slot == -1) slot = Door_NearestInt(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pintu di dekatmu.");
        return 1;
    }
    Door_ToggleLock(playerid, slot);
    return 1;
}

// Door_CmdDelete: /deletedoor — hapus pintu terdekat (admin 4+/pemilik, via konfirmasi).
stock Door_CmdDelete(playerid)
{
    new slot = Door_NearestExt(playerid);
    if (slot == -1) slot = Door_NearestInt(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Tidak ada pintu di dekatmu.");
        return 1;
    }
    if (!IsAdmin(playerid, 4) && !Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu tidak berhak menghapus pintu ini.");
        return 1;
    }
    pDoorMenuSlot[playerid] = slot;
    new msg[160];
    format(msg, sizeof(msg),
        "Yakin ingin menghapus pintu #%d (\"%s\")?\n\nPintu di kedua sisi akan hilang selamanya.",
        drDBID[slot], drName[slot]);
    Dialog_Show(playerid, DoorDeleteConfirm, DIALOG_STYLE_MSGBOX, "Hapus Pintu", msg, "Hapus", "Batal");
    return 1;
}

// Door_LoadAll: memuat semua pintu dari database saat gamemode mulai.
stock Door_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT id, owner_type, owner_id, name, ext_x, ext_y, ext_z, ext_int, ext_vw, int_x, int_y, int_z, int_int, int_vw, locked FROM doors",
        "OnDoorLoaded");
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:DoorList - daftar pintu; pilih satu untuk melihat detail.
Dialog:DoorList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDoorListSlot[playerid][listitem];
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 1;
    Door_ShowInfo(playerid, slot);
    return 1;
}

// Dialog:DoorPublic - info pintu untuk pemain biasa (tanpa hak kelola).
Dialog:DoorPublic(playerid, response, listitem, inputtext[])
{
    return 1;
}

// Dialog:DoorManage - menu kelola pintu: kunci/buka, ganti nama, hapus.
Dialog:DoorManage(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDoorMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 1;
    if (!Door_CanManage(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu tidak berhak mengelola pintu ini.");
        return 1;
    }
    if (listitem == 0)
    {
        Door_ToggleLock(playerid, slot);
    }
    else if (listitem == 1)
    {
        Dialog_Show(playerid, DoorRename, DIALOG_STYLE_INPUT, "Ganti Nama Pintu",
            "Masukkan nama baru untuk pintu ini (2-31 karakter):", "Simpan", "Batal");
    }
    else if (listitem == 2)
    {
        new msg[160];
        format(msg, sizeof(msg),
            "Yakin ingin menghapus pintu #%d (\"%s\")?\n\nPintu di kedua sisi akan hilang selamanya.",
            drDBID[slot], drName[slot]);
        Dialog_Show(playerid, DoorDeleteConfirm, DIALOG_STYLE_MSGBOX, "Hapus Pintu", msg, "Hapus", "Batal");
    }
    return 1;
}

// Dialog:DoorRename - input nama baru pintu.
Dialog:DoorRename(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDoorMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 1;
    Door_Rename(playerid, slot, inputtext);
    return 1;
}

// Dialog:DoorDeleteConfirm - konfirmasi sebelum pintu dihapus.
Dialog:DoorDeleteConfirm(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    new slot = pDoorMenuSlot[playerid];
    if (slot < 0 || slot >= MAX_DOOR || !drExists[slot]) return 1;
    Door_Delete(playerid, slot);
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnDoorLoaded: mengisi slot pintu dari database lalu spawn pickup+label.
public OnDoorLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_DOOR; i++)
    {
        cache_get_value_name_int(i, "id", tmp);          drDBID[i] = tmp;
        cache_get_value_name_int(i, "owner_type", tmp);   drOwnerType[i] = tmp;
        cache_get_value_name_int(i, "owner_id", tmp);     drOwnerID[i] = tmp;
        cache_get_value_name(i, "name", drName[i], sizeof(drName[]));
        cache_get_value_name_float(i, "ext_x", ftmp);     drExtX[i] = ftmp;
        cache_get_value_name_float(i, "ext_y", ftmp);     drExtY[i] = ftmp;
        cache_get_value_name_float(i, "ext_z", ftmp);     drExtZ[i] = ftmp;
        cache_get_value_name_int(i, "ext_int", tmp);      drExtInt[i] = tmp;
        cache_get_value_name_int(i, "ext_vw", tmp);       drExtVW[i] = tmp;
        cache_get_value_name_float(i, "int_x", ftmp);     drIntX[i] = ftmp;
        cache_get_value_name_float(i, "int_y", ftmp);     drIntY[i] = ftmp;
        cache_get_value_name_float(i, "int_z", ftmp);     drIntZ[i] = ftmp;
        cache_get_value_name_int(i, "int_int", tmp);      drIntInt[i] = tmp;
        cache_get_value_name_int(i, "int_vw", tmp);       drIntVW[i] = tmp;
        cache_get_value_name_int(i, "locked", tmp);       drLocked[i] = tmp;
        drExists[i] = 1;
        drExtLabelOn[i] = false;
        drIntLabelOn[i] = false;
        Door_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d pintu dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnDoorCreated: setelah INSERT pintu berhasil, isi slot lalu spawn pickup+label.
public OnDoorCreated(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = Door_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot pintu penuh (maksimal 100).");
        pDoorStep[playerid] = 0;
        return 1;
    }
    drExists[slot] = 1;
    drDBID[slot] = cache_insert_id();
    drOwnerType[slot] = pDoorType[playerid];
    drOwnerID[slot] = pDoorOwnerID[playerid];
    format(drName[slot], sizeof(drName[]), "%s", pDoorName[playerid]);
    drExtX[slot] = pDoorExtX[playerid];
    drExtY[slot] = pDoorExtY[playerid];
    drExtZ[slot] = pDoorExtZ[playerid];
    drExtInt[slot] = pDoorExtInt[playerid];
    drExtVW[slot] = pDoorExtVW[playerid];
    GetPlayerPos(playerid, drIntX[slot], drIntY[slot], drIntZ[slot]);
    drIntInt[slot] = GetPlayerInterior(playerid);
    drIntVW[slot] = GetPlayerVirtualWorld(playerid);
    drLocked[slot] = 0;
    drExtLabelOn[slot] = false;
    drIntLabelOn[slot] = false;
    pDoorStep[playerid] = 0;
    Door_Spawn(slot);
    new msg[160];
    format(msg, sizeof(msg), "Pintu #%d (\"%s\") berhasil dibuat. Tekan ENTER di depan pintu untuk masuk.",
        drDBID[slot], drName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}
