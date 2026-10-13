//================================================================
// Society Roleplay - Family_System
// Keluarga/gangster dinamis: didirikan pemain dengan biaya,
// keanggotaan tersimpan di kolom characters (family_id, family_rank).
// Fitur: /createfamily (bayar), /faminvite & /famkick (pimpinan),
// /setfamrank, /fam chat keluarga, /faminfo, /families, /famquit,
// kas keluarga (/famdeposit & /famwithdraw), /famcolor (ketua pilih
// warna: diterapkan ke nama anggota & warna kendaraan anggota),
// /famsetleader (admin). Basis badside untuk turf/gang war nanti.
// Di-include dari gamemodes/Society_Main.pwn (setelah Garage).
//================================================================

#if defined _family_system_included
    #endinput
#endif
#define _family_system_included

//==== KONSTANTA ====
#define MAX_FAMILY 20
#define FAMILY_MAX_RANK 6
#define FAMILY_LEAD_RANK 6     // rank Ketua
#define FAMILY_CREATE_COST 50000000 // Rp50 juta biaya pendirian keluarga
#define FAMILY_COLORS 8

// Pilihan warna keluarga: nama, RGB (chat/label/nama), indeks warna
// mobil SA-MP (0-126) untuk tint kendaraan anggota.
new Family_ColorName[FAMILY_COLORS][16] =
{
    "Merah",
    "Biru",
    "Hijau",
    "Kuning",
    "Ungu",
    "Oranye",
    "Putih",
    "Hitam"
};
new Family_ColorRGB[FAMILY_COLORS] =
{
    0xE63A3A, // Merah
    0x2D6CDF, // Biru
    0x2DBF62, // Hijau
    0xF5B301, // Kuning
    0xB45FD1, // Ungu
    0xFF9900, // Oranye
    0xF0F0F0, // Putih
    0x1A1A1A  // Hitam
};
new Family_ColorCar[FAMILY_COLORS] =
{
    3,  // Merah
    79, // Biru
    16, // Hijau
    6,  // Kuning
    44, // Ungu
    51, // Oranye
    1,  // Putih
    0   // Hitam
};

// Nama rank keluarga (rank 1-6), gaya badside.
new Family_RankName[FAMILY_MAX_RANK][16] =
{
    "Preman",
    "Anak Buah",
    "Penegak",
    "Kapten",
    "Tangan Kanan",
    "Ketua"
};

//==== DATA KELUARGA ====
new famExists[MAX_FAMILY];          // 1 jika slot terisi
new famDBID[MAX_FAMILY];           // id baris di tabel families
new famName[MAX_FAMILY][32];       // nama keluarga
new famColor[MAX_FAMILY];          // warna keluarga (0xRRGGBB)
new famColorCar[MAX_FAMILY];       // indeks warna mobil SA-MP (0-126)
new famLeaderCharID[MAX_FAMILY];   // id karakter ketua (0 = belum ada)
new famLeaderName[MAX_FAMILY][24]; // nama karakter ketua
new famCash[MAX_FAMILY];           // kas keluarga

// Data sementara: pendirian keluarga (nama dicatat saat perintah
// diketik, dipakai di callback OnFamilyCreated).
new pFamMakeName[MAX_PLAYERS][32];

// Data sementara per pemain.
new pFamInvite[MAX_PLAYERS];       // slot keluarga yang mengundang (-1 = tidak ada)
new pFamInviter[MAX_PLAYERS];      // id pemain yang mengundang
new pFamInfoSlot[MAX_PLAYERS];     // slot keluarga untuk dialog info
new pFamColorFor[MAX_PLAYERS];     // slot keluarga yang warnanya sedang dipilih (-1 = tidak ada)

//==== FORWARD ====
forward OnFamilyLoaded();
forward OnFamilyCreated(playerid, slot);
forward OnFamilyMembersLoaded(playerid);
forward OnFamilyDetailLoaded(playerid);

//================================================================
// UTIL KELUARGA
//================================================================

// Family_FreeSlot: mencari slot keluarga kosong, -1 jika penuh.
stock Family_FreeSlot()
{
    for (new i = 0; i < MAX_FAMILY; i++)
    {
        if (!famExists[i]) return i;
    }
    return -1;
}

// Family_Embed: mengubah warna 0xRRGGBB menjadi "{RRGGBB}" untuk label/dialog.
stock Family_Embed(color, dest[], len)
{
    format(dest, len, "{%06x}", color & 0xFFFFFF);
    return 1;
}

