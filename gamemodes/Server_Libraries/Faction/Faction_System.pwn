//================================================================
// Society Roleplay - Faction_System
// Fraksi dinamis: dibuat oleh admin, markas berupa pickup + label 3D,
// keanggotaan tersimpan di kolom characters (faction_id, faction_rank).
// Fitur: /finvite & /fkick (pimpinan), /setrank, /f chat fraksi,
// /duty (seragam + senjata dinas sesuai tipe fraksi), kas fraksi
// (/fdeposit & /fwithdraw). Tipe: LSPD, EMS, Pemerintah, Montir, News.
// Di-include dari gamemodes/Society_Main.pwn (setelah Utils & Admin).
//================================================================

#if defined _faction_system_included
    #endinput
#endif
#define _faction_system_included

//==== KONSTANTA ====
#define MAX_FACTION 20
#define FACTION_TYPES 5
#define FACTION_HQ_RANGE 8.0    // jarak interaksi markas (duty)
#define FACTION_MAX_RANK 6
#define FACTION_LEAD_RANK 6     // rank Ketua

// Daftar tipe fraksi + warna + skin seragam dinas.
new Faction_TypeName[FACTION_TYPES][24] =
{
    "LSPD (Polisi)",
    "EMS (Medis)",
    "Pemerintah",
    "Montir",
    "News"
};
new Faction_TypeColor[FACTION_TYPES] =
{
    0x2D6CDF, // LSPD biru
    0xE63A3A, // EMS merah
    0x2DBF62, // Pemerintah hijau
    0xF5B301, // Montir kuning
    0xB45FD1  // News ungu
};
new Faction_TypeSkin[FACTION_TYPES] =
{
    280, // LSPD: polisi
    274, // EMS: paramedis
    147, // Pemerintah: jas
    50,  // Montir: montir
    59   // News: reporter
};

// Senjata dinas per tipe fraksi (maks 3, -1 = tidak ada).
new Faction_DutyWeapon[FACTION_TYPES][3] =
{
    {22, 25, 29}, // LSPD: pistol, shotgun, MP5
    {42, -1, -1}, // EMS: alat pemadam
    {-1, -1, -1}, // Pemerintah: tanpa senjata
    {-1, -1, -1}, // Montir: tanpa senjata
    {43, -1, -1}  // News: kamera
};
new Faction_DutyAmmo[FACTION_TYPES][3] =
{
    {100, 60, 150},
    {200, 0, 0},
    {0, 0, 0},
    {0, 0, 0},
    {50, 0, 0}
};

// Nama rank fraksi (rank 1-6).
new Faction_RankName[FACTION_MAX_RANK][16] =
{
    "Rekrut",
    "Anggota",
    "Senior",
    "Perwira",
    "Wakil Ketua",
    "Ketua"
};

//==== DATA FRAKSI ====
new fExists[MAX_FACTION];           // 1 jika slot terisi
new fDBID[MAX_FACTION];            // id baris di tabel factions
new fName[MAX_FACTION][32];        // nama fraksi
new fType[MAX_FACTION];            // indeks tipe fraksi (0-4)
new fColor[MAX_FACTION];           // warna fraksi (0xRRGGBB)
new Float:fSpawnX[MAX_FACTION];    // posisi markas
new Float:fSpawnY[MAX_FACTION];
new Float:fSpawnZ[MAX_FACTION];
new Float:fSpawnA[MAX_FACTION];    // arah hadap markas
new fLeaderCharID[MAX_FACTION];    // id karakter ketua (0 = belum ada)
new fLeaderName[MAX_FACTION][24];  // nama karakter ketua
new fCash[MAX_FACTION];            // kas fraksi
new fPickup[MAX_FACTION];          // id pickup markas
new Text3D:fLabel[MAX_FACTION];    // label 3D markas
new bool:fLabelOn[MAX_FACTION];    // true jika label sedang tampil

// Data sementara: pembuatan fraksi oleh admin (posisi & nama dicatat
// saat perintah diketik, dipakai di callback OnFactionCreated).
new pFactionMakeName[32];
new pFactionMakeType;
new Float:pFactionMakeX;
new Float:pFactionMakeY;
new Float:pFactionMakeZ;
new Float:pFactionMakeA;

