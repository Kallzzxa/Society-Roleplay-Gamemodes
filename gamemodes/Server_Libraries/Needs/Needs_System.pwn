//================================================================
// Society Roleplay - Needs_System
// Sistem kebutuhan pemain: makan, minum, stress.
// Tampil sebagai textdraw gaya oldschool di kanan bawah layar.
// Di-include dari gamemodes/Society_Main.pwn (setelah Utils_Color).
//================================================================

#if defined _needs_system_included
    #endinput
#endif
#define _needs_system_included

// Indeks baris textdraw kebutuhan
#define NEEDS_MAKAN  0
#define NEEDS_MINUM  1
#define NEEDS_STRESS 2

new PlayerText:pNeedsTD[MAX_PLAYERS][3];
new bool:pNeedsTDCreated[MAX_PLAYERS];

// Needs_BuildBar: "Makan ~g~||||||||--~w~" (10 segmen, warna ikut nilai)
stock Needs_BuildBar(const label[], Float:value, bool:invert, dest[], len)
{
    new filled = floatround(value / 10.0, floatround_round);
    if (filled < 0) filled = 0;
    if (filled > 10) filled = 10;
    new color[4];
    if (!invert)
    {
        if (value > 60.0) color = "~g~";
        else if (value >= 30.0) color = "~y~";
        else color = "~r~";
    }
    else
    {
        if (value > 60.0) color = "~r~";
        else if (value >= 30.0) color = "~y~";
        else color = "~g~";
    }
    new bar[12], pos = 0;
    for (new i = 0; i < 10; i++)
    {
        bar[pos++] = (i < filled) ? ('|') : ('-');
    }
    bar[pos] = EOS;
    format(dest, len, "%s %s%s~w~", label, color, bar);
    return 1;
}

// Needs_CreateTextDraws: membuat 3 player-textdraw (makan, minum, stress)
stock Needs_CreateTextDraws(playerid)
{
    if (UI_IsCef(playerid)) return 1; // dirender via WebView (HUD HTML)
    if (pNeedsTDCreated[playerid]) return 1;
    pNeedsTD[playerid][NEEDS_MAKAN] = CreatePlayerTextDraw(playerid, 505.0, 385.0, "Makan");
    pNeedsTD[playerid][NEEDS_MINUM] = CreatePlayerTextDraw(playerid, 505.0, 399.0, "Minum");
    pNeedsTD[playerid][NEEDS_STRESS] = CreatePlayerTextDraw(playerid, 505.0, 413.0, "Stress");
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawFont(playerid, pNeedsTD[playerid][i], 1);
        PlayerTextDrawLetterSize(playerid, pNeedsTD[playerid][i], 0.25, 1.1);
        PlayerTextDrawSetOutline(playerid, pNeedsTD[playerid][i], 1);
        PlayerTextDrawSetProportional(playerid, pNeedsTD[playerid][i], 1);
        PlayerTextDrawColor(playerid, pNeedsTD[playerid][i], COLOR_WHITE);
    }
    pNeedsTDCreated[playerid] = true;
    return 1;
}

stock Needs_DestroyTextDraws(playerid)
{
    if (!pNeedsTDCreated[playerid]) return 1;
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawDestroy(playerid, pNeedsTD[playerid][i]);
    }
    pNeedsTDCreated[playerid] = false;
    return 1;
}

// Needs_UpdateTextDraws: menggambar ulang isi bar sesuai nilai saat ini
stock Needs_UpdateTextDraws(playerid)
{
    if (UI_IsCef(playerid))
    {
        return UI_HudNeeds(playerid,
            Society_PlayerData[playerid][sPHunger],
            Society_PlayerData[playerid][sPThirst],
            Society_PlayerData[playerid][sPStress]);
    }
    if (!pNeedsTDCreated[playerid]) return 0;
    new str[48];
    Needs_BuildBar("Makan", Society_PlayerData[playerid][sPHunger], false, str, sizeof(str));
    PlayerTextDrawSetString(playerid, pNeedsTD[playerid][NEEDS_MAKAN], str);
    Needs_BuildBar("Minum", Society_PlayerData[playerid][sPThirst], false, str, sizeof(str));
    PlayerTextDrawSetString(playerid, pNeedsTD[playerid][NEEDS_MINUM], str);
    Needs_BuildBar("Stress", Society_PlayerData[playerid][sPStress], true, str, sizeof(str));
    PlayerTextDrawSetString(playerid, pNeedsTD[playerid][NEEDS_STRESS], str);
    return 1;
}

stock Needs_Show(playerid)
{
    if (UI_IsCef(playerid)) return Needs_UpdateTextDraws(playerid); // HUD HTML
    Needs_CreateTextDraws(playerid);
    Needs_UpdateTextDraws(playerid);
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawShow(playerid, pNeedsTD[playerid][i]);
    }
    return 1;
}