// Family_ChatColor: warna 0xRRGGBB -> format 32-bit SA-MP (alpha terakhir).
stock Family_ChatColor(slot)
{
    return ((famColor[slot] & 0xFFFFFF) << 8) | 0xFF;
}

// Family_SlotOf: slot keluarga milik karakter pemain, -1 jika belum punya.
stock Family_SlotOf(playerid)
{
    new fid = Society_PlayerData[playerid][sPFamilyID];
    if (fid <= 0) return -1;
    for (new i = 0; i < MAX_FAMILY; i++)
    {
        if (famExists[i] && famDBID[i] == fid) return i;
    }
    return -1;
}

// Family_RankName_Get: nama rank berdasarkan angka rank (1-6).
stock Family_RankName_Get(rank, dest[], len)
{
    if (rank >= 1 && rank <= FAMILY_MAX_RANK)
    {
        format(dest, len, "%s", Family_RankName[rank - 1]);
    }
    else
    {
        format(dest, len, "-");
    }
    return 1;
}

// Family_SaveMember: menyimpan family_id & family_rank karakter ke DB.
stock Family_SaveMember(playerid)
{
    if (!Society_PlayerData[playerid][sPLogged] || Society_PlayerData[playerid][sPCharID] <= 0) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE characters SET family_id = %d, family_rank = %d WHERE id = %d",
        Society_PlayerData[playerid][sPFamilyID], Society_PlayerData[playerid][sPFamilyRank],
        Society_PlayerData[playerid][sPCharID]);
    mysql_tquery(g_SQL, query);
    return 1;
}

// Family_SetMember: mengatur keanggotaan karakter di memori + DB.
// (rank 0 = keluar dari keluarga)
stock Family_SetMember(playerid, dbid, rank)
{
    Society_PlayerData[playerid][sPFamilyID] = dbid;
    Society_PlayerData[playerid][sPFamilyRank] = rank;
    Family_SaveMember(playerid);
    Family_ApplyColor(playerid);
    return 1;
}

// Family_ApplyColor: menerapkan warna nama pemain sesuai keluarganya.
// Admin yang sedang on-duty tetap oranye (prioritas duty).
stock Family_ApplyColor(playerid)
{
    if (!IsPlayerConnected(playerid)) return 0;
    if (pAdminDuty[playerid])
    {
        SetPlayerColor(playerid, ADMIN_DUTY_COLOR);
        return 1;
    }
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SetPlayerColor(playerid, 0xFFFFFFFF);
        return 1;
    }
    SetPlayerColor(playerid, Family_ChatColor(slot));
    return 1;
}

// Family_Broadcast: kirim pesan ke semua anggota keluarga yang sedang online.
stock Family_Broadcast(slot, const text[], color)
{
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 0;
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
            && Society_PlayerData[p][sPCharID] > 0
            && Society_PlayerData[p][sPFamilyID] == famDBID[slot])
        {
            SendClientMessage(p, color, text);
        }
    }
    return 1;
}

// Family_TintVehicle: menerapkan warna keluarga ke satu slot kendaraan
// (warna utama diganti, warna kedua tetap) lalu disimpan ke DB.
stock Family_TintVehicle(slot, vslot)
{
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 0;
    if (vslot < 0 || vslot >= MAX_PVEH || !vExists[vslot] || !vSpawned[vslot]) return 0;
    ChangeVehicleColor(vVehID[vslot], famColorCar[slot], vColor2[vslot]);
    vColor1[vslot] = famColorCar[slot];
    if (g_SQL != MYSQL_INVALID_HANDLE)
    {
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE player_vehicles SET color1 = %d WHERE id = %d",
            vColor1[vslot], vDBID[vslot]);
        mysql_tquery(g_SQL, query);
    }
    return 1;
}

// Family_TintAllVehicles: menerapkan warna keluarga ke semua kendaraan
// pribadi milik anggota yang sedang online & kendaraannya ter-spawn.
stock Family_TintAllVehicles(slot)
{
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 0;
    new count = 0;
    for (new v = 0; v < MAX_PVEH; v++)
    {
        if (!vExists[v] || !vSpawned[v]) continue;
        for (new p = 0; p < MAX_PLAYERS; p++)
        {
            if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
                && Society_PlayerData[p][sPCharID] > 0
                && Society_PlayerData[p][sPCharID] == vOwnerCharID[v]
                && Society_PlayerData[p][sPFamilyID] == famDBID[slot])
            {
                Family_TintVehicle(slot, v);
                count++;
                break;
            }
        }
    }
    return count;
}

//================================================================
// AKSI KELUARGA
//================================================================

