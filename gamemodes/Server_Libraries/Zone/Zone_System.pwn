//================================================================
// Society Roleplay - Zone_System
// Zona dinamis: area persegi yang dibuat admin (tipe Greenzone /
// Zona Bahaya), tersimpan di tabel zones.
// Greenzone: damage dibatalkan & tembakan dinonaktifkan di dalam
// area (dicek di OnPlayerTakeDamage / OnPlayerWeaponShot).
// Zona Bahaya: hanya penanda area berbahaya (damage tetap jalan).
// Setiap zona tampil sebagai gangzone berwarna + label 3D, dan
// pemain yang masuk area melihat textdraw nama zona di layar.
// Fitur: /createzone (admin 3+), /zones (daftar + detail), /deletezone
// (admin 4+, berdiri di dalam zona).
// Di-include dari gamemodes/Society_Main.pwn (setelah Family).
//================================================================

#if defined _zone_system_included
    #endinput
#endif
#define _zone_system_included

//==== KONSTANTA ====
#define MAX_ZONE 30
#define ZONE_HALF_SIZE 50.0  // setengah sisi persegi (100x100 meter)
#define ZONE_TYPE_GREEN 0    // greenzone: aman, tanpa damage & tembakan
#define ZONE_TYPE_RED 1      // zona bahaya: penanda area berbahaya

#define ZONE_GZ_COLOR_GREEN 0x00CC3366 // hijau transparan
#define ZONE_GZ_COLOR_RED 0xCC330066   // merah transparan

//==== DATA ZONA ====
new zoneExists[MAX_ZONE];            // 1 jika slot terisi
new zoneDBID[MAX_ZONE];              // id baris di tabel zones
new zoneName[MAX_ZONE][32];          // nama zona
new zoneType[MAX_ZONE];              // 0 = Greenzone, 1 = Zona Bahaya
new Float:zoneMinX[MAX_ZONE];        // batas area persegi
new Float:zoneMinY[MAX_ZONE];
new Float:zoneMaxX[MAX_ZONE];
new Float:zoneMaxY[MAX_ZONE];
new zoneGZ[MAX_ZONE];                // id gangzone SA-MP (-1 = belum dibuat)
new Text3D:zoneLabel[MAX_ZONE];      // label 3D di tengah zona

// Data sementara per pemain.
new pZoneSlot[MAX_PLAYERS];          // slot zona tempat pemain berada (-1 = tidak ada)
new pZoneWarnCD[MAX_PLAYERS];        // cooldown peringatan tembakan (GetTickCount)
new PlayerText:zonePTD[MAX_PLAYERS]; // textdraw nama zona di layar
new bool:pZoneTDCreated[MAX_PLAYERS];// textdraw sudah dibuat atau belum
new pZoneListSlot[MAX_PLAYERS][MAX_ZONE]; // slot zona per baris dialog /zones
new pZoneListCount[MAX_PLAYERS];         // jumlah baris dialog /zones terakhir
new pZoneInfoSlot[MAX_PLAYERS];          // slot zona di dialog detail

//==== FORWARD ====
forward OnZoneLoaded();
forward OnZoneCreated(playerid, slot);
forward ZoneTick();

//================================================================
// UTIL ZONA
//================================================================

// Zone_FreeSlot: mencari slot zona kosong, -1 jika penuh.
stock Zone_FreeSlot()
{
    for (new i = 0; i < MAX_ZONE; i++)
    {
        if (!zoneExists[i]) return i;
    }
    return -1;
}

// Zone_TypeName: nama tipe zona untuk label/dialog.
stock Zone_TypeName(type, dest[], len)
{
    if (type == ZONE_TYPE_GREEN)
    {
        format(dest, len, "Greenzone");
    }
    else
    {
        format(dest, len, "Zona Bahaya");
    }
    return 1;
}