stock Needs_Hide(playerid)
{
    if (!pNeedsTDCreated[playerid]) return 0;
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawHide(playerid, pNeedsTD[playerid][i]);
    }
    return 1;
}

// Needs_Eat: /eat — menambah kenyang, mengurangi sedikit stress
stock Needs_Eat(playerid)
{
    if (Society_PlayerData[playerid][sPHunger] >= 100.0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Kamu sudah kenyang.");
        return 1;
    }
    new now = GetTickCount();
    if (now - Society_PlayerData[playerid][sPNeedsCD] < 5000)
    {
        SendClientMessage(playerid, COLOR_GREY, "Tunggu sebentar sebelum makan lagi.");
        return 1;
    }
    Society_PlayerData[playerid][sPNeedsCD] = now;
    Society_PlayerData[playerid][sPHunger] += 35.0;
    if (Society_PlayerData[playerid][sPHunger] > 100.0) Society_PlayerData[playerid][sPHunger] = 100.0;
    Society_PlayerData[playerid][sPStress] -= 10.0;
    if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
    SendClientMessage(playerid, COLOR_GREEN, "Kamu makan. Kenyang +35, stress berkurang.");
    Needs_UpdateTextDraws(playerid);
    return 1;
}

// Needs_Drink: /drink — menghilangkan haus, mengurangi sedikit stress
stock Needs_Drink(playerid)
{
    if (Society_PlayerData[playerid][sPThirst] >= 100.0)
    {
        SendClientMessage(playerid, COLOR_GREY, "Kamu tidak haus.");
        return 1;
    }
    new now = GetTickCount();
    if (now - Society_PlayerData[playerid][sPNeedsCD] < 5000)
    {
        SendClientMessage(playerid, COLOR_GREY, "Tunggu sebentar sebelum minum lagi.");
        return 1;
    }
    Society_PlayerData[playerid][sPNeedsCD] = now;
    Society_PlayerData[playerid][sPThirst] += 35.0;
    if (Society_PlayerData[playerid][sPThirst] > 100.0) Society_PlayerData[playerid][sPThirst] = 100.0;
    Society_PlayerData[playerid][sPStress] -= 10.0;
    if (Society_PlayerData[playerid][sPStress] < 0.0) Society_PlayerData[playerid][sPStress] = 0.0;
    SendClientMessage(playerid, COLOR_GREEN, "Kamu minum. Haus hilang +35, stress berkurang.");
    Needs_UpdateTextDraws(playerid);
    return 1;
}

// NeedsTick: dipanggil tiap 60 detik via SetTimer di OnGameModeInit
forward NeedsTick();
public NeedsTick()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (!IsPlayerConnected(i)) continue;
        if (!Society_PlayerData[i][sPLogged] || Society_PlayerData[i][sPCharID] <= 0) continue;

        Society_PlayerData[i][sPHunger] -= 1.0;
        Society_PlayerData[i][sPThirst] -= 1.5;
        if (Society_PlayerData[i][sPHunger] < 25.0 || Society_PlayerData[i][sPThirst] < 25.0)
            Society_PlayerData[i][sPStress] += 2.0;
        else
            Society_PlayerData[i][sPStress] -= 0.5;

        if (Society_PlayerData[i][sPHunger] < 0.0) Society_PlayerData[i][sPHunger] = 0.0;
        if (Society_PlayerData[i][sPThirst] < 0.0) Society_PlayerData[i][sPThirst] = 0.0;
        if (Society_PlayerData[i][sPStress] < 0.0) Society_PlayerData[i][sPStress] = 0.0;
        if (Society_PlayerData[i][sPStress] > 100.0) Society_PlayerData[i][sPStress] = 100.0;

        new Float:hp;
        if (Society_PlayerData[i][sPHunger] <= 0.0)
        {
            GetPlayerHealth(i, hp);
            SetPlayerHealth(i, hp - 3.0);
            SendClientMessage(i, COLOR_RED, "Kamu kelaparan! Segera makan! (/eat)");
        }
        if (Society_PlayerData[i][sPThirst] <= 0.0)
        {
            GetPlayerHealth(i, hp);
            SetPlayerHealth(i, hp - 3.0);
            SendClientMessage(i, COLOR_RED, "Kamu kehausan! Segera minum! (/drink)");
        }
        if (Society_PlayerData[i][sPStress] >= 100.0)
        {
            GetPlayerHealth(i, hp);
            SetPlayerHealth(i, hp - 2.0);
            SendClientMessage(i, COLOR_RED, "Stress kamu mencapai batas! Cari makan/drink untuk menurunkannya.");
        }
        Needs_UpdateTextDraws(i);
    }
    return 1;
}