// Family_Create: pemain mendirikan keluarga baru dengan biaya.
// Pendiri otomatis menjadi Ketua (rank 6), lalu memilih warna keluarga.
stock Family_Create(playerid, const name[])
{
    if (Society_PlayerData[playerid][sPFamilyID] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Karaktermu sudah tergabung dalam sebuah keluarga.");
        return 0;
    }
    new slot = Family_FreeSlot();
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Slot keluarga penuh (maksimal 20).");
        return 0;
    }
    if (GetPlayerMoney(playerid) < FAMILY_CREATE_COST)
    {
        new rp[32], msg[160];
        FormatRupiah(FAMILY_CREATE_COST, rp, sizeof(rp));
        format(msg, sizeof(msg), "Biaya pendirian keluarga: %s tunai. Uangmu tidak cukup.", rp);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    format(pFamMakeName[playerid], sizeof(pFamMakeName[]), "%s", name);
    new query[256];
    mysql_format(g_SQL, query, sizeof(query),
        "INSERT INTO families (name, color, leader_char_id, cash) VALUES ('%e', %d, %d, 0)",
        name, Family_ColorRGB[0],
        Society_PlayerData[playerid][sPCharID]);
    mysql_tquery(g_SQL, query, "OnFamilyCreated", "dd", playerid, slot);
    return 1;
}

// Family_Invite: pimpinan (Tangan Kanan+) mengundang pemain menjadi anggota.
stock Family_Invite(playerid, target)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFamilyRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Tangan Kanan ke atas yang bisa mengundang.");
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
    if (Society_PlayerData[target][sPFamilyID] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu sudah tergabung dalam sebuah keluarga.");
        return 0;
    }
    pFamInvite[target] = slot;
    pFamInviter[target] = playerid;
    new rankname[16], msg[256], tname[MAX_PLAYER_NAME], iname[MAX_PLAYER_NAME];
    Family_RankName_Get(Society_PlayerData[playerid][sPFamilyRank], rankname, sizeof(rankname));
    GetPlayerName(target, tname, sizeof(tname));
    GetPlayerName(playerid, iname, sizeof(iname));
    format(msg, sizeof(msg),
        "%s (%s keluarga %s) mengundang anda bergabung.\n\nTerima undangan ini?",
        iname, rankname, famName[slot]);
    Dialog_Show(target, FamilyInvite, DIALOG_STYLE_MSGBOX,
        "Undangan Keluarga", msg, "Terima", "Tolak");
    format(msg, sizeof(msg), "Undangan keluarga dikirim ke %s.", tname);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    return 1;
}

// Family_Kick: pimpinan (Tangan Kanan+) mengeluarkan anggota (rank lebih rendah).
stock Family_Kick(playerid, target)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFamilyRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Tangan Kanan ke atas yang bisa mengeluarkan anggota.");
        return 0;
    }
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    if (Society_PlayerData[target][sPFamilyID] != famDBID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu bukan anggota keluargamu.");
        return 0;
    }
    new trank = Society_PlayerData[target][sPFamilyRank];
    new myrank = Society_PlayerData[playerid][sPFamilyRank];
    if (trank >= myrank)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak bisa mengeluarkan anggota dengan rank setara/lebih tinggi.");
        return 0;
    }
    new wasleader = (trank == FAMILY_LEAD_RANK);
    new tname[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(target, tname, sizeof(tname));
    Family_SetMember(target, 0, 0);
    if (wasleader)
    {
        famLeaderCharID[slot] = 0;
        famLeaderName[slot][0] = EOS;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE families SET leader_char_id = 0 WHERE id = %d", famDBID[slot]);
        mysql_tquery(g_SQL, query);
    }
    format(msg, sizeof(msg), "%s telah dikeluarkan dari keluarga %s.", tname, famName[slot]);
    SendClientMessage(playerid, COLOR_YELLOW, msg);
    format(msg, sizeof(msg), "Anda dikeluarkan dari keluarga %s.", famName[slot]);
    SendClientMessage(target, COLOR_RED, msg);
    format(msg, sizeof(msg), "%s dikeluarkan dari keluarga.", tname);
    Family_Broadcast(slot, msg, 0xFF4444FF);
    return 1;
}