// Data sementara per pemain.
new pFactionInvite[MAX_PLAYERS];    // slot fraksi yang mengundang (-1 = tidak ada)
new pFactionInviter[MAX_PLAYERS];  // id pemain yang mengundang
new pFactionInfoSlot[MAX_PLAYERS]; // slot fraksi untuk dialog info
new bool:pDutyOn[MAX_PLAYERS];     // true jika sedang duty fraksi
new pDutyOldSkin[MAX_PLAYERS];     // skin sebelum duty (dikembalikan saat off duty)

//==== FORWARD ====
forward OnFactionLoaded();
forward OnFactionCreated(playerid, slot);
forward OnFactionMembersLoaded(playerid);
forward OnFactionDetailLoaded(playerid);

//================================================================
// UTIL FRAKSI
//================================================================

// Faction_FreeSlot: mencari slot fraksi kosong, -1 jika penuh.
stock Faction_FreeSlot()
{
    for (new i = 0; i < MAX_FACTION; i++)
    {
        if (!fExists[i]) return i;
    }
    return -1;
}

// Faction_Embed: mengubah warna 0xRRGGBB menjadi "{RRGGBB}" untuk label.
stock Faction_Embed(color, dest[], len)
{
    format(dest, len, "{%06x}", color & 0xFFFFFF);
    return 1;
}

// Faction_ChatColor: warna 0xRRGGBB -> format 32-bit SA-MP (alpha terakhir).
stock Faction_ChatColor(slot)
{
    return ((fColor[slot] & 0xFFFFFF) << 8) | 0xFF;
}

// Faction_SlotOf: slot fraksi milik karakter pemain, -1 jika belum punya.
stock Faction_SlotOf(playerid)
{
    new fid = Society_PlayerData[playerid][sPFactionID];
    if (fid <= 0) return -1;
    for (new i = 0; i < MAX_FACTION; i++)
    {
        if (fExists[i] && fDBID[i] == fid) return i;
    }
    return -1;
}

// Faction_RefreshLabel: menggambar ulang label 3D markas fraksi.
stock Faction_RefreshLabel(slot)
{
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 0;
    if (fLabelOn[slot])
    {
        Delete3DTextLabel(fLabel[slot]);
        fLabelOn[slot] = false;
    }
    new text[256], embed[10], ketua[48];
    Faction_Embed(fColor[slot], embed, sizeof(embed));
    if (fLeaderCharID[slot] <= 0)
    {
        format(ketua, sizeof(ketua), "Ketua: {999999}-\n");
    }
    else
    {
        format(ketua, sizeof(ketua), "Ketua: {FFFFFF}%s\n", fLeaderName[slot]);
    }
    format(text, sizeof(text), "%s[FRAKSI]%s\n%s{FFFFFF}\n%s\n%sKetik /duty di sini{FFFFFF}",
        embed, "{FFFFFF}", fName[slot], Faction_TypeName[fType[slot]], ketua, embed);
    fLabel[slot] = Create3DTextLabel(text, 0xFFFFFFFF,
        fSpawnX[slot], fSpawnY[slot], fSpawnZ[slot] + 1.5, 20.0, 0, 1);
    fLabelOn[slot] = true;
    return 1;
}

// Faction_Spawn: membuat pickup markas + label 3D untuk satu fraksi.
stock Faction_Spawn(slot)
{
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 0;
    fPickup[slot] = CreatePickup(1247, 23, fSpawnX[slot], fSpawnY[slot], fSpawnZ[slot], 0);
    Faction_RefreshLabel(slot);
    return 1;
}

// Faction_NearHQ: true jika pemain dekat markas fraksinya sendiri.
stock Faction_NearHQ(playerid, slot)
{
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 0;
    if (GetPlayerInterior(playerid) != 0 || GetPlayerVirtualWorld(playerid) != 0) return 0;
    new Float:d = GetPlayerDistanceFromPoint(playerid, fSpawnX[slot], fSpawnY[slot], fSpawnZ[slot]);
    return (d <= FACTION_HQ_RANGE);
}

// Faction_SaveMember: menyimpan faction_id & faction_rank karakter ke DB.
stock Faction_SaveMember(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE characters SET faction_id = %d, faction_rank = %d WHERE id = %d",
        Society_PlayerData[playerid][sPFactionID], Society_PlayerData[playerid][sPFactionRank],
        Society_PlayerData[playerid][sPCharID]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Faction_RankName_Get: nama rank berdasarkan angka rank (1-6).
stock Faction_RankName_Get(rank, dest[], len)
{
    if (rank >= 1 && rank <= FACTION_MAX_RANK)
    {
        format(dest, len, "%s", Faction_RankName[rank - 1]);
    }
    else
    {
        format(dest, len, "-");
    }
    return 1;
}

// Faction_Broadcast: kirim pesan ke semua anggota fraksi yang sedang online.
stock Faction_Broadcast(slot, const text[], color)
{
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 0;
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
            && Society_PlayerData[p][sPCharID] > 0
            && Society_PlayerData[p][sPFactionID] == fDBID[slot])
        {
            SendClientMessage(p, color, text);
        }
    }
    return 1;
}

