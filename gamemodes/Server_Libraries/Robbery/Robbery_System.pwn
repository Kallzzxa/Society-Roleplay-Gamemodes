//================================================================
// Society Roleplay - Robbery_System
// Sistem rampok ala SA-MP (badside): /rob di titik rampok ->
// progress bar textdraw berjalan, alarm otomatis ke polisi (LSPD)
// yang online, cooldown per titik, hasil berupa UANG KOTOR
// (characters.dirty_money, terlihat di /money & /stats).
//
// Admin: /createrobspot [nama] [tipe] (level 3+) -> pickup + label 3D.
// Pemain: /rob (dekat titik), /robspots (daftar + detail; admin 4+
// bisa hapus), /deleterobspot (admin 4+, berdiri di dekat titik).
// Perampok harus tetap di dekat titik & jalan kaki sampai progress
// penuh; pergi/mati/naik kendaraan/disconnect = gagal.
// Tabel: robbery_spots. Modul:
// gamemodes/Server_Libraries/Robbery/Robbery_System.pwn
// Di-include dari gamemodes/Society_Main.pwn (setelah Door).
//================================================================

#if defined _robbery_system_included
    #endinput
#endif
#define _robbery_system_included

//==== KONSTANTA ====
#define MAX_ROBSPOT 20
#define ROB_RADIUS 12.0          // jarak maksimal dari titik saat merampok

#define ROB_TYPE_BANK 0
#define ROB_TYPE_TOKO 1
#define ROB_TYPE_ATM 2
#define ROB_TYPES 3

// Default per tipe: nama, hadiah min/maks, durasi (detik), cooldown (detik).
new Rob_TypeName[ROB_TYPES][8] = { "Bank", "Toko", "ATM" };
new Rob_DefMin[ROB_TYPES] = { 2000000, 500000, 200000 };
new Rob_DefMax[ROB_TYPES] = { 5000000, 1500000, 600000 };
new Rob_DefDur[ROB_TYPES] = { 90, 45, 25 };
new Rob_DefCD[ROB_TYPES]  = { 7200, 3600, 1800 };

//==== DATA TITIK RAMPOK ====
new robExists[MAX_ROBSPOT];          // 1 jika slot terisi
new robDBID[MAX_ROBSPOT];            // id baris di tabel robbery_spots
new robName[MAX_ROBSPOT][32];        // nama titik
new robType[MAX_ROBSPOT];            // 0=Bank, 1=Toko, 2=ATM
new robRewardMin[MAX_ROBSPOT];
new robRewardMax[MAX_ROBSPOT];
new robDuration[MAX_ROBSPOT];        // detik progress
new robCooldown[MAX_ROBSPOT];        // detik cooldown per titik
new robLastRobbed[MAX_ROBSPOT];      // unix timestamp rampok terakhir
new Float:robX[MAX_ROBSPOT];
new Float:robY[MAX_ROBSPOT];
new Float:robZ[MAX_ROBSPOT];
new robPickup[MAX_ROBSPOT];
new Text3D:robLabel[MAX_ROBSPOT];

// Data per pemain.
new pRobSlot[MAX_PLAYERS];           // slot titik yang dirampok (-1 = tidak)
new pRobProgress[MAX_PLAYERS];       // detik progress berjalan
new PlayerText:robPTD[MAX_PLAYERS];  // textdraw progress bar
new bool:pRobTDCreated[MAX_PLAYERS];
new pRobListSlot[MAX_PLAYERS][MAX_ROBSPOT];
new pRobListCount[MAX_PLAYERS];
new pRobInfoSlot[MAX_PLAYERS];

//==== FORWARD ====
forward OnRobSpotLoaded();
forward OnRobSpotCreated(playerid, slot);
forward RobberyTick();

//================================================================
// UTIL
//================================================================

// Rob_FreeSlot: slot titik kosong, -1 jika penuh.
stock Rob_FreeSlot()
{
    for (new i = 0; i < MAX_ROBSPOT; i++)
    {
        if (!robExists[i]) return i;
    }
    return -1;
}

// Rob_NearestSpot: slot titik terdekat dalam radius, -1 jika tidak ada.
stock Rob_NearestSpot(playerid, Float:radius)
{
    new best = -1;
    new Float:bestd = radius;
    for (new i = 0; i < MAX_ROBSPOT; i++)
    {
        if (!robExists[i]) continue;
        new Float:d = GetPlayerDistanceFromPoint(playerid, robX[i], robY[i], robZ[i]);
        if (d <= bestd)
        {
            bestd = d;
            best = i;
        }
    }
    return best;
}