// Family_Quit: pemain keluar dari keluarganya sendiri.
stock Family_Quit(playerid)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    new rank = Society_PlayerData[playerid][sPFamilyRank];
    new name[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(playerid, name, sizeof(name));
    Family_SetMember(playerid, 0, 0);
    if (rank == FAMILY_LEAD_RANK)
    {
        famLeaderCharID[slot] = 0;
        famLeaderName[slot][0] = EOS;
        new query[128];
        mysql_format(g_SQL, query, sizeof(query),
            "UPDATE families SET leader_char_id = 0 WHERE id = %d", famDBID[slot]);
        mysql_tquery(g_SQL, query);
        format(msg, sizeof(msg), "Ketua %s keluar. Keluarga %s kini tanpa ketua.", name, famName[slot]);
    }
    else
    {
        format(msg, sizeof(msg), "%s keluar dari keluarga %s.", name, famName[slot]);
    }
    SendClientMessage(playerid, COLOR_YELLOW, "Anda keluar dari keluarga.");
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_SetRank: ketua (rank 6) mengatur rank anggota (1-5).
stock Family_SetRank(playerid, target, rank)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFamilyRank] != FAMILY_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengatur rank.");
        return 0;
    }
    if (rank < 1 || rank >= FAMILY_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Rank harus antara 1-5. Rank 6 (Ketua) diatur via /famsetleader.");
        return 0;
    }
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    if (Society_PlayerData[target][sPFamilyID] != famDBID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu bukan anggota keluargamu.");
        return 0;
    }
    Family_SetMember(target, famDBID[slot], rank);
    new rankname[16], tname[MAX_PLAYER_NAME], msg[192];
    Family_RankName_Get(rank, rankname, sizeof(rankname));
    GetPlayerName(target, tname, sizeof(tname));
    format(msg, sizeof(msg), "Rank %s kini menjadi %s (%d).", tname, rankname, rank);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "Rank anda di keluarga %s diubah menjadi %s.", famName[slot], rankname);
    SendClientMessage(target, COLOR_YELLOW, msg);
    return 1;
}

// Family_SetLeader: admin 4+ menunjuk ketua keluarga baru (harus sudah anggota).
stock Family_SetLeader(playerid, target)
{
    if (!IsPlayerConnected(target) || !Society_PlayerData[target][sPLogged]
        || Society_PlayerData[target][sPCharID] <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "ID pemain tidak valid atau belum memakai karakter.");
        return 0;
    }
    new slot = Family_SlotOf(target);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu belum tergabung dalam keluarga mana pun. Undang dulu dengan /faminvite.");
        return 0;
    }
    new tchar = Society_PlayerData[target][sPCharID];
    if (tchar == famLeaderCharID[slot])
    {
        SendClientMessage(playerid, COLOR_RED, "Pemain itu sudah menjadi ketua keluarga tersebut.");
        return 0;
    }
    // Ketua lama (jika online) diturunkan menjadi Tangan Kanan.
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
            && Society_PlayerData[p][sPCharID] == famLeaderCharID[slot])
        {
            Family_SetMember(p, famDBID[slot], 5);
            new msg[128];
            format(msg, sizeof(msg), "Anda diturunkan menjadi Tangan Kanan keluarga %s.", famName[slot]);
            SendClientMessage(p, COLOR_YELLOW, msg);
        }
    }
    famLeaderCharID[slot] = tchar;
    format(famLeaderName[slot], sizeof(famLeaderName[]), "%s", pCharName[target]);
    Family_SetMember(target, famDBID[slot], FAMILY_LEAD_RANK);
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE families SET leader_char_id = %d WHERE id = %d", tchar, famDBID[slot]);
    mysql_tquery(g_SQL, query);
    new tname[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(target, tname, sizeof(tname));
    format(msg, sizeof(msg), "[ADMIN] %s ditunjuk menjadi Ketua keluarga %s.", tname, famName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "%s kini menjadi Ketua keluarga %s.", pCharName[target], famName[slot]);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_Chat: /fam - pesan chat hanya untuk sesama anggota keluarga.
stock Family_Chat(playerid, const text[])
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    new rankname[16], name[MAX_PLAYER_NAME], msg[192];
    Family_RankName_Get(Society_PlayerData[playerid][sPFamilyRank], rankname, sizeof(rankname));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "** [KELUARGA %s] %s (%s): %s", famName[slot], name, rankname, text);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_Deposit: anggota menyetor uang tunai ke kas keluarga.
stock Family_Deposit(playerid, amount)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
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
    famCash[slot] += amount;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE families SET cash = %d WHERE id = %d", famCash[slot], famDBID[slot]);
    mysql_tquery(g_SQL, query);
    new rp[32], kas[32], msg[256], name[MAX_PLAYER_NAME];
    FormatRupiah(amount, rp, sizeof(rp));
    FormatRupiah(famCash[slot], kas, sizeof(kas));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Anda menyetor %s ke kas keluarga. Kas kini: %s.", rp, kas);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "%s menyetor %s ke kas keluarga.", name, rp);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_Withdraw: ketua mengambil uang dari kas keluarga.