// Faction_SetDuty: menyalakan/mematikan mode duty fraksi.
// Saat duty: seragam + senjata dinas sesuai tipe fraksi, senjata lama dibersihkan.
stock Faction_SetDuty(playerid, on)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1) return 0;
    if (on)
    {
        if (pDutyOn[playerid]) return 0;
        pDutyOn[playerid] = true;
        pDutyOldSkin[playerid] = GetPlayerSkin(playerid);
        SetPlayerSkin(playerid, Faction_TypeSkin[fType[slot]]);
        ResetPlayerWeapons(playerid);
        for (new w = 0; w < 3; w++)
        {
            new weapon = Faction_DutyWeapon[fType[slot]][w];
            if (weapon > 0)
            {
                GivePlayerWeapon(playerid, weapon, Faction_DutyAmmo[fType[slot]][w]);
            }
        }
        new msg[192];
        format(msg, sizeof(msg), "Anda mulai duty sebagai %s. Seragam & senjata dinas diberikan.",
            Faction_TypeName[fType[slot]]);
        SendClientMessage(playerid, COLOR_GREEN, msg);
    }
    else
    {
        if (!pDutyOn[playerid]) return 0;
        pDutyOn[playerid] = false;
        SetPlayerSkin(playerid, pDutyOldSkin[playerid]);
        ResetPlayerWeapons(playerid);
        SendClientMessage(playerid, COLOR_GREY, "Duty selesai. Seragam & senjata dinas dikembalikan.");
    }
    return 1;
}

// Faction_SetMember: mengatur keanggotaan karakter di memori + DB.
// (rank 0 = keluar dari fraksi)
stock Faction_SetMember(playerid, dbid, rank)
{
    Society_PlayerData[playerid][sPFactionID] = dbid;
    Society_PlayerData[playerid][sPFactionRank] = rank;
    Faction_SaveMember(playerid);
    return 1;
}

//================================================================
// AKSI FRAKSI
//================================================================

// Faction_Create: admin 3+ membuat fraksi baru di posisinya.
// Pembuat otomatis menjadi ketua (rank 6) bila sedang memakai karakter.
stock Faction_Create(playerid, type, const name[])
{
    if (type < 0 || type >= FACTION_TYPES) return 0;
    new slot = Faction_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot fraksi penuh (maksimal 20).");
        return 0;
    }
    new leaderid = Society_PlayerData[playerid][sPCharID];
    format(pFactionMakeName, sizeof(pFactionMakeName), "%s", name);
    pFactionMakeType = type;
    GetPlayerPos(playerid, pFactionMakeX, pFactionMakeY, pFactionMakeZ);
    GetPlayerFacingAngle(playerid, pFactionMakeA);
    new query[320];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO factions (name, type, color, spawn_x, spawn_y, spawn_z, spawn_angle, leader_char_id, cash) VALUES ('%e', %d, %d, %f, %f, %f, %f, %d, 0)",
        name, type, Faction_TypeColor[type],
        pFactionMakeX, pFactionMakeY, pFactionMakeZ, pFactionMakeA, leaderid);
    mysql_tquery(g_SQL, query, "OnFactionCreated", "dd", playerid, slot);
    return 1;
}

// Faction_Invite: pimpinan (rank 5+) mengundang pemain menjadi anggota.
stock Faction_Invite(playerid, target)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFactionRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Wakil Ketua ke atas yang bisa mengundang.");
        return 0;
    }
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    if (target == playerid)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak bisa mengundang diri sendiri.");
        return 0;
    }
    if (Society_PlayerData[target][sPFactionID] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu sudah tergabung dalam sebuah fraksi.");
        return 0;
    }
    pFactionInvite[target] = slot;
    pFactionInviter[target] = playerid;
    new rankname[16], msg[256], tname[MAX_PLAYER_NAME], iname[MAX_PLAYER_NAME];
    Faction_RankName_Get(Society_PlayerData[playerid][sPFactionRank], rankname, sizeof(rankname));
    GetPlayerName(target, tname, sizeof(tname));
    GetPlayerName(playerid, iname, sizeof(iname));
    format(msg, sizeof(msg),
        "%s (%s fraksi %s) mengundang anda bergabung.\n\nTerima undangan ini?",
        iname, rankname, fName[slot]);
    Dialog_Show(target, FactionInvite, DIALOG_STYLE_MSGBOX,
        "Undangan Fraksi", msg, "Terima", "Tolak");
    format(msg, sizeof(msg), "Undangan fraksi dikirim ke %s.", tname);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Faction_Kick: pimpinan (rank 5+) mengeluarkan anggota (rank lebih rendah).
