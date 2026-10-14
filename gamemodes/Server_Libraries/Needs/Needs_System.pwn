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

new PlayerText:pNeedsLbl[MAX_PLAYERS][3];
new PlayerText:pNeedsBg[MAX_PLAYERS][3];
new PlayerText:pNeedsFill[MAX_PLAYERS][3];
new bool:pNeedsTDCreated[MAX_PLAYERS];

// HUD modern gaya NoPixel: bar tipis di kiri bawah layar.
// Tiap bar: label + latar gelap + isi berwarna (lebar ikut nilai).
#define NEEDS_BAR_X  115.0
#define NEEDS_BAR_W  100.0
#define NEEDS_BAR_H  8.0

new NeedsBarLabel[3][8] = {"MAKAN", "MINUM", "STRESS"};
new NeedsBarY[3] = {400, 418, 436};

// Needs_BarColor: warna isi bar (stress terbalik: tinggi = merah).
stock Needs_BarColor(idx, Float:value)
{
    if (idx == NEEDS_MAKAN) return 0x2EE66BFF;  // hijau
    if (idx == NEEDS_MINUM) return 0x4A9EFFFF;  // biru
    if (value > 60.0) return 0xFF5555FF;        // stress tinggi = merah
    if (value >= 30.0) return 0xFFAA00FF;       // sedang = oranye
    return 0x2EE66BFF;                          // rendah = hijau
}

// Needs_CreateTextDraws: membuat 9 player-textdraw (label+latar+isi x3)
stock Needs_CreateTextDraws(playerid)
{
    if (UI_IsCef(playerid)) return 1; // dirender via WebView (HUD HTML)
    if (pNeedsTDCreated[playerid]) return 1;
    for (new i = 0; i < 3; i++)
    {
        new Float:ly = float(NeedsBarY[i]);
        pNeedsLbl[playerid][i] = CreatePlayerTextDraw(playerid, 60.0, ly, NeedsBarLabel[i]);
        PlayerTextDrawFont(playerid, pNeedsLbl[playerid][i], 1);
        PlayerTextDrawLetterSize(playerid, pNeedsLbl[playerid][i], 0.20, 0.9);
        PlayerTextDrawColor(playerid, pNeedsLbl[playerid][i], 0xFFFFFFFF);
        PlayerTextDrawSetOutline(playerid, pNeedsLbl[playerid][i], 1);

        pNeedsBg[playerid][i] = CreatePlayerTextDraw(playerid, NEEDS_BAR_X, ly + 2.0, "_");
        PlayerTextDrawTextSize(playerid, pNeedsBg[playerid][i], NEEDS_BAR_X + NEEDS_BAR_W, ly + 2.0 + NEEDS_BAR_H);
        PlayerTextDrawUseBox(playerid, pNeedsBg[playerid][i], 1);
        PlayerTextDrawBoxColor(playerid, pNeedsBg[playerid][i], 0x0C0C0CCC);

        pNeedsFill[playerid][i] = CreatePlayerTextDraw(playerid, NEEDS_BAR_X, ly + 2.0, "_");
        PlayerTextDrawTextSize(playerid, pNeedsFill[playerid][i], NEEDS_BAR_X + NEEDS_BAR_W, ly + 2.0 + NEEDS_BAR_H);
        PlayerTextDrawUseBox(playerid, pNeedsFill[playerid][i], 1);
        PlayerTextDrawBoxColor(playerid, pNeedsFill[playerid][i], Needs_BarColor(i, 100.0));
    }
    pNeedsTDCreated[playerid] = true;
    return 1;
}

stock Needs_DestroyTextDraws(playerid)
{
    if (!pNeedsTDCreated[playerid]) return 1;
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawDestroy(playerid, pNeedsLbl[playerid][i]);
        PlayerTextDrawDestroy(playerid, pNeedsBg[playerid][i]);
        PlayerTextDrawDestroy(playerid, pNeedsFill[playerid][i]);
    }
    pNeedsTDCreated[playerid] = false;
    return 1;
}

// Needs_NeedValue: mengambil nilai kebutuhan dari data pemain.
stock Float:Needs_NeedValue(playerid, idx)
{
    if (idx == NEEDS_MAKAN) return Society_PlayerData[playerid][sPHunger];
    if (idx == NEEDS_MINUM) return Society_PlayerData[playerid][sPThirst];
    return Society_PlayerData[playerid][sPStress];
}

// Needs_UpdateTextDraws: menggambar ulang lebar & warna bar sesuai nilai
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
    for (new i = 0; i < 3; i++)
    {
        new Float:val = Needs_NeedValue(playerid, i);
        if (val < 0.0) val = 0.0;
        if (val > 100.0) val = 100.0;
        new Float:ly = float(NeedsBarY[i]);
        PlayerTextDrawTextSize(playerid, pNeedsFill[playerid][i],
            NEEDS_BAR_X + (val / 100.0) * NEEDS_BAR_W, ly + 2.0 + NEEDS_BAR_H);
        PlayerTextDrawBoxColor(playerid, pNeedsFill[playerid][i], Needs_BarColor(i, val));
        PlayerTextDrawShow(playerid, pNeedsFill[playerid][i]); // terapkan ulang ukuran
    }
    return 1;
}

stock Needs_Show(playerid)
{
    if (UI_IsCef(playerid)) return Needs_UpdateTextDraws(playerid); // HUD HTML
    Needs_CreateTextDraws(playerid);
    Needs_UpdateTextDraws(playerid);
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawShow(playerid, pNeedsLbl[playerid][i]);
        PlayerTextDrawShow(playerid, pNeedsBg[playerid][i]);
        PlayerTextDrawShow(playerid, pNeedsFill[playerid][i]);
    }
    return 1;
}

stock Needs_Hide(playerid)
{
    if (!pNeedsTDCreated[playerid]) return 0;
    for (new i = 0; i < 3; i++)
    {
        PlayerTextDrawHide(playerid, pNeedsLbl[playerid][i]);
        PlayerTextDrawHide(playerid, pNeedsBg[playerid][i]);
        PlayerTextDrawHide(playerid, pNeedsFill[playerid][i]);
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