// Rob_CooldownLeft: sisa cooldown titik (detik), 0 = siap dirampok.
stock Rob_CooldownLeft(slot)
{
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 0;
    new left = robCooldown[slot] - (gettime() - robLastRobbed[slot]);
    return (left > 0) ? left : 0;
}

// Rob_FormatCD: 3661 -> "1 jam 1 mnt"; 125 -> "2:05".
stock Rob_FormatCD(seconds, dest[], len)
{
    if (seconds >= 3600)
    {
        format(dest, len, "%d jam %d mnt", seconds / 3600, (seconds % 3600) / 60);
    }
    else if (seconds >= 60)
    {
        format(dest, len, "%d:%02d", seconds / 60, seconds % 60);
    }
    else
    {
        format(dest, len, "%d dtk", seconds);
    }
    return 1;
}

// Rob_RewardText: "Rp2.000.000 - Rp5.000.000" untuk label/dialog.
stock Rob_RewardText(slot, dest[], len)
{
    new mn[32], mx[32];
    FormatRupiah(robRewardMin[slot], mn, sizeof(mn));
    FormatRupiah(robRewardMax[slot], mx, sizeof(mx));
    format(dest, len, "%s - %s", mn, mx);
    return 1;
}

// Rob_BuildSlot: membuat/memperbarui pickup & label 3D titik rampok.
stock Rob_BuildSlot(slot)
{
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 0;
    if (robPickup[slot] != -1)
    {
        DestroyPickup(robPickup[slot]);
        robPickup[slot] = -1;
    }
    if (robLabel[slot] != Text3D:INVALID_3DTEXT_ID)
    {
        Delete3DTextLabel(robLabel[slot]);
        robLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    }
    robPickup[slot] = CreatePickup(1239, 1, robX[slot], robY[slot], robZ[slot], 0);
    new text[256], reward[64], cd[24];
    Rob_RewardText(slot, reward, sizeof(reward));
    format(text, sizeof(text),
        "{FF3333}[RAMPOK ID: %d]\n{FFFFFF}%s\n{FFFF00}Tipe: %s\n{FFFF00}Hadiah: %s\n",
        robDBID[slot], robName[slot], Rob_TypeName[robType[slot]], reward);
    new left = Rob_CooldownLeft(slot);
    if (left > 0)
    {
        Rob_FormatCD(left, cd, sizeof(cd));
        format(text, sizeof(text), "%s{FF9900}Cooldown: %s\n", text, cd);
    }
    format(text, sizeof(text), "%s{00CCFF}/rob untuk merampok", text);
    robLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        robX[slot], robY[slot], robZ[slot] + 1.0, 25.0, 0, 0);
    return 1;
}

// Rob_Delete: menghapus titik dari dunia & database.
stock Rob_Delete(slot)
{
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 0;
    if (robPickup[slot] != -1)
    {
        DestroyPickup(robPickup[slot]);
        robPickup[slot] = -1;
    }
    if (robLabel[slot] != Text3D:INVALID_3DTEXT_ID)
    {
        Delete3DTextLabel(robLabel[slot]);
        robLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    }
    // Batalkan pemain yang sedang merampok titik ini.
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && pRobSlot[p] == slot)
        {
            Rob_Cancel(p, "Titik rampok ini dihapus admin.");
        }
    }
    robExists[slot] = 0;
    if (g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[96];
        mysql_format(g_SQL, query, sizeof(query),
            "DELETE FROM robbery_spots WHERE id = %d", robDBID[slot]);
        mysql_tquery(g_SQL, query);
    }
    return 1;
}

// Rob_AlarmLSPD: kirim alarm perampokan ke semua fraksi tipe LSPD (0).
stock Rob_AlarmLSPD(slot)
{
    new msg[192];
    format(msg, sizeof(msg),
        "[ALARM] Perampokan di %s (%s)! Semua unit LSPD segera merapat!",
        robName[slot], Rob_TypeName[robType[slot]]);
    for (new i = 0; i < MAX_FACTION; i++)
    {
        if (fExists[i] && fType[i] == ROB_TYPE_BANK) // tipe fraksi 0 = LSPD
        {
            Faction_Broadcast(i, msg, 0x2D6CDFFF);
        }
    }
    return 1;
}

//================================================================
// PROGRESS BAR (textdraw oldschool + CEF)
//================================================================