// Zone_InRect: cek apakah pemain berada di dalam persegi slot zona.
stock Zone_InRect(playerid, slot)
{
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 0;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    return (x >= zoneMinX[slot] && x <= zoneMaxX[slot]
        && y >= zoneMinY[slot] && y <= zoneMaxY[slot]);
}

// Zone_AtPlayer: slot zona tempat pemain berada, -1 jika di luar semua zona.
stock Zone_AtPlayer(playerid)
{
    for (new i = 0; i < MAX_ZONE; i++)
    {
        if (zoneExists[i] && Zone_InRect(playerid, i)) return i;
    }
    return -1;
}

// Zone_InGreenzone: true jika pemain sedang berada di dalam greenzone.
stock Zone_InGreenzone(playerid)
{
    new slot = Zone_AtPlayer(playerid);
    return (slot != -1 && zoneType[slot] == ZONE_TYPE_GREEN);
}

// Zone_BuildSlot: membuat/memperbarui gangzone & label 3D untuk slot zona.
stock Zone_BuildSlot(slot)
{
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 0;
    // Hapus tampilan lama bila ada.
    if (zoneGZ[slot] != -1)
    {
        GangZoneDestroy(zoneGZ[slot]);
        zoneGZ[slot] = -1;
    }
    if (zoneLabel[slot] != Text3D:INVALID_3DTEXT_ID)
    {
        Delete3DTextLabel(zoneLabel[slot]);
        zoneLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    }
    zoneGZ[slot] = GangZoneCreate(zoneMinX[slot], zoneMinY[slot],
        zoneMaxX[slot], zoneMaxY[slot]);
    if (zoneGZ[slot] != -1)
    {
        GangZoneShowForAll(zoneGZ[slot],
            zoneType[slot] == ZONE_TYPE_GREEN ? ZONE_GZ_COLOR_GREEN : ZONE_GZ_COLOR_RED);
    }
    new tname[16], text[96];
    Zone_TypeName(zoneType[slot], tname, sizeof(tname));
    new colorhex[9];
    if (zoneType[slot] == ZONE_TYPE_GREEN)
    {
        format(colorhex, sizeof(colorhex), "33CC33");
    }
    else
    {
        format(colorhex, sizeof(colorhex), "CC3333");
    }
    format(text, sizeof(text), "{%s}[%s]{FFFFFF}\n%s", colorhex, tname, zoneName[slot]);
    new Float:cx = (zoneMinX[slot] + zoneMaxX[slot]) / 2.0;
    new Float:cy = (zoneMinY[slot] + zoneMaxY[slot]) / 2.0;
    zoneLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF, cx, cy, 10.0, 40.0, 0, 0);
    return 1;
}

// Zone_Delete: menghapus zona dari dunia & database.
stock Zone_Delete(slot)
{
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 0;
    if (zoneGZ[slot] != -1)
    {
        GangZoneDestroy(zoneGZ[slot]);
        zoneGZ[slot] = -1;
    }
    if (zoneLabel[slot] != Text3D:INVALID_3DTEXT_ID)
    {
        Delete3DTextLabel(zoneLabel[slot]);
        zoneLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    }
    zoneExists[slot] = 0;
    // Pemain yang sedang di dalam zona disembunyikan textdraw-nya.
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && pZoneSlot[p] == slot)
        {
            pZoneSlot[p] = -1;
            Zone_TDHide(p);
        }
    }
    if (g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[96];
        mysql_format(g_SQL, query, sizeof(query),
            "DELETE FROM zones WHERE id = %d", zoneDBID[slot]);
        mysql_tquery(g_SQL, query);
    }
    return 1;
}

//================================================================
// TEXTDRAW ZONA
//================================================================