stock Faction_Kick(playerid, target)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFactionRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Wakil Ketua ke atas yang bisa mengeluarkan anggota.");
        return 0;
    }
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    if (Society_PlayerData[target][sPFactionID] != fDBID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu bukan anggota fraksimu.");
        return 0;
    }
    new trank = Society_PlayerData[target][sPFactionRank];
    new myrank = Society_PlayerData[playerid][sPFactionRank];
    if (trank >= myrank)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak bisa mengeluarkan anggota dengan rank setara/lebih tinggi.");
        return 0;
    }
    new wasleader = (trank == FACTION_LEAD_RANK);
    new tname[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(target, tname, sizeof(tname));
    Faction_SetMember(target, 0, 0);
    if (pDutyOn[target])
    {
        Faction_SetDuty(target, 0);
    }
    if (wasleader)
    {
        fLeaderCharID[slot] = 0;
        fLeaderName[slot][0] = EOS;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE factions SET leader_char_id = 0 WHERE id = %d", fDBID[slot]);
        mysql_tquery(g_SQL, query);
        Faction_RefreshLabel(slot);
    }
    format(msg, sizeof(msg), "%s telah dikeluarkan dari fraksi %s.", tname, fName[slot]);
    SendClientMessage(playerid, COLOR_YELLOW, msg);
    format(msg, sizeof(msg), "Anda dikeluarkan dari fraksi %s.", fName[slot]);
    SendClientMessage(target, COLOR_RED, msg);
    Faction_Broadcast(slot, msg, 0xFF4444FF);
    return 1;
}

// Faction_Quit: pemain keluar dari fraksinya sendiri.
stock Faction_Quit(playerid)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    new rank = Society_PlayerData[playerid][sPFactionRank];
    new name[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(playerid, name, sizeof(name));
    if (pDutyOn[playerid])
    {
        Faction_SetDuty(playerid, 0);
    }
    Faction_SetMember(playerid, 0, 0);
    if (rank == FACTION_LEAD_RANK)
    {
        fLeaderCharID[slot] = 0;
        fLeaderName[slot][0] = EOS;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE factions SET leader_char_id = 0 WHERE id = %d", fDBID[slot]);
        mysql_tquery(g_SQL, query);
        Faction_RefreshLabel(slot);
        format(msg, sizeof(msg), "Ketua %s keluar. Fraksi %s kini tanpa ketua.", name, fName[slot]);
    }
    else
    {
        format(msg, sizeof(msg), "%s keluar dari fraksi %s.", name, fName[slot]);
    }
    SendClientMessage(playerid, COLOR_YELLOW, "Anda keluar dari fraksi.");
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Faction_SetRank: ketua (rank 6) mengatur rank anggota (1-5).
stock Faction_SetRank(playerid, target, rank)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFactionRank] != FACTION_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengatur rank.");
        return 0;
    }
    if (rank < 1 || rank >= FACTION_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Rank harus antara 1-5. Rank 6 (Ketua) diatur via /fsetleader.");
        return 0;
    }
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    if (Society_PlayerData[target][sPFactionID] != fDBID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu bukan anggota fraksimu.");
        return 0;
    }
    Faction_SetMember(target, fDBID[slot], rank);
    new rankname[16], tname[MAX_PLAYER_NAME], msg[192];
    Faction_RankName_Get(rank, rankname, sizeof(rankname));
    GetPlayerName(target, tname, sizeof(tname));
    format(msg, sizeof(msg), "Rank %s kini menjadi %s (%d).", tname, rankname, rank);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "Rank anda di fraksi %s diubah menjadi %s.", fName[slot], rankname);
    SendClientMessage(target, COLOR_YELLOW, msg);
    return 1;
}