// Rob_TDCreate: textdraw progress rampok (tengah bawah layar).
stock Rob_TDCreate(playerid)
{
    if (pRobTDCreated[playerid]) return 1;
    robPTD[playerid] = CreatePlayerTextDraw(playerid, 320.0, 400.0, "_");
    PlayerTextDrawFont(playerid, robPTD[playerid], 1);
    PlayerTextDrawLetterSize(playerid, robPTD[playerid], 0.35, 1.4);
    PlayerTextDrawSetOutline(playerid, robPTD[playerid], 1);
    PlayerTextDrawSetProportional(playerid, robPTD[playerid], 1);
    PlayerTextDrawAlignment(playerid, robPTD[playerid], 2);
    PlayerTextDrawColor(playerid, robPTD[playerid], COLOR_WHITE);
    pRobTDCreated[playerid] = true;
    return 1;
}

// Rob_TDUpdate: gambar ulang bar sesuai progress (0-100%).
stock Rob_TDUpdate(playerid, percent, const spotname[])
{
    if (UI_IsCef(playerid))
    {
        return UI_HudRobbery(playerid, spotname, percent);
    }
    if (!pRobTDCreated[playerid]) return 0;
    new bar[16], pos = 0, filled = percent / 10;
    if (filled > 10) filled = 10;
    for (new i = 0; i < 10; i++)
    {
        bar[pos++] = (i < filled) ? ('|') : ('-');
    }
    bar[pos] = EOS;
    new str[96];
    format(str, sizeof(str), "Merampok %s~n~~r~%s~w~~n~%d%%", spotname, bar, percent);
    PlayerTextDrawSetString(playerid, robPTD[playerid], str);
    return 1;
}

stock Rob_TDShow(playerid)
{
    if (UI_IsCef(playerid)) return 1; // bar dirender via HUD HTML
    Rob_TDCreate(playerid);
    PlayerTextDrawShow(playerid, robPTD[playerid]);
    return 1;
}

stock Rob_TDHide(playerid)
{
    if (UI_IsCef(playerid)) return UI_HudRobberyHide(playerid);
    if (!pRobTDCreated[playerid]) return 1;
    PlayerTextDrawHide(playerid, robPTD[playerid]);
    return 1;
}

stock Rob_TDDestroy(playerid)
{
    if (!pRobTDCreated[playerid]) return 1;
    PlayerTextDrawDestroy(playerid, robPTD[playerid]);
    pRobTDCreated[playerid] = false;
    return 1;
}

//================================================================
// ALUR RAMPOK
//================================================================

// Rob_Start: pemain memulai perampokan di slot titik. Return 1 = mulai.
stock Rob_Start(playerid, slot)
{
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 0;
    if (pRobSlot[playerid] != -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Kamu sudah merampok. Selesaikan dulu!");
        return 0;
    }
    new left = Rob_CooldownLeft(slot);
    if (left > 0)
    {
        new cd[24], msg[128];
        Rob_FormatCD(left, cd, sizeof(cd));
        format(msg, sizeof(msg), "Titik ini baru saja dirampok. Coba lagi dalam %s.", cd);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    if (GetPlayerState(playerid) != PLAYER_STATE_ONFOOT)
    {
        SendClientMessage(playerid, COLOR_RED, "Turun dari kendaraan dulu untuk merampok!");
        return 0;
    }
    pRobSlot[playerid] = slot;
    pRobProgress[playerid] = 0;
    Rob_TDShow(playerid);
    Rob_TDUpdate(playerid, 0, robName[slot]);
    Rob_AlarmLSPD(slot);
    new msg[192];
    format(msg, sizeof(msg),
        "Kamu mulai merampok %s! Tetap di dekat titik & jangan bergerak sampai selesai.",
        robName[slot]);
    SendClientMessage(playerid, COLOR_YELLOW, msg);
    SendClientMessage(playerid, COLOR_RED, "Alarm berbunyi! Polisi mungkin sudah tahu aksimu.");
    return 1;
}

// Rob_Cancel: batalkan perampokan pemain (pergi/mati/naik kendaraan/hapus).
stock Rob_Cancel(playerid, const reason[])
{
    if (pRobSlot[playerid] == -1) return 0;
    pRobSlot[playerid] = -1;
    pRobProgress[playerid] = 0;
    Rob_TDHide(playerid);
    SendClientMessage(playerid, COLOR_RED, reason);
    return 1;
}

// Rob_Complete: progress penuh -> beri hadiah uang kotor.
stock Rob_Complete(playerid)
{
    new slot = pRobSlot[playerid];
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot])
    {
        Rob_Cancel(playerid, "Perampokan gagal!");
        return 0;
    }
    new reward = robRewardMin[slot] + random(robRewardMax[slot] - robRewardMin[slot] + 1);
    pDirtyMoney[playerid] += reward;
    SaveCharacter(playerid); // simpan uang kotor langsung
    pRobSlot[playerid] = -1;
    pRobProgress[playerid] = 0;
    Rob_TDHide(playerid);
    robLastRobbed[slot] = gettime();
    if (g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[96];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE robbery_spots SET last_robbed = %d WHERE id = %d",
            robLastRobbed[slot], robDBID[slot]);
        mysql_tquery(g_SQL, query);
    }
    Rob_BuildSlot(slot); // perbarui label (status cooldown)
    new uang[32], msg[160];
    FormatRupiah(reward, uang, sizeof(uang));
    format(msg, sizeof(msg),
        "Perampokan berhasil! Kamu mendapatkan %s (UANG KOTOR).", uang);
    SendClientMessage(playerid, COLOR_YELLOW, msg);
    SendClientMessage(playerid, COLOR_GREY,
        "Uang kotor tersimpan & terlihat di /money. Hati-hati, polisi mengincarmu!");
    format(msg, sizeof(msg),
        "*** Perampokan di %s (%s) berhasil! Pelaku masih buron.",
        robName[slot], Rob_TypeName[robType[slot]]);
    SendClientMessageToAll(COLOR_RED, msg);
    return 1;
}

