//================================================================
// Society Roleplay - Admin_System
// Sistem admin: nama jabatan tiap level, mode duty (on-duty) dengan
// nama berwarna, dan daftar admin yang sedang online.
// Level admin tersimpan di kolom accounts.admin (diatur via /setadmin).
// Di-include dari gamemodes/Society_Main.pwn (setelah Utils_Color).
//================================================================

#if defined _admin_system_included
    #endinput
#endif
#define _admin_system_included

// Warna nama saat admin sedang on-duty (oranye oldschool).
#define ADMIN_DUTY_COLOR 0xFF9900FF

// pAdminDuty: true jika admin sedang bertugas (on-duty).
new bool:pAdminDuty[MAX_PLAYERS];

// Admin_Name: nama jabatan tiap level admin.
// 1=Junior, 2=Senior, 3=Head, 4=Manager, 5=Owner.
stock Admin_Name(level, dest[], len)
{
    switch (level)
    {
        case 1: format(dest, len, "Junior");
        case 2: format(dest, len, "Senior");
        case 3: format(dest, len, "Head");
        case 4: format(dest, len, "Manager");
        case 5: format(dest, len, "Owner");
        default: format(dest, len, "Bukan Admin");
    }
    return 1;
}

// Admin_ToggleDuty: menyalakan/mematikan mode duty admin.
// Saat on-duty, nama admin berwarna oranye dan diumumkan ke server.
stock Admin_ToggleDuty(playerid)
{
    new level = Society_PlayerData[playerid][sPAdmin];
    if (level < 1) return 0;
    new name[MAX_PLAYER_NAME], title[16], msg[160];
    GetPlayerName(playerid, name, sizeof(name));
    Admin_Name(level, title, sizeof(title));
    if (pAdminDuty[playerid])
    {
        pAdminDuty[playerid] = false;
        SetPlayerColor(playerid, 0xFFFFFFFF); // kembalikan ke warna normal
        format(msg, sizeof(msg), "[ADMIN] %s (%s) sudah tidak bertugas.", name, title);
        SendClientMessageToAll(COLOR_GREY, msg);
        SendClientMessage(playerid, COLOR_GREY, "Mode duty dimatikan. Warna nama dikembalikan normal.");
    }
    else
    {
        pAdminDuty[playerid] = true;
        SetPlayerColor(playerid, ADMIN_DUTY_COLOR);
        format(msg, sizeof(msg), "[ADMIN] %s (%s) sedang bertugas. Hubungi bila butuh bantuan.", name, title);
        SendClientMessageToAll(COLOR_YELLOW, msg);
        SendClientMessage(playerid, COLOR_YELLOW, "Mode duty dinyalakan. Nama anda sekarang berwarna oranye.");
    }
    return 1;
}

// Admin_OnDisconnect: mereset status duty saat pemain keluar server.
stock Admin_OnDisconnect(playerid)
{
    pAdminDuty[playerid] = false;
    return 1;
}

// Admin_ShowList: dialog daftar admin yang sedang online,
// berisi nama, level jabatan, dan status duty.
stock Admin_ShowList(playerid)
{
    new list[1024], line[96], title[16], name[MAX_PLAYER_NAME], count = 0;
    list[0] = EOS;
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (!IsPlayerConnected(i)) continue;
        if (!Society_PlayerData[i][sPLogged]) continue;
        new level = Society_PlayerData[i][sPAdmin];
        if (level < 1) continue;
        GetPlayerName(i, name, sizeof(name));
        Admin_Name(level, title, sizeof(title));
        if (pAdminDuty[i])
            format(line, sizeof(line), "%s [ID %d] - %s - SEDANG BERTUGAS\n", name, i, title);
        else
            format(line, sizeof(line), "%s [ID %d] - %s\n", name, i, title);
        if ((strlen(list) + strlen(line)) < sizeof(list))
        {
            strcat(list, line);
            count++;
        }
    }
    if (count == 0)
    {
        Dialog_Show(playerid, AdminList, DIALOG_STYLE_MSGBOX, "Daftar Admin",
            "Tidak ada admin yang sedang online.", "Tutup", "");
    }
    else
    {
        Dialog_Show(playerid, AdminList, DIALOG_STYLE_LIST, "Daftar Admin Online", list, "Tutup", "");
    }
    return 1;
}

// Dialog:AdminList - handler dialog daftar admin (hanya informasi).
Dialog:AdminList(playerid, response, listitem, inputtext[])
{
    return 1;
}