// Faction_SetLeader: admin 4+ menunjuk ketua fraksi baru (harus sudah anggota).
stock Faction_SetLeader(playerid, target)
{
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    new slot = Faction_SlotOf(target);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu belum tergabung dalam fraksi mana pun. Undang dulu dengan /finvite.");
        return 0;
    }
    new tchar = Society_PlayerData[target][sPCharID];
    if (tchar == fLeaderCharID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu sudah menjadi ketua fraksi tersebut.");
        return 0;
    }
    // Ketua lama (jika online) diturunkan ke Wakil Ketua.
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
            && Society_PlayerData[p][sPCharID] == fLeaderCharID[slot])
        {
            Faction_SetMember(p, fDBID[slot], 5);
            new msg[128];
            format(msg, sizeof(msg), "Anda diturunkan menjadi Wakil Ketua fraksi %s.", fName[slot]);
            SendClientMessage(p, COLOR_YELLOW, msg);
        }
    }
    fLeaderCharID[slot] = tchar;
    format(fLeaderName[slot], sizeof(fLeaderName[]), "%s", pCharName[target]);
    Faction_SetMember(target, fDBID[slot], FACTION_LEAD_RANK);
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE factions SET leader_char_id = %d WHERE id = %d", tchar, fDBID[slot]);
    mysql_tquery(g_SQL, query);
    Faction_RefreshLabel(slot);
    new tname[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(target, tname, sizeof(tname));
    format(msg, sizeof(msg), "[ADMIN] %s ditunjuk menjadi Ketua fraksi %s.", tname, fName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "%s kini menjadi Ketua fraksi %s.", pCharName[target], fName[slot]);
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Faction_Chat: /f - pesan chat hanya untuk sesama anggota fraksi.
stock Faction_Chat(playerid, const text[])
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    new rankname[16], name[MAX_PLAYER_NAME], msg[192];
    Faction_RankName_Get(Society_PlayerData[playerid][sPFactionRank], rankname, sizeof(rankname));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "** [FRAKSI %s] %s (%s): %s", fName[slot], name, rankname, text);
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Faction_ToggleDuty: /duty - hanya bisa di markas fraksi sendiri.
stock Faction_ToggleDuty(playerid)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (!Faction_NearHQ(playerid, slot))
    {
        SendClientMessage(playerid, COLOR_RED, "Anda harus berada di markas fraksi untuk duty.");
        return 0;
    }
    if (pDutyOn[playerid])
    {
        Faction_SetDuty(playerid, 0);
    }
    else
    {
        Faction_SetDuty(playerid, 1);
        new name[MAX_PLAYER_NAME], msg[192];
        GetPlayerName(playerid, name, sizeof(name));
        format(msg, sizeof(msg), "%s mulai duty (%s).", name, Faction_TypeName[fType[slot]]);
        Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    }
    return 1;
}

// Faction_Deposit: anggota menyetor uang tunai ke kas fraksi.
stock Faction_Deposit(playerid, amount)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (amount <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Jumlah harus lebih dari 0.");
        return 0;
    }
    if (GetPlayerMoney(playerid) < amount)
    {
        SendClientMessage(playerid, COLOR_RED, "Uang tunai anda tidak cukup.");
        return 0;
    }
    GivePlayerMoney(playerid, -amount);
    fCash[slot] += amount;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE factions SET cash = %d WHERE id = %d", fCash[slot], fDBID[slot]);
    mysql_tquery(g_SQL, query);
    new rp[32], kas[32], msg[256], name[MAX_PLAYER_NAME];
    FormatRupiah(amount, rp, sizeof(rp));
    FormatRupiah(fCash[slot], kas, sizeof(kas));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Anda menyetor %s ke kas fraksi. Kas kini: %s.", rp, kas);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "%s menyetor %s ke kas fraksi.", name, rp);
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Faction_Withdraw: ketua mengambil uang dari kas fraksi.
stock Faction_Withdraw(playerid, amount)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFactionRank] != FACTION_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengambil kas fraksi.");
        return 0;
    }
    if (amount <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Jumlah harus lebih dari 0.");
        return 0;
    }
    if (amount > fCash[slot])
    {
        new kas[32], msg[128];
        FormatRupiah(fCash[slot], kas, sizeof(kas));
        format(msg, sizeof(msg), "Kas fraksi tidak cukup. Saldo kas: %s.", kas);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, amount);
    fCash[slot] -= amount;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE factions SET cash = %d WHERE id = %d", fCash[slot], fDBID[slot]);
    mysql_tquery(g_SQL, query);
    new rp[32], msg[192], name[MAX_PLAYER_NAME];
    FormatRupiah(amount, rp, sizeof(rp));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Anda mengambil %s dari kas fraksi.", rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "Ketua %s mengambil %s dari kas fraksi.", name, rp);
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Faction_ShowInfo: /finfo - dialog info fraksi sendiri + daftar anggota (dari DB).
stock Faction_ShowInfo(playerid)
{
    new slot = Faction_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam fraksi mana pun.");
        return 0;
    }
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
        return 0;
    }
    pFactionInfoSlot[playerid] = slot;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT name, faction_rank FROM characters WHERE faction_id = %d ORDER BY faction_rank DESC, name ASC",
        fDBID[slot]);
    mysql_tquery(g_SQL, query, "OnFactionMembersLoaded", "d", playerid);
    return 1;
}