// RobberyTick: tiap 1 detik, majukan progress perampok & validasi.
public RobberyTick()
{
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (!IsPlayerConnected(p)) continue;
        new slot = pRobSlot[p];
        if (slot == -1) continue;
        if (!Society_PlayerData[p][sPLogged] || Society_PlayerData[p][sPCharID] <= 0
            || slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot])
        {
            Rob_Cancel(p, "Perampokan gagal!");
            continue;
        }
        new Float:hp;
        GetPlayerHealth(p, hp);
        if (hp <= 0.0)
        {
            Rob_Cancel(p, "Perampokan gagal! Kamu tewas.");
            continue;
        }
        if (GetPlayerState(p) != PLAYER_STATE_ONFOOT)
        {
            Rob_Cancel(p, "Perampokan gagal! Kamu naik kendaraan.");
            continue;
        }
        if (!IsPlayerInRangeOfPoint(p, ROB_RADIUS, robX[slot], robY[slot], robZ[slot]))
        {
            Rob_Cancel(p, "Perampokan gagal! Kamu terlalu jauh dari titik.");
            continue;
        }
        pRobProgress[p]++;
        if (pRobProgress[p] >= robDuration[slot])
        {
            Rob_Complete(p);
        }
        else
        {
            Rob_TDUpdate(p, (pRobProgress[p] * 100) / robDuration[slot], robName[slot]);
        }
    }
    return 1;
}

//================================================================
// DATABASE
//================================================================

stock Robbery_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT id, name, type, reward_min, reward_max, duration, cooldown, last_robbed, pos_x, pos_y, pos_z FROM robbery_spots",
        "OnRobSpotLoaded");
    return 1;
}