stock Family_Withdraw(playerid, amount)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFamilyRank] != FAMILY_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengambil kas keluarga.");
        return 0;
    }
    if (amount <= 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Jumlah harus lebih dari 0.");
        return 0;
    }
    if (amount > famCash[slot])
    {
        new kas[32], msg[128];
        FormatRupiah(famCash[slot], kas, sizeof(kas));
        format(msg, sizeof(msg), "Kas keluarga tidak cukup. Saldo kas: %s.", kas);
        SendClientMessage(playerid, COLOR_RED, msg);
        return 0;
    }
    GivePlayerMoney(playerid, amount);
    famCash[slot] -= amount;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE families SET cash = %d WHERE id = %d", famCash[slot], famDBID[slot]);
    mysql_tquery(g_SQL, query);
    new rp[32], msg[192], name[MAX_PLAYER_NAME];
    FormatRupiah(amount, rp, sizeof(rp));
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Anda mengambil %s dari kas keluarga.", rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "Ketua %s mengambil %s dari kas keluarga.", name, rp);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_ShowColorPicker: /famcolor - ketua memilih warna keluarga (dialog).
stock Family_ShowColorPicker(playerid)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (Society_PlayerData[playerid][sPFamilyRank] != FAMILY_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengganti warna keluarga.");
        return 0;
    }
    pFamColorFor[playerid] = slot;
    new list[512], line[48], embed[10];
    list[0] = EOS;
    for (new i = 0; i < FAMILY_COLORS; i++)
    {
        Family_Embed(Family_ColorRGB[i], embed, sizeof(embed));
        format(line, sizeof(line), "%s%s{FFFFFF}\n", embed, Family_ColorName[i]);
        if ((strlen(list) + strlen(line)) < sizeof(list)) strcat(list, line);
    }
    Dialog_Show(playerid, FamilyColor, DIALOG_STYLE_LIST,
        "Warna Keluarga", list, "Pilih", "Batal");
    return 1;
}

// Family_SetColor: menerapkan warna baru ke keluarga: nama anggota,
// chat, dan warna utama kendaraan anggota yang sedang online.
stock Family_SetColor(playerid, slot, coloridx)
{
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 0;
    if (coloridx < 0 || coloridx >= FAMILY_COLORS) return 0;
    if (Society_PlayerData[playerid][sPFamilyID] != famDBID[slot]
        || Society_PlayerData[playerid][sPFamilyRank] != FAMILY_LEAD_RANK)
    {
        SendClientMessage(playerid, COLOR_RED, "Hanya Ketua yang bisa mengganti warna keluarga.");
        return 0;
    }
    famColor[slot] = Family_ColorRGB[coloridx];
    famColorCar[slot] = Family_ColorCar[coloridx];
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "UPDATE families SET color = %d WHERE id = %d", famColor[slot], famDBID[slot]);
    mysql_tquery(g_SQL, query);
    // Terapkan warna nama ke semua anggota yang online.
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (IsPlayerConnected(p) && Society_PlayerData[p][sPLogged]
            && Society_PlayerData[p][sPCharID] > 0
            && Society_PlayerData[p][sPFamilyID] == famDBID[slot])
        {
            Family_ApplyColor(p);
        }
    }
    // Samakan warna utama kendaraan anggota yang sedang ter-spawn.
    new tinted = Family_TintAllVehicles(slot);
    new msg[256], embed[10];
    Family_Embed(famColor[slot], embed, sizeof(embed));
    format(msg, sizeof(msg),
        "Warna keluarga %s kini %s%s{FFFFFF}. %d kendaraan anggota disamakan warnanya.",
        famName[slot], embed, Family_ColorName[coloridx], tinted);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    format(msg, sizeof(msg), "Ketua mengganti warna keluarga menjadi %s%s{FFFFFF}.",
        embed, Family_ColorName[coloridx]);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Family_ShowInfo: /faminfo - dialog info keluarga sendiri + daftar anggota (dari DB).
stock Family_ShowInfo(playerid)
{
    new slot = Family_SlotOf(playerid);
    if (slot == -1)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda tidak tergabung dalam keluarga mana pun.");
        return 0;
    }
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
        return 0;
    }
    pFamInfoSlot[playerid] = slot;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT name, family_rank FROM characters WHERE family_id = %d ORDER BY family_rank DESC, name ASC",
        famDBID[slot]);
    mysql_tquery(g_SQL, query, "OnFamilyMembersLoaded", "d", playerid);
    return 1;
}