// Zone_TDCreate: membuat textdraw nama zona (atas layar) untuk pemain.
stock Zone_TDCreate(playerid)
{
    if (pZoneTDCreated[playerid]) return 1;
    zonePTD[playerid] = CreatePlayerTextDraw(playerid, 320.0, 20.0, "GREENZONE");
    PlayerTextDrawFont(playerid, zonePTD[playerid], 2);
    PlayerTextDrawLetterSize(playerid, zonePTD[playerid], 0.5, 2.2);
    PlayerTextDrawSetOutline(playerid, zonePTD[playerid], 1);
    PlayerTextDrawSetProportional(playerid, zonePTD[playerid], 1);
    PlayerTextDrawAlignment(playerid, zonePTD[playerid], 2);
    PlayerTextDrawColor(playerid, zonePTD[playerid], 0x33CC33FF);
    pZoneTDCreated[playerid] = true;
    return 1;
}

// Zone_TDShow: menampilkan textdraw zona sesuai slot zona.
stock Zone_TDShow(playerid, slot)
{
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 0;
    new tname[16];
    Zone_TypeName(zoneType[slot], tname, sizeof(tname));
    if (UI_IsCef(playerid))
    {
        return UI_HudZone(playerid, tname, zoneType[slot] == ZONE_TYPE_GREEN);
    }
    Zone_TDCreate(playerid);
    PlayerTextDrawSetString(playerid, zonePTD[playerid], tname);
    PlayerTextDrawColor(playerid, zonePTD[playerid],
        zoneType[slot] == ZONE_TYPE_GREEN ? 0x33CC33FF : 0xCC3333FF);
    PlayerTextDrawShow(playerid, zonePTD[playerid]);
    return 1;
}

// Zone_TDHide: menyembunyikan textdraw zona.
stock Zone_TDHide(playerid)
{
    if (UI_IsCef(playerid)) return UI_HudZoneHide(playerid);
    if (!pZoneTDCreated[playerid]) return 1;
    PlayerTextDrawHide(playerid, zonePTD[playerid]);
    return 1;
}

// Zone_TDDestroy: menghapus textdraw zona (saat disconnect).
stock Zone_TDDestroy(playerid)
{
    if (!pZoneTDCreated[playerid]) return 1;
    PlayerTextDrawDestroy(playerid, zonePTD[playerid]);
    pZoneTDCreated[playerid] = false;
    return 1;
}

// ZoneTick: tiap 1 detik, cek zona tempat tiap pemain berada dan
// perbarui textdraw-nya.
public ZoneTick()
{
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (!IsPlayerConnected(p)) continue;
        if (!Society_PlayerData[p][sPLogged] || Society_PlayerData[p][sPCharID] <= 0)
        {
            if (pZoneSlot[p] != -1)
            {
                pZoneSlot[p] = -1;
                Zone_TDHide(p);
            }
            continue;
        }
        new slot = Zone_AtPlayer(p);
        if (slot != pZoneSlot[p])
        {
            pZoneSlot[p] = slot;
            if (slot == -1)
            {
                Zone_TDHide(p);
            }
            else
            {
                Zone_TDShow(p, slot);
                new tname[16], msg[96];
                Zone_TypeName(zoneType[slot], tname, sizeof(tname));
                format(msg, sizeof(msg), "Anda memasuki %s: %s", tname, zoneName[slot]);
                SendClientMessage(p, 0xCCCCCCFF, msg);
                if (zoneType[slot] == ZONE_TYPE_GREEN)
                {
                    SendClientMessage(p, 0x33CC33FF, "Kekerasan & senjata dilarang di dalam greenzone.");
                }
                else
                {
                    SendClientMessage(p, 0xCC3333FF, "Waspada: anda berada di Zona Bahaya.");
                }
            }
        }
    }
    return 1;
}

//================================================================
// PERLINDUNGAN GREENZONE
//================================================================