public OnRobSpotLoaded()
{
    new rows = cache_num_rows(), tmp = 0, count = 0;
    new Float:f = 0.0;
    for (new i = 0; i < rows && i < MAX_ROBSPOT; i++)
    {
        cache_get_value_name_int(i, "id", tmp);          robDBID[i] = tmp;
        cache_get_value_name(i, "name", robName[i], sizeof(robName[]));
        cache_get_value_name_int(i, "type", tmp);        robType[i] = tmp;
        cache_get_value_name_int(i, "reward_min", tmp);  robRewardMin[i] = tmp;
        cache_get_value_name_int(i, "reward_max", tmp);  robRewardMax[i] = tmp;
        cache_get_value_name_int(i, "duration", tmp);    robDuration[i] = tmp;
        cache_get_value_name_int(i, "cooldown", tmp);    robCooldown[i] = tmp;
        cache_get_value_name_int(i, "last_robbed", tmp); robLastRobbed[i] = tmp;
        cache_get_value_name_float(i, "pos_x", f);       robX[i] = f;
        cache_get_value_name_float(i, "pos_y", f);       robY[i] = f;
        cache_get_value_name_float(i, "pos_z", f);       robZ[i] = f;
        robPickup[i] = -1;
        robLabel[i] = Text3D:INVALID_3DTEXT_ID;
        robExists[i] = 1;
        Rob_BuildSlot(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d titik rampok dimuat dari database.", count);
    print(msg);
    return 1;
}

// Rob_Create: admin membuat titik rampok di posisinya.
stock Rob_Create(playerid, const name[], type)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new slot = Rob_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot titik rampok penuh, hapus yang lama dulu.");
        return 0;
    }
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    robExists[slot] = 1;
    robDBID[slot] = 0;
    format(robName[slot], sizeof(robName[]), "%s", name);
    robType[slot] = type;
    robRewardMin[slot] = Rob_DefMin[type];
    robRewardMax[slot] = Rob_DefMax[type];
    robDuration[slot] = Rob_DefDur[type];
    robCooldown[slot] = Rob_DefCD[type];
    robLastRobbed[slot] = 0;
    robX[slot] = x;
    robY[slot] = y;
    robZ[slot] = z;
    robPickup[slot] = -1;
    robLabel[slot] = Text3D:INVALID_3DTEXT_ID;
    new query[512];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO robbery_spots (name, type, reward_min, reward_max, duration, cooldown, last_robbed, pos_x, pos_y, pos_z) VALUES ('%e', %d, %d, %d, %d, %d, 0, %f, %f, %f)",
        name, type, robRewardMin[slot], robRewardMax[slot],
        robDuration[slot], robCooldown[slot], x, y, z);
    mysql_tquery(g_SQL, query, "OnRobSpotCreated", "dd", playerid, slot);
    return 1;
}

public OnRobSpotCreated(playerid, slot)
{
    if (slot < 0 || slot >= MAX_ROBSPOT) return 1;
    if (!robExists[slot]) return 1;
    robDBID[slot] = cache_insert_id();
    Rob_BuildSlot(slot);
    if (IsPlayerConnected(playerid))
    {
        new reward[64], msg[192];
        Rob_RewardText(slot, reward, sizeof(reward));
        format(msg, sizeof(msg),
            "Titik rampok \"%s\" (%s) dibuat. Hadiah %s, durasi %d dtk.",
            robName[slot], Rob_TypeName[robType[slot]], reward, robDuration[slot]);
        SendClientMessage(playerid, COLOR_GREEN, msg);
    }
    return 1;
}

//================================================================
// PERINTAH (dipanggil dari OnPlayerCommandText di Society_Main)
//================================================================

// Rob_CmdCreate: /createrobspot [nama] [tipe] — admin 3+.
// Tipe: 0 = Bank, 1 = Toko, 2 = ATM. Spasi pada nama diganti _.
stock Rob_CmdCreate(playerid, const cmdtext[], idx)
{
    if (!IsAdmin(playerid, 3))
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya admin level 3+ yang bisa membuat titik rampok.");
        return 1;
    }
    new name[32], stype[8];
    new i = idx, n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(name) - 1)
    {
        name[n++] = (cmdtext[i] == '_') ? ' ' : cmdtext[i];
        i++;
    }
    name[n] = EOS;
    while (cmdtext[i] == ' ') i++;
    n = 0;
    while (cmdtext[i] != EOS && cmdtext[i] != ' ' && n < sizeof(stype) - 1)
    {
        stype[n++] = cmdtext[i++];
    }
    stype[n] = EOS;
    if (name[0] == EOS || stype[0] == EOS)
    {
        SendClientMessage(playerid, COLOR_GREY, "Gunakan: /createrobspot [nama] [tipe]");
        SendClientMessage(playerid, COLOR_GREY, "Tipe: 0 = Bank, 1 = Toko, 2 = ATM");
        SendClientMessage(playerid, COLOR_GREY, "Contoh: /createrobspot Bank_Fleeca 0 (spasi diganti _)");
        return 1;
    }
    if (!IsNumeric(stype))
    {
        SendClientMessage(playerid, COLOR_RED, "Tipe harus 0 (Bank), 1 (Toko), atau 2 (ATM).");
        return 1;
    }
    new type = strval(stype);
    if (type < 0 || type >= ROB_TYPES)
    {
        SendClientMessage(playerid, COLOR_RED, "Tipe harus 0 (Bank), 1 (Toko), atau 2 (ATM).");
        return 1;
    }
    Rob_Create(playerid, name, type);
    return 1;
}

// Rob_CmdRob: /rob — mulai merampok titik terdekat.
stock Rob_CmdRob(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new slot = Rob_NearestSpot(playerid, ROB_RADIUS);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_GREY, "Tidak ada titik rampok di dekatmu. Cari label [RAMPOK].");
        return 1;
    }
    Rob_Start(playerid, slot);
    return 1;
}