// Family_ShowList: /families - dialog daftar semua keluarga.
stock Family_ShowList(playerid)
{
    new list[1024], line[96], embed[10], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_FAMILY; i++)
    {
        if (!famExists[i]) continue;
        Family_Embed(famColor[i], embed, sizeof(embed));
        if (famLeaderCharID[i] <= 0)
        {
            format(line, sizeof(line), "%s%s{FFFFFF} (tanpa ketua)\n", embed, famName[i]);
        }
        else
        {
            format(line, sizeof(line), "%s%s{FFFFFF} (Ketua: %s)\n", embed, famName[i], famLeaderName[i]);
        }
        if ((strlen(list) + strlen(line)) < sizeof(list))
        {
            strcat(list, line);
            count++;
        }
    }
    if (count == 0)
    {
        Dialog_Show(playerid, FamiliesList, DIALOG_STYLE_MSGBOX, "Daftar Keluarga",
            "Belum ada keluarga yang didirikan di server ini.\nKetik /createfamily [nama] untuk mendirikan satu.", "Tutup", "");
    }
    else
    {
        Dialog_Show(playerid, FamiliesList, DIALOG_STYLE_LIST, "Daftar Keluarga", list, "Detail", "Tutup");
    }
    return 1;
}

// Family_ShowDetail: dialog detail satu keluarga (dipilih dari daftar).
stock Family_ShowDetail(playerid, slot)
{
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 0;
    if (g_SQL == MYSQL_INVALID_HANDLE)
    {
        SendClientMessage(playerid, COLOR_RED, "Database sedang offline.");
        return 0;
    }
    pFamInfoSlot[playerid] = slot;
    new query[128];
    mysql_format(g_SQL, query, sizeof(query),
        "SELECT COUNT(*) AS cnt FROM characters WHERE family_id = %d", famDBID[slot]);
    mysql_tquery(g_SQL, query, "OnFamilyDetailLoaded", "d", playerid);
    return 1;
}

// Family_LoadAll: memuat semua keluarga dari database saat gamemode mulai.
stock Family_LoadAll()
{
    if (g_SQL == MYSQL_INVALID_HANDLE) return 0;
    mysql_tquery(g_SQL,
        "SELECT f.id, f.name, f.color, f.leader_char_id, IFNULL(c.name, '') AS leader_name, f.cash FROM families f LEFT JOIN characters c ON c.id = f.leader_char_id",
        "OnFamilyLoaded");
    return 1;
}

// Family_OnDisconnect: mereset data sementara keluarga saat pemain keluar.
stock Family_OnDisconnect(playerid)
{
    pFamInvite[playerid] = -1;
    pFamInviter[playerid] = -1;
    pFamColorFor[playerid] = -1;
    return 1;
}

// Family_OnConnect: mereset data sementara keluarga saat pemain masuk.
stock Family_OnConnect(playerid)
{
    pFamInvite[playerid] = -1;
    pFamInviter[playerid] = -1;
    pFamColorFor[playerid] = -1;
    return 1;
}

//================================================================
// DIALOG (easyDialog)
//================================================================

// Dialog:FamilyInvite - target undangan memilih terima/tolak.
Dialog:FamilyInvite(playerid, response, listitem, inputtext[])
{
    new slot = pFamInvite[playerid];
    pFamInvite[playerid] = -1;
    new inviter = pFamInviter[playerid];
    pFamInviter[playerid] = -1;
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot])
    {
        if (response) SendClientMessage(playerid, COLOR_RED, "Keluarga tersebut sudah tidak ada.");
        return 1;
    }
    if (Society_PlayerData[playerid][sPFamilyID] > 0)
    {
        SendClientMessage(playerid, COLOR_RED, "Anda sudah tergabung dalam sebuah keluarga.");
        return 1;
    }
    if (!response)
    {
        SendClientMessage(playerid, COLOR_GREY, "Anda menolak undangan keluarga.");
        if (IsPlayerConnected(inviter))
        {
            new name[MAX_PLAYER_NAME], msg[128];
            GetPlayerName(playerid, name, sizeof(name));
            format(msg, sizeof(msg), "%s menolak undangan keluarga %s.", name, famName[slot]);
            SendClientMessage(inviter, COLOR_GREY, msg);
        }
        return 1;
    }
    // Cek ulang pengundang masih berhak (rank 5+ & keluarga sama).
    if (!IsPlayerConnected(inviter) || Family_SlotOf(inviter) != slot
        || Society_PlayerData[inviter][sPFamilyRank] < 5)
    {
        SendClientMessage(playerid, COLOR_RED, "Undangan sudah tidak berlaku.");
        return 1;
    }
    Family_SetMember(playerid, famDBID[slot], 1);
    new name[MAX_PLAYER_NAME], msg[192];
    GetPlayerName(playerid, name, sizeof(name));
    format(msg, sizeof(msg), "Selamat datang di keluarga %s! Rank awal: Preman.", famName[slot]);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Gunakan /fam untuk chat keluarga. Namamu kini berwarna keluarga.");
    format(msg, sizeof(msg), "%s bergabung ke keluarga %s.", name, famName[slot]);
    Family_Broadcast(slot, msg, Family_ChatColor(slot));
    return 1;
}