// Zone_OnTakeDamage: dipanggil dari OnPlayerTakeDamage. Damage di
// dalam greenzone (korban ATAU penyerang di dalam) dibatalkan.
stock Zone_OnTakeDamage(playerid, issuerid, Float:amount, weaponid)
{
    new victim_green = Zone_InGreenzone(playerid);
    new issuer_green = 0;
    if (issuerid != INVALID_PLAYER_ID && IsPlayerConnected(issuerid))
    {
        issuer_green = Zone_InGreenzone(issuerid);
    }
    if (!victim_green && !issuer_green) return 1;
    // Kembalikan nyawa yang hilang akibat damage.
    new Float:hp;
    GetPlayerHealth(playerid, hp);
    SetPlayerHealth(playerid, hp + amount);
    if (issuerid != INVALID_PLAYER_ID && IsPlayerConnected(issuerid))
    {
        SendClientMessage(issuerid, 0xCC3333FF, "Menyerang di greenzone dilarang!");
    }
    new msg[96];
    format(msg, sizeof(msg), "Greenzone melindungi anda dari serangan (senjata %d).", weaponid);
    SendClientMessage(playerid, 0x33CC33FF, msg);
    return 1;
}

// Zone_OnWeaponShot: dipanggil dari OnPlayerWeaponShot. Return 0 =
// tembakan dibatalkan (di dalam greenzone).
stock Zone_OnWeaponShot(playerid)
{
    if (!Zone_InGreenzone(playerid)) return 1;
    // Batasi spam peringatan: maksimal 1x per 3 detik.
    new now = GetTickCount();
    if (now - pZoneWarnCD[playerid] >= 3000)
    {
        pZoneWarnCD[playerid] = now;
        SendClientMessage(playerid, 0xCC3333FF, "Menembak di greenzone dilarang!");
    }
    return 0;
}

//================================================================
// DATABASE
//================================================================

// Zone_LoadAll: memuat semua zona dari database saat gamemode mulai.
stock Zone_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT id, name, type, min_x, min_y, max_x, max_y FROM zones",
        "OnZoneLoaded");
    return 1;
}

public OnZoneLoaded()
{
    new rows = cache_num_rows(), tmp, count = 0;
    for (new i = 0; i < rows && i < MAX_ZONE; i++)
    {
        cache_get_value_name_int(i, "id", tmp);   zoneDBID[i] = tmp;
        cache_get_value_name(i, "name", zoneName[i], sizeof(zoneName[]));
        cache_get_value_name_int(i, "type", tmp);  zoneType[i] = tmp;
        new Float:f;
        cache_get_value_name_float(i, "min_x", f); zoneMinX[i] = f;
        cache_get_value_name_float(i, "min_y", f); zoneMinY[i] = f;
        cache_get_value_name_float(i, "max_x", f); zoneMaxX[i] = f;
        cache_get_value_name_float(i, "max_y", f); zoneMaxY[i] = f;
        zoneGZ[i] = -1;
        zoneLabel[i] = Text3D:INVALID_3DTEXT_ID;
        zoneExists[i] = 1;
        Zone_BuildSlot(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d zona dimuat dari database.", count);
    print(msg);
    return 1;
}

// Zone_Create: admin membuat zona baru di posisinya (persegi
// 100x100 meter). Slot dicadangkan langsung supaya dua pembuatan
// cepat tidak berebut slot yang sama; id DB diisi di OnZoneCreated.
stock Zone_Create(playerid, const name[], type)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new slot = Zone_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, 0xCC3333FF, "Slot zona penuh, hapus zona lama dulu.");
        return 0;
    }
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    zoneExists[slot] = 1;
    zoneDBID[slot] = 0;
    format(zoneName[slot], sizeof(zoneName[]), "%s", name);
    zoneType[slot] = type;
    zoneMinX[slot] = x - ZONE_HALF_SIZE;
    zoneMinY[slot] = y - ZONE_HALF_SIZE;
    zoneMaxX[slot] = x + ZONE_HALF_SIZE;
    zoneMaxY[slot] = y + ZONE_HALF_SIZE;
    zoneGZ[slot] = -1;
    zoneLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    new query[512];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO zones (name, type, min_x, min_y, max_x, max_y) VALUES ('%e', %d, %f, %f, %f, %f)",
        name, type, zoneMinX[slot], zoneMinY[slot], zoneMaxX[slot], zoneMaxY[slot]);
    mysql_tquery(g_SQL, query, "OnZoneCreated", "dd", playerid, slot);
    return 1;
}