// Faction_ShowList: /factions - dialog daftar semua fraksi.
stock Faction_ShowList(playerid)
{
    new list[1024], line[96], embed[10], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_FACTION; i++)
    {
        if (!fExists[i]) continue;
        Faction_Embed(fColor[i], embed, sizeof(embed));
        if (fLeaderCharID[i] <= 0)
        {
            format(line, sizeof(line), "%s%s{FFFFFF} - %s (tanpa ketua)\n", embed, fName[i], Faction_TypeName[fType[i]]);
        }
        else
        {
            format(line, sizeof(line), "%s%s{FFFFFF} - %s (Ketua: %s)\n", embed, fName[i], Faction_TypeName[fType[i]], fLeaderName[i]);
        }
        if ((strlen(list) + strlen(line)) < sizeof(list))
        {
            strcat(list, line);
            count++;
        }
    }
    if (count == 0)
    {
        Dialog_Show(playerid, FactionsList, DIALOG_STYLE_MSGBOX, "Daftar Fraksi",
            "Belum ada fraksi yang dibuat di server ini.", "Tutup", "");
    }
    else
    {
        Dialog_Show(playerid, FactionsList, DIALOG_STYLE_LIST, "Daftar Fraksi", list, "Detail", "Tutup");
    }
    return 1;
}

// Faction_ShowDetail: dialog detail satu fraksi (dipilih dari daftar).
stock Faction_ShowDetail(playerid, slot)
{
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
        return 0;
    }
    pFactionInfoSlot[playerid] = slot;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT COUNT(*) AS cnt FROM characters WHERE faction_id = %d", fDBID[slot]);
    mysql_tquery(g_SQL, query, "OnFactionDetailLoaded", "d", playerid);
    return 1;
}

// Faction_LoadAll: memuat semua fraksi dari database saat gamemode mulai.
stock Faction_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT f.id, f.name, f.type, f.color, f.spawn_x, f.spawn_y, f.spawn_z, f.spawn_angle, f.leader_char_id, IFNULL(c.name, '') AS leader_name, f.cash FROM factions f LEFT JOIN characters c ON c.id = f.leader_char_id",
        "OnFactionLoaded");
    return 1;
}

// Faction_OnDisconnect: mereset status duty & undangan saat pemain keluar.
stock Faction_OnDisconnect(playerid)
{
    pDutyOn[playerid] = false;
    pFactionInvite[playerid] = -1;
    pFactionInviter[playerid] = -1;
    return 1;
}

// Faction_OnConnect: mereset data sementara fraksi saat pemain masuk.
stock Faction_OnConnect(playerid)
{
    pDutyOn[playerid] = false;
    pFactionInvite[playerid] = -1;
    pFactionInviter[playerid] = -1;
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:FactionInvite - target undangan memilih terima/tolak.
Dialog:FactionInvite(playerid, response, listitem, inputtext[])
{
    new slot = pFactionInvite[playerid];
    pFactionInvite[playerid] = -1;
    new inviter = pFactionInviter[playerid];
    pFactionInviter[playerid] = -1;
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot])
    {
        if (response) SendClientMessage(playerid, COLOR_RED, "Fraksi tersebut sudah tidak ada.");
        return 1;
    }
    if (Society_PlayerData[playerid][sPFactionID] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda sudah tergabung dalam sebuah fraksi.");
        return 1;
    }
    if (!response)
    {
        SendClientMessage(playerid, COLOR_GREY, "Anda menolak undangan fraksi.");
        if (IsPlayerConnected(inviter))
        {
            new name[MAX_PLAYER_NAME], msg[128];
            GetPlayerName(playerid, name, sizeof(name));
            format(msg, sizeof(msg), "%s menolak undangan fraksi %s.", name, fName[slot]);
            SendClientMessage(inviter, COLOR_GREY, msg);
        }
        return 1;
    }
    // Cek ulang pengundang masih berhak (rank 5+ & fraksi sama).
    if (!IsPlayerConnected(inviter) || Faction_SlotOf(inviter) != slot
        || Society_PlayerData[inviter][sPFactionRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Undangan sudah tidak berlaku.");
        return 1;
    }
    Faction_SetMember(playerid, fDBID[slot], 1);
    new name[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Selamat datang di fraksi %s! Rank awal: Rekrut.", fName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Gunakan /f untuk chat fraksi dan /duty di markas untuk bertugas.");
    format(msg, sizeof(msg), "%s bergabung ke fraksi %s.", name, fName[slot]);
    Faction_Broadcast(slot, msg, Faction_ChatColor(slot));
    return 1;
}