// Dialog:FamilyColor - ketua memilih warna keluarga dari daftar.
Dialog:FamilyColor(playerid, response, listitem, inputtext[])
{
    new slot = pFamColorFor[playerid];
    pFamColorFor[playerid] = -1;
    if (!response) return 1;
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 1;
    if (listitem < 0 || listitem >= FAMILY_COLORS) return 1;
    Family_SetColor(playerid, slot, listitem);
    return 1;
}

// Dialog:FamiliesList - daftar keluarga; pilih satu untuk melihat detail.
Dialog:FamiliesList(playerid, response, listitem, inputtext[])
{
    if (!response) return 1;
    // listitem dipetakan ke slot keluarga ke-n yang ada.
    new n = 0, slot = -1;
    for (new i = 0; i < MAX_FAMILY; i++)
    {
        if (!famExists[i]) continue;
        if (n == listitem) { slot = i; break; }
        n++;
    }
    if (slot == -1) return 1;
    Family_ShowDetail(playerid, slot);
    return 1;
}

// Dialog:FamilyDetail & FamilyInfoBody - hanya tampilan, tidak ada aksi.
Dialog:FamilyDetail(playerid, response, listitem, inputtext[])
{
    return 1;
}

Dialog:FamilyInfoBody(playerid, response, listitem, inputtext[])
{
    return 1;
}

//================================================================
// CALLBACK MYSQL
//================================================================

// OnFamilyLoaded: mengisi slot keluarga dari database.
public OnFamilyLoaded()
{
    new rows = cache_num_rows(), tmp, count = 0;
    for (new i = 0; i < rows && i < MAX_FAMILY; i++)
    {
        cache_get_value_name_int(i, "id", tmp);            famDBID[i] = tmp;
        cache_get_value_name(i, "name", famName[i], sizeof(famName[]));
        cache_get_value_name_int(i, "color", tmp);         famColor[i] = tmp;
        cache_get_value_name_int(i, "leader_char_id", tmp); famLeaderCharID[i] = tmp;
        cache_get_value_name(i, "leader_name", famLeaderName[i], sizeof(famLeaderName[]));
        cache_get_value_name_int(i, "cash", tmp);          famCash[i] = tmp;
        // Samakan indeks warna mobil dengan RGB yang tersimpan.
        famColorCar[i] = Family_ColorCar[0];
        for (new c = 0; c < FAMILY_COLORS; c++)
        {
            if (Family_ColorRGB[c] == famColor[i]) { famColorCar[i] = Family_ColorCar[c]; break; }
        }
        famExists[i] = 1;
        count++;
    }
    new msg[96];
    format(msg, sizeof(msg), "[SocietyRP] %d keluarga dimuat dari database.", count);
    print(msg);
    return 1;
}