// Rob_CmdList: /robspots — dialog daftar semua titik rampok.
stock Rob_CmdList(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda belum memilih karakter.");
        return 1;
    }
    new list[1024], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_ROBSPOT; i++)
    {
        if (!robExists[i]) continue;
        new line[128], cd[24], reward[64];
        Rob_RewardText(i, reward, sizeof(reward));
        new left = Rob_CooldownLeft(i);
        if (left > 0)
        {
            Rob_FormatCD(left, cd, sizeof(cd));
        }
        else
        {
            format(cd, sizeof(cd), "Siap");
        }
        format(line, sizeof(line), "ID %d | %s (%s) | %s\n",
            robDBID[i], robName[i], Rob_TypeName[robType[i]], cd);
        strcat(list, line, sizeof(list));
        pRobListSlot[playerid][count] = i;
        count++;
    }
    pRobListCount[playerid] = count;
    if (count == 0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Belum ada titik rampok di server ini.");
        return 1;
    }
    Dialog_Show(playerid, RobListHandler, DIALOG_STYLE_LIST,
        "Titik Rampok", list, "Detail", "Tutup");
    return 1;
}

// Rob_CmdDelete: /deleterobspot — admin 4+, berdiri di dekat titik.
stock Rob_CmdDelete(playerid)
{
    if (!IsAdmin(playerid, 4))
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya admin level 4+ yang bisa menghapus titik rampok.");
        return 1;
    }
    new slot = Rob_NearestSpot(playerid, ROB_RADIUS);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_GREY, "Berdirilah di dekat titik rampok yang ingin dihapus.");
        return 1;
    }
    new msg[128];
    format(msg, sizeof(msg), "Titik rampok \"%s\" (ID %d) dihapus.", robName[slot], robDBID[slot]);
    Rob_Delete(slot);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

//================================================================
// DIALOG (easydialog)
//================================================================

// RobListHandler: daftar titik -> dialog detail.
Dialog:RobListHandler(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (listitem < 0 || listitem >= pRobListCount[playerid]) return 1;
    new slot = pRobListSlot[playerid][listitem];
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 1;
    pRobInfoSlot[playerid] = slot;
    new reward[64], cd[24], info[512];
    Rob_RewardText(slot, reward, sizeof(reward));
    new left = Rob_CooldownLeft(slot);
    if (left > 0) Rob_FormatCD(left, cd, sizeof(cd));
    else format(cd, sizeof(cd), "Siap dirampok");
    format(info, sizeof(info),
        "Nama: %s\nTipe: %s\nHadiah: %s (uang kotor)\nDurasi rampok: %d detik\nStatus: %s\n\nBerdiri di dekat titik lalu ketik /rob.\nTetap di dekat titik & jalan kaki sampai progress penuh.",
        robName[slot], Rob_TypeName[robType[slot]], reward,
        robDuration[slot], cd);
    if (IsAdmin(playerid, 4))
    {
        Dialog_Show(playerid, RobInfoHandler, DIALOG_STYLE_MSGBOX,
            "Detail Titik Rampok", info, "Hapus Titik", "Tutup");
    }
    else
    {
        Dialog_Show(playerid, RobInfoHandler, DIALOG_STYLE_MSGBOX,
            "Detail Titik Rampok", info, "Tutup", "");
    }
    return 1;
}

// RobInfoHandler: dialog detail; admin 4+ bisa menghapus.
Dialog:RobInfoHandler(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    if (!IsAdmin(playerid, 4)) return 1;
    new slot = pRobInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_ROBSPOT || !robExists[slot]) return 1;
    new msg[128];
    format(msg, sizeof(msg), "Titik rampok \"%s\" (ID %d) dihapus.", robName[slot], robDBID[slot]);
    Rob_Delete(slot);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Robbery_OnConnect: reset data sementara rampok.
stock Robbery_OnConnect(playerid)
{
    pRobSlot[playerid] = -1;
    pRobProgress[playerid] = 0;
    pRobTDCreated[playerid] = false;
    pRobListCount[playerid] = 0;
    pRobInfoSlot[playerid] = -1;
    return 1;
}

// Robbery_OnDisconnect: batalkan rampok & hapus textdraw.
stock Robbery_OnDisconnect(playerid)
{
    if (pRobSlot[playerid] != -1)
    {
        pRobSlot[playerid] = -1;
        pRobProgress[playerid] = 0;
    }
    Rob_TDDestroy(playerid);
    return 1;
}