// OnZoneCreated: setelah INSERT zona berhasil, isi id DB & tampilkan
// gangzone + label 3D.
public OnZoneCreated(playerid, slot)
{
    if (slot < 0 || slot >= MAX_ZONE) return 1;
    if (!zoneExists[slot]) return 1;
    zoneDBID[slot] = cache_insert_id();
    Zone_BuildSlot(slot);
    if (IsPlayerConnected(playerid))
    {
        new tname[16], msg[128];
        Zone_TypeName(zoneType[slot], tname, sizeof(tname));
        format(msg, sizeof(msg), "%s \"%s\" berhasil dibuat (100x100 meter di sekelilingmu).", tname, zoneName[slot]);
        SendClientMessage(playerid, 0x33CC33FF, msg);
    }
    return 1;
}

//================================================================
// PERINTAH (dipanggil dari OnPlayerCommandText di Society_Main)
//================================================================

// Zone_CmdCreate: /createzone [nama] [tipe] — admin 3+.
// Tipe: 0 = Greenzone, 1 = Zona Bahaya. Spasi pada nama diganti _.
stock Zone_CmdCreate(playerid, const cmdtext[], idx)
{
    if (!IsAdmin(playerid, 3))
    {
        SendClientMessage(playerid, 0xCC3333FF, "Hanya admin level 3+ yang bisa membuat zona.");
        return 1;
    }
    new name[32], stype[8];
    new i = idx;
    // Ambil nama zona (satu kata, spasi diganti _).
    new n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(name) - 1)
    {
        name[n++] = (cmdtext[i] == '_') ? ' ' : cmdtext[i];
        i++;
    }
    name[n] = EOS;
    // Lewati spasi, ambil tipe.
    while (cmdtext[i] == ' ') i++;
    n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(stype) - 1)
    {
        stype[n++] = cmdtext[i++];
    }
    stype[n] = EOS;
    if (name[0] == EOS || stype[0] == EOS)
    {
        SendClientMessage(playerid, 0xCCCCCCFF, "Gunakan: /createzone [nama] [tipe]");
        SendClientMessage(playerid, 0xCCCCCCFF, "Tipe: 0 = Greenzone (aman), 1 = Zona Bahaya");
        SendClientMessage(playerid, 0xCCCCCCFF, "Contoh: /createzone Balai_Kota 0 (spasi diganti _)");
        return 1;
    }
    if (!IsNumeric(stype))
    {
        SendClientMessage(playerid, 0xCC3333FF, "Tipe harus 0 (Greenzone) atau 1 (Zona Bahaya).");
        return 1;
    }
    new type = strval(stype);
    if (type != ZONE_TYPE_GREEN && type != ZONE_TYPE_RED)
    {
        SendClientMessage(playerid, 0xCC3333FF, "Tipe harus 0 (Greenzone) atau 1 (Zona Bahaya).");
        return 1;
    }
    Zone_Create(playerid, name, type);
    return 1;
}

// Zone_CmdList: /zones — dialog daftar semua zona.
stock Zone_CmdList(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, 0xCC3333FF, "Anda belum memilih karakter.");
        return 1;
    }
    new list[1024], tname[16], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_ZONE; i++)
    {
        if (!zoneExists[i]) continue;
        Zone_TypeName(zoneType[i], tname, sizeof(tname));
        new line[96];
        format(line, sizeof(line), "ID %d | %s | %s\n", zoneDBID[i], tname, zoneName[i]);
        strcat(list, line, sizeof(list));
        pZoneListSlot[playerid][count] = i; // baris dialog -> slot zona
        count++;
    }
    pZoneListCount[playerid] = count;
    if (count == 0)
    {
        SendClientMessage(playerid, 0xCCCCCCFF, "Belum ada zona di server ini.");
        return 1;
    }
    Dialog_Show(playerid, ZoneListHandler, DIALOG_STYLE_LIST,
        "Zona di Server", list, "Detail", "Tutup");
    return 1;
}