// Dialog:FactionsList - daftar fraksi; pilih satu untuk melihat detail.
Dialog:FactionsList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    // listitem dipetakan ke slot fraksi ke-n yang ada.
    new n = 0, slot = -1;
    for (new i = 0; i < MAX_FACTION; i++)
    {
        if (!fExists[i]) continue;
        if (n == listitem) { slot = i; break; }
        n++;
    }
    if (slot == -1) return 1;
    Faction_ShowDetail(playerid, slot);
    return 1;
}

// Dialog:FactionDetail & FactionInfoBody - hanya tampilan, tidak ada aksi.
Dialog:FactionDetail(playerid, response, listitem, inputtext[])
{
    return 1;
}

Dialog:FactionInfoBody(playerid, response, listitem, inputtext[])
{
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnFactionLoaded: mengisi slot fraksi dari database lalu spawn markas.
public OnFactionLoaded()
{
    new rows = cache_num_rows(), tmp, Float:ftmp, count = 0;
    for (new i = 0; i < rows && i < MAX_FACTION; i++)
    {
        cache_get_value_name_int(i, "id", tmp);            fDBID[i] = tmp;
        cache_get_value_name(i, "name", fName[i], sizeof(fName[]));
        cache_get_value_name_int(i, "type", tmp);          fType[i] = tmp;
        cache_get_value_name_int(i, "color", tmp);         fColor[i] = tmp;
        cache_get_value_name_float(i, "spawn_x", ftmp);    fSpawnX[i] = ftmp;
        cache_get_value_name_float(i, "spawn_y", ftmp);    fSpawnY[i] = ftmp;
        cache_get_value_name_float(i, "spawn_z", ftmp);    fSpawnZ[i] = ftmp;
        cache_get_value_name_float(i, "spawn_angle", ftmp); fSpawnA[i] = ftmp;
        cache_get_value_name_int(i, "leader_char_id", tmp); fLeaderCharID[i] = tmp;
        cache_get_value_name(i, "leader_name", fLeaderName[i], sizeof(fLeaderName[]));
        cache_get_value_name_int(i, "cash", tmp);          fCash[i] = tmp;
        if (fType[i] < 0 || fType[i] >= FACTION_TYPES) fType[i] = 0;
        fExists[i] = 1;
        fLabelOn[i] = false;
        Faction_Spawn(i);
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d fraksi dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnFactionCreated: setelah INSERT fraksi berhasil, isi slot & spawn markas.
// Pembuat menjadi ketua bila sedang memakai karakter.
public OnFactionCreated(playerid, slot)
{
    if (slot < 0 || slot >= MAX_FACTION) return 1;
    new type = pFactionMakeType;
    if (type < 0 || type >= FACTION_TYPES) type = 0;
    fExists[slot] = 1;
    fDBID[slot] = cache_insert_id();
    format(fName[slot], sizeof(fName[]), "%s", pFactionMakeName);
    fType[slot] = type;
    fColor[slot] = Faction_TypeColor[type];
    fSpawnX[slot] = pFactionMakeX;
    fSpawnY[slot] = pFactionMakeY;
    fSpawnZ[slot] = pFactionMakeZ;
    fSpawnA[slot] = pFactionMakeA;
    fCash[slot] = 0;
    fLeaderCharID[slot] = 0;
    fLeaderName[slot][0] = EOS;
    if (IsPlayerConnected(playerid) && Society_PlayerData[playerid][sPLogged]
        && Society_PlayerData[playerid][sPCharID] > 0
        && Society_PlayerData[playerid][sPFactionID] <= 0)
    {
        fLeaderCharID[slot] = Society_PlayerData[playerid][sPCharID];
        format(fLeaderName[slot], sizeof(fLeaderName[]), "%s", pCharName[playerid]);
        Faction_SetMember(playerid, fDBID[slot], FACTION_LEAD_RANK);
    }
    // Simpan posisi spawn yang benar ke DB (jaga-jaga bila INSERT gagal
    // menulis posisi, lalu pastikan leader_char_id konsisten).
    new uq[256];
    mysql_format(g_SQL, uq, sizeof(uq),
        "UPDATE factions SET spawn_x = %f, spawn_y = %f, spawn_z = %f, spawn_angle = %f, leader_char_id = %d WHERE id = %d",
        fSpawnX[slot], fSpawnY[slot], fSpawnZ[slot], fSpawnA[slot],
        fLeaderCharID[slot], fDBID[slot]);
    mysql_tquery(g_SQL, uq);
    fLabelOn[slot] = false;
    Faction_Spawn(slot);
    new msg[192];
    format(msg, sizeof(msg), "Fraksi \"%s\" (%s) berhasil dibuat di posisimu.",
        fName[slot], Faction_TypeName[fType[slot]]);
    if (IsPlayerConnected(playerid))
    {
        SendClientMessage(playerid, COLOR_GREEN, msg);
        if (fLeaderCharID[slot] > 0)
        {
            SendClientMessage(playerid, COLOR_GREEN, "Anda menjadi ketua fraksi ini (rank Ketua).");
        }
        SendClientMessage(playerid, COLOR_GREY, "Gunakan /finvite [id] untuk mengundang anggota.");
    }
    return 1;
}

// OnFactionMembersLoaded: menampilkan dialog info fraksi + daftar anggota.
public OnFactionMembersLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pFactionInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 1;
    new rows = cache_num_rows();
    new rankname[16], myrank[16], kas[32], list[1536], line[96], title[64], header[256];
    FormatRupiah(fCash[slot], kas, sizeof(kas));
    Faction_RankName_Get(Society_PlayerData[playerid][sPFactionRank], myrank, sizeof(myrank));
    if (fLeaderCharID[slot] <= 0)
        format(header, sizeof(header),
            "Nama: %s\nTipe: %s\nKetua: -\nKas: %s\nRank anda: %s\n\nAnggota (%d):\n",
            fName[slot], Faction_TypeName[fType[slot]], kas, myrank, rows);
    else
        format(header, sizeof(header),
            "Nama: %s\nTipe: %s\nKetua: %s\nKas: %s\nRank anda: %s\n\nAnggota (%d):\n",
            fName[slot], Faction_TypeName[fType[slot]], fLeaderName[slot], kas, myrank, rows);
    list[0] = EOS;
    strcat(list, header);
    new cname[24], trank;
    for (new i = 0; i < rows; i++)
    {
        cache_get_value_name(i, "name", cname, sizeof(cname));
        cache_get_value_name_int(i, "faction_rank", trank);
        Faction_RankName_Get(trank, rankname, sizeof(rankname));
        format(line, sizeof(line), "- %s (%s)\n", cname, rankname);
        if ((strlen(list) + strlen(line)) < sizeof(list)) strcat(list, line);
    }
    format(title, sizeof(title), "Fraksi: %s", fName[slot]);
    Dialog_Show(playerid, FactionInfoBody, DIALOG_STYLE_MSGBOX, title, list, "Tutup", "");
    return 1;
}

// OnFactionDetailLoaded: menampilkan dialog detail fraksi dari daftar umum.
public OnFactionDetailLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pFactionInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_FACTION || !fExists[slot]) return 1;
    new count = 0;
    cache_get_value_name_int(0, "cnt", count);
    new ketua[32], info[256], title[64];
    if (fLeaderCharID[slot] <= 0) format(ketua, sizeof(ketua), "-");
    else format(ketua, sizeof(ketua), "%s", fLeaderName[slot]);
    format(info, sizeof(info),
        "Nama: %s\nTipe: %s\nKetua: %s\nJumlah anggota: %d\n\nMarkas ditandai dengan ikon bintang.\nKetik /duty di markas bila anda anggotanya.",
        fName[slot], Faction_TypeName[fType[slot]], ketua, count);
    format(title, sizeof(title), "Fraksi: %s", fName[slot]);
    Dialog_Show(playerid, FactionDetail, DIALOG_STYLE_MSGBOX, title, info, "Tutup", "");
    return 1;
}