// OnFamilyCreated: setelah INSERT keluarga berhasil, isi slot & jadikan
// pendiri sebagai Ketua, lalu tampilkan dialog pilih warna keluarga.
public OnFamilyCreated(playerid, slot)
{
    if (slot < 0 || slot >= MAX_FAMILY) return 1;
    if (!famExists[slot])
    {
        famExists[slot] = 1;
        famDBID[slot] = cache_insert_id();
        format(famName[slot], sizeof(famName[]), "%s", pFamMakeName[playerid]);
        famColor[slot] = Family_ColorRGB[0];
        famColorCar[slot] = Family_ColorCar[0];
        famCash[slot] = 0;
        famLeaderCharID[slot] = 0;
        famLeaderName[slot][0] = EOS;
    }
    if (!IsPlayerConnected(playerid))
    {
        // Pemain keburu keluar: kembalikan biaya ke kas keluarga.
        return 1;
    }
    // Potong biaya pendirian dari uang tunai pendiri.
    GivePlayerMoney(playerid, -FAMILY_CREATE_COST);
    if (Society_PlayerData[playerid][sPLogged]
        && Society_PlayerData[playerid][sPCharID] > 0
        && Society_PlayerData[playerid][sPFamilyID] <= 0)
    {
        famLeaderCharID[slot] = Society_PlayerData[playerid][sPCharID];
        format(famLeaderName[slot], sizeof(famLeaderName[]), "%s", pCharName[playerid]);
        new uq[128];
        mysql_format(g_SQL, uq, sizeof(uq),
            "UPDATE families SET leader_char_id = %d WHERE id = %d",
            famLeaderCharID[slot], famDBID[slot]);
        mysql_tquery(g_SQL, uq);
        Family_SetMember(playerid, famDBID[slot], FAMILY_LEAD_RANK);
    }
    new rp[32], msg[256];
    FormatRupiah(FAMILY_CREATE_COST, rp, sizeof(rp));
    format(msg, sizeof(msg), "Keluarga \"%s\" berhasil didirikan! Biaya: %s.", famName[slot], rp);
    SendClientMessage(playerid, COLOR_GREEN, msg);
    SendClientMessage(playerid, COLOR_GREY, "Pilih warna identitas keluargamu di bawah ini.");
    SendClientMessage(playerid, COLOR_GREY, "Gunakan /faminvite [id] untuk mengundang anggota.");
    Family_ShowColorPicker(playerid);
    return 1;
}

// OnFamilyMembersLoaded: menampilkan dialog info keluarga + daftar anggota.
public OnFamilyMembersLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pFamInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 1;
    new rows = cache_num_rows();
    new rankname[16], myrank[16], kas[32], list[1536], line[96], title[64], header[256], warna[16], embed[10];
    FormatRupiah(famCash[slot], kas, sizeof(kas));
    Family_RankName_Get(Society_PlayerData[playerid][sPFamilyRank], myrank, sizeof(myrank));
    Family_Embed(famColor[slot], embed, sizeof(embed));
    format(warna, sizeof(warna), "%sWarna ini%s", embed, "{FFFFFF}");
    new ketua[32];
    if (famLeaderCharID[slot] <= 0) format(ketua, sizeof(ketua), "-");
    else format(ketua, sizeof(ketua), "%s", famLeaderName[slot]);
    format(header, sizeof(header),
        "Nama: %s\nKetua: %s\nWarna: %s\nKas: %s\nRank anda: %s\n\nAnggota (%d):\n",
        famName[slot], ketua, warna, kas, myrank, rows);
    list[0] = EOS;
    strcat(list, header);
    new cname[24], trank;
    for (new i = 0; i < rows; i++)
    {
        cache_get_value_name(i, "name", cname, sizeof(cname));
        cache_get_value_name_int(i, "family_rank", trank);
        Family_RankName_Get(trank, rankname, sizeof(rankname));
        format(line, sizeof(line), "- %s (%s)\n", cname, rankname);
        if ((strlen(list) + strlen(line)) < sizeof(list)) strcat(list, line);
    }
    format(title, sizeof(title), "Keluarga: %s", famName[slot]);
    Dialog_Show(playerid, FamilyInfoBody, DIALOG_STYLE_MSGBOX, title, list, "Tutup", "");
    return 1;
}

// OnFamilyDetailLoaded: menampilkan dialog detail keluarga dari daftar umum.
public OnFamilyDetailLoaded(playerid)
{
    if (!IsPlayerConnected(playerid)) return 1;
    new slot = pFamInfoSlot[playerid];
    if (slot < 0 || slot >= MAX_FAMILY || !famExists[slot]) return 1;
    new count = 0;
    cache_get_value_name_int(0, "cnt", count);
    new ketua[32], info[256], title[64], warna[16], embed[10];
    if (famLeaderCharID[slot] <= 0) format(ketua, sizeof(ketua), "-");
    else format(ketua, sizeof(ketua), "%s", famLeaderName[slot]);
    Family_Embed(famColor[slot], embed, sizeof(embed));
    format(warna, sizeof(warna), "%sWarna ini%s", embed, "{FFFFFF}");
    format(info, sizeof(info),
        "Nama: %s\nKetua: %s\nWarna: %s\nJumlah anggota: %d\n\nKeluarga adalah basis badside: rekrut anggotamu\nlalu kuasai jalanan bersama.",
        famName[slot], ketua, warna, count);
    format(title, sizeof(title), "Keluarga: %s", famName[slot]);
    Dialog_Show(playerid, FamilyDetail, DIALOG_STYLE_MSGBOX, title, info, "Tutup", "");
    return 1;
}