// Zone_CmdDelete: /deletezone — admin 4+, hapus zona tempat admin berdiri.
stock Zone_CmdDelete(playerid)
{
    if (!IsAdmin(playerid, 4))
    {
        SendClientMessage(playerid, 0xCC3333FF, "Hanya admin level 4+ yang bisa menghapus zona.");
        return 1;
    }
    new slot = Zone_AtPlayer(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, 0xCCCCCCFF, "Berdirilah di dalam zona yang ingin dihapus, lalu ulangi perintah.");
        return 1;
    }
    new msg[128];
    format(msg, sizeof(msg), "Zona \"%s\" (ID %d) dihapus.", zoneName[slot], zoneDBID[slot]);
    Zone_Delete(slot);
    SendClientMessage(playerid, 0x33CC33FF, msg);
    return 1;
}

//================================================================
// DIALOG (easydialog)
//================================================================

// ZoneListHandler: daftar zona -> tampilkan dialog detail.
Dialog:ZoneListHandler(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (listitem < 0 || listitem >= pZoneListCount[playerid]) return 1;
    new slot = pZoneListSlot[playerid][listitem];
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 1;
    pZoneInfoSlot[playerid] = slot;
    new tname[16], info[512];
    Zone_TypeName(zoneType[slot], tname, sizeof(tname));
    format(info, sizeof(info),
        "Nama: %s\nTipe: %s\n\nBatas area:\n  Min X: %.1f | Min Y: %.1f\n  Max X: %.1f | Max Y: %.1f\n  (persegi %.0fx%.0f meter)\n\n%s",
        zoneName[slot], tname,
        zoneMinX[slot], zoneMinY[slot], zoneMaxX[slot], zoneMaxY[slot],
        (zoneMaxX[slot] - zoneMinX[slot]), (zoneMaxY[slot] - zoneMinY[slot]),
        zoneType[slot] == ZONE_TYPE_GREEN ?
            "Damage & tembakan dinonaktifkan di dalam area ini." :
            "Area berbahaya: damage tetap berjalan, waspadalah.");
    if (IsAdmin(playerid, 4))
    {
        Dialog_Show(playerid, ZoneInfoHandler, DIALOG_STYLE_MSGBOX,
            "Detail Zona", info, "Hapus Zona", "Tutup");
    }
    else
    {
        Dialog_Show(playerid, ZoneInfoHandler, DIALOG_STYLE_MSGBOX,
            "Detail Zona", info, "Tutup", "");
    }
    return 1;
}

// ZoneInfoHandler: dialog detail zona; admin 4+ bisa menghapus.
Dialog:ZoneInfoHandler(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    // response=1 + admin 4+ = tombol "Hapus Zona" (tombol utama).
    if (!IsAdmin(playerid, 4)) return 1;
    new slot = pZoneInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_ZONE || !zoneExists[slot]) return 1;
    new msg[128];
    format(msg, sizeof(msg), "Zona \"%s\" (ID %d) dihapus.", zoneName[slot], zoneDBID[slot]);
    Zone_Delete(slot);
    SendClientMessage(playerid, 0x33CC33FF, msg);
    return 1;
}

// Zone_OnConnect: reset data sementara zona (dipanggil dari OnPlayerConnect).
stock Zone_OnConnect(playerid)
{
    pZoneSlot[playerid] = -1;
    pZoneWarnCD[playerid] = 0;
    pZoneTDCreated[playerid] = false;
    pZoneListCount[playerid] = 0;
    pZoneInfoSlot[playerid] = -1;
    return 1;
}

// Zone_OnDisconnect: bersihkan textdraw zona (dipanggil dari OnPlayerDisconnect).
stock Zone_OnDisconnect(playerid)
{
    Zone_TDDestroy(playerid);
    pZoneSlot[playerid] = -1;
    return 1;
}
