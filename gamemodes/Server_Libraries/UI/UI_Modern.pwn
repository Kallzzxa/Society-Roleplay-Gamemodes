//================================================================
// Society Roleplay - UI_Modern
// UI kit gaya modern (inspirasi NoPixel/FiveM), full textdraw:
//  - UI_Notify: notifikasi pil kanan-atas, hilang otomatis.
//  - UI_ShowMenu: menu modern pengganti dialog LIST/MSGBOX.
//    Klik via SelectTextDraw; hasil klik diteruskan ke handler
//    dialog yang SAMA (public dialog_<Nama>) via CallLocalFunction,
//    jadi migrasi dialog lama cukup ganti Dialog_Show -> UI_ShowMenu.
// Tema: latar hitam transparan, teks putih, aksen teal/hijau.
// Di-include dari gamemodes/Society_Main.pwn (setelah Utils).
//================================================================

#if defined _ui_modern_included
    #endinput
#endif
#define _ui_modern_included

//---- Palet tema ----
#define UI_COL_BG      0x0C0C0CE6  // hitam transparan (panel)
#define UI_COL_ACCENT  0x00D8A8FF  // teal/hijau aksen utama
#define UI_COL_WHITE   0xFFFFFFFF
#define UI_COL_GREY    0xAAAAAAFF
#define UI_COL_GREEN   0x2EE66BFF
#define UI_COL_RED     0xFF5555FF
#define UI_COL_BLUE    0x4A9EFFFF

//---- Batas ----
#define UI_MAX_OPTS    12
#define UI_MAX_NOTIF   3
#define UI_NOTIF_MS    4500

//---- Tipe notifikasi ----
#define UI_NT_INFO     0
#define UI_NT_OK       1
#define UI_NT_ERR      2

//==== MENU MODERN ====
new PlayerText:uiMenuBG[MAX_PLAYERS];
new PlayerText:uiMenuBar[MAX_PLAYERS];
new PlayerText:uiMenuTitle[MAX_PLAYERS];
new PlayerText:uiMenuSub[MAX_PLAYERS];
new PlayerText:uiMenuOpt[MAX_PLAYERS][UI_MAX_OPTS];
new PlayerText:uiMenuFoot[MAX_PLAYERS];
new bool:uiMenuOpen[MAX_PLAYERS];
new uiMenuHandler[MAX_PLAYERS][32];
new uiMenuCount[MAX_PLAYERS];

//==== NOTIFIKASI ====
new PlayerText:uiNtBG[MAX_PLAYERS][UI_MAX_NOTIF];
new PlayerText:uiNtBar[MAX_PLAYERS][UI_MAX_NOTIF];
new PlayerText:uiNtTx[MAX_PLAYERS][UI_MAX_NOTIF];
new uiNtExpire[MAX_PLAYERS][UI_MAX_NOTIF];
new bool:uiNtMade[MAX_PLAYERS];

//==== FORWARD ====
forward UITick();

// UI_CountLines: menghitung baris teks (~n~) untuk tinggi panel.
stock UI_CountLines(const str[])
{
    new n = 1, len = strlen(str);
    for (new i = 0; i < len - 2; i++)
    {
        if (str[i] == '~' && str[i+1] == 'n' && str[i+2] == '~')
        {
            n++;
            i += 2;
        }
    }
    return n;
}

//================================================================
// MENU MODERN
//================================================================

// UI_DestroyMenu: menghapus semua textdraw menu pemain.
stock UI_DestroyMenu(playerid)
{
    if (uiMenuBG[playerid] != PlayerText:0)
    {
        PlayerTextDrawDestroy(playerid, uiMenuBG[playerid]);
        uiMenuBG[playerid] = PlayerText:0;
    }
    if (uiMenuBar[playerid] != PlayerText:0)
    {
        PlayerTextDrawDestroy(playerid, uiMenuBar[playerid]);
        uiMenuBar[playerid] = PlayerText:0;
    }
    if (uiMenuTitle[playerid] != PlayerText:0)
    {
        PlayerTextDrawDestroy(playerid, uiMenuTitle[playerid]);
        uiMenuTitle[playerid] = PlayerText:0;
    }
    if (uiMenuSub[playerid] != PlayerText:0)
    {
        PlayerTextDrawDestroy(playerid, uiMenuSub[playerid]);
        uiMenuSub[playerid] = PlayerText:0;
    }
    for (new i = 0; i < UI_MAX_OPTS; i++)
    {
        if (uiMenuOpt[playerid][i] != PlayerText:0)
        {
            PlayerTextDrawDestroy(playerid, uiMenuOpt[playerid][i]);
            uiMenuOpt[playerid][i] = PlayerText:0;
        }
    }
    if (uiMenuFoot[playerid] != PlayerText:0)
    {
        PlayerTextDrawDestroy(playerid, uiMenuFoot[playerid]);
        uiMenuFoot[playerid] = PlayerText:0;
    }
    return 1;
}

// UI_ShowMenu: menampilkan menu modern.
// handler = nama public dialog ("dialog_<Nama>") yang menerima klik.
// subtitle mendukung ~n~. options = daftar teks opsi (maks UI_MAX_OPTS).
stock UI_ShowMenu(playerid, handler[], title[], subtitle[], options[][64], optcount)
{
    if (optcount < 1) return 0;
    if (optcount > UI_MAX_OPTS) optcount = UI_MAX_OPTS;

    UI_DestroyMenu(playerid);
    uiMenuOpen[playerid] = false;
    format(uiMenuHandler[playerid], sizeof(uiMenuHandler[]), "%s", handler);
    uiMenuCount[playerid] = optcount;

    new sublines = UI_CountLines(subtitle);
    new Float:oy = 186.0 + float(sublines) * 11.0 + 8.0; // y opsi pertama
    new Float:panelB = oy + float(optcount) * 22.0 + 26.0; // bawah panel

    // Latar panel.
    uiMenuBG[playerid] = CreatePlayerTextDraw(playerid, 445.0, 140.0, "_");
    PlayerTextDrawTextSize(playerid, uiMenuBG[playerid], 620.0, panelB);
    PlayerTextDrawUseBox(playerid, uiMenuBG[playerid], 1);
    PlayerTextDrawBoxColor(playerid, uiMenuBG[playerid], UI_COL_BG);
    // Garis aksen teal di bawah judul.
    uiMenuBar[playerid] = CreatePlayerTextDraw(playerid, 445.0, 170.0, "_");
    PlayerTextDrawTextSize(playerid, uiMenuBar[playerid], 620.0, 172.0);
    PlayerTextDrawUseBox(playerid, uiMenuBar[playerid], 1);
    PlayerTextDrawBoxColor(playerid, uiMenuBar[playerid], UI_COL_ACCENT);
    // Judul.
    uiMenuTitle[playerid] = CreatePlayerTextDraw(playerid, 455.0, 146.0, title);
    PlayerTextDrawFont(playerid, uiMenuTitle[playerid], 2);
    PlayerTextDrawLetterSize(playerid, uiMenuTitle[playerid], 0.28, 1.2);
    PlayerTextDrawColor(playerid, uiMenuTitle[playerid], UI_COL_WHITE);
    PlayerTextDrawSetOutline(playerid, uiMenuTitle[playerid], 1);
    // Subtitle / isi.
    uiMenuSub[playerid] = CreatePlayerTextDraw(playerid, 455.0, 178.0, subtitle);
    PlayerTextDrawFont(playerid, uiMenuSub[playerid], 1);
    PlayerTextDrawLetterSize(playerid, uiMenuSub[playerid], 0.21, 0.95);
    PlayerTextDrawColor(playerid, uiMenuSub[playerid], UI_COL_GREY);
    PlayerTextDrawSetOutline(playerid, uiMenuSub[playerid], 1);
    // Opsi (bisa diklik).
    for (new i = 0; i < optcount; i++)
    {
        new Float:rowY = oy + float(i) * 22.0;
        uiMenuOpt[playerid][i] = CreatePlayerTextDraw(playerid, 455.0, rowY, options[i]);
        PlayerTextDrawFont(playerid, uiMenuOpt[playerid][i], 1);
        PlayerTextDrawLetterSize(playerid, uiMenuOpt[playerid][i], 0.24, 1.05);
        PlayerTextDrawColor(playerid, uiMenuOpt[playerid][i], UI_COL_WHITE);
        PlayerTextDrawSetOutline(playerid, uiMenuOpt[playerid][i], 1);
        PlayerTextDrawTextSize(playerid, uiMenuOpt[playerid][i], 613.0, rowY + 16.0);
        PlayerTextDrawSetSelectable(playerid, uiMenuOpt[playerid][i], 1);
    }
    // Footer.
    uiMenuFoot[playerid] = CreatePlayerTextDraw(playerid, 532.0, panelB - 18.0, "ESC tutup");
    PlayerTextDrawAlignment(playerid, uiMenuFoot[playerid], 2);
    PlayerTextDrawFont(playerid, uiMenuFoot[playerid], 1);
    PlayerTextDrawLetterSize(playerid, uiMenuFoot[playerid], 0.19, 0.85);
    PlayerTextDrawColor(playerid, uiMenuFoot[playerid], UI_COL_GREY);

    PlayerTextDrawShow(playerid, uiMenuBG[playerid]);
    PlayerTextDrawShow(playerid, uiMenuBar[playerid]);
    PlayerTextDrawShow(playerid, uiMenuTitle[playerid]);
    PlayerTextDrawShow(playerid, uiMenuSub[playerid]);
    for (new i = 0; i < optcount; i++)
    {
        PlayerTextDrawShow(playerid, uiMenuOpt[playerid][i]);
    }
    PlayerTextDrawShow(playerid, uiMenuFoot[playerid]);

    uiMenuOpen[playerid] = true;
    SelectTextDraw(playerid, 0x00D8A8AA); // hover = aksen teal
    return 1;
}

// UI_CloseMenu: menutup menu & meneruskan hasil ke handler dialog.
stock UI_CloseMenu(playerid, response, listitem)
{
    if (!uiMenuOpen[playerid]) return 0;
    uiMenuOpen[playerid] = false;
    new handler[32];
    format(handler, sizeof(handler), "%s", uiMenuHandler[playerid]);
    CancelSelectTextDraw(playerid);
    UI_DestroyMenu(playerid);
    new inputtext[2];
    inputtext[0] = '\1';
    inputtext[1] = EOS;
    CallLocalFunction(handler, "ddds", playerid, response, listitem, inputtext);
    return 1;
}

// UI_OnMenuClick: menangani klik textdraw menu (dari OnPlayerClickPlayerTextDraw).
stock UI_OnMenuClick(playerid, PlayerText:playertextid)
{
    if (!uiMenuOpen[playerid]) return 0;
    if (playertextid == PlayerText:INVALID_TEXT_DRAW)
    {
        UI_CloseMenu(playerid, 0, -1); // ESC = batal
        return 1;
    }
    for (new i = 0; i < uiMenuCount[playerid]; i++)
    {
        if (playertextid == uiMenuOpt[playerid][i])
        {
            UI_CloseMenu(playerid, 1, i);
            return 1;
        }
    }
    return 0;
}

// UI_HideMenu: menutup menu tanpa memanggil handler (mis. disconnect).
stock UI_HideMenu(playerid)
{
    if (!uiMenuOpen[playerid]) return 0;
    uiMenuOpen[playerid] = false;
    CancelSelectTextDraw(playerid);
    UI_DestroyMenu(playerid);
    return 1;
}

//================================================================
// NOTIFIKASI
//================================================================

// UI_MakeNotif: membuat textdraw notifikasi (sekali per sesi).
stock UI_MakeNotif(playerid)
{
    if (uiNtMade[playerid]) return 1;
    for (new i = 0; i < UI_MAX_NOTIF; i++)
    {
        new Float:ny = 70.0 + float(i) * 40.0;
        uiNtBG[playerid][i] = CreatePlayerTextDraw(playerid, 470.0, ny, "_");
        PlayerTextDrawTextSize(playerid, uiNtBG[playerid][i], 630.0, ny + 32.0);
        PlayerTextDrawUseBox(playerid, uiNtBG[playerid][i], 1);
        PlayerTextDrawBoxColor(playerid, uiNtBG[playerid][i], UI_COL_BG);
        uiNtBar[playerid][i] = CreatePlayerTextDraw(playerid, 470.0, ny, "_");
        PlayerTextDrawTextSize(playerid, uiNtBar[playerid][i], 476.0, ny + 32.0);
        PlayerTextDrawUseBox(playerid, uiNtBar[playerid][i], 1);
        PlayerTextDrawBoxColor(playerid, uiNtBar[playerid][i], UI_COL_BLUE);
        uiNtTx[playerid][i] = CreatePlayerTextDraw(playerid, 484.0, ny + 7.0, " ");
        PlayerTextDrawFont(playerid, uiNtTx[playerid][i], 1);
        PlayerTextDrawLetterSize(playerid, uiNtTx[playerid][i], 0.22, 1.0);
        PlayerTextDrawColor(playerid, uiNtTx[playerid][i], UI_COL_WHITE);
        PlayerTextDrawSetOutline(playerid, uiNtTx[playerid][i], 1);
        uiNtExpire[playerid][i] = 0;
    }
    uiNtMade[playerid] = true;
    return 1;
}

// UI_Notify: menampilkan notifikasi kanan-atas (type: 0=info,1=ok,2=error).
stock UI_Notify(playerid, type, text[])
{
    UI_MakeNotif(playerid);
    new now = GetTickCount(), slot = -1, oldest = 0, oldestT = 0x7fffffff;
    for (new i = 0; i < UI_MAX_NOTIF; i++)
    {
        if (uiNtExpire[playerid][i] <= now)
        {
            slot = i;
            break;
        }
        if (uiNtExpire[playerid][i] < oldestT)
        {
            oldestT = uiNtExpire[playerid][i];
            oldest = i;
        }
    }
    if (slot == -1) slot = oldest;
    new col = UI_COL_BLUE;
    if (type == UI_NT_OK) col = UI_COL_GREEN;
    else if (type == UI_NT_ERR) col = UI_COL_RED;
    PlayerTextDrawBoxColor(playerid, uiNtBar[playerid][slot], col);
    PlayerTextDrawSetString(playerid, uiNtTx[playerid][slot], text);
    PlayerTextDrawShow(playerid, uiNtBG[playerid][slot]);
    PlayerTextDrawShow(playerid, uiNtBar[playerid][slot]);
    PlayerTextDrawShow(playerid, uiNtTx[playerid][slot]);
    uiNtExpire[playerid][slot] = now + UI_NOTIF_MS;
    return 1;
}

// UI_HideNotif: menyembunyikan semua notifikasi pemain.
stock UI_HideNotif(playerid)
{
    if (!uiNtMade[playerid]) return 0;
    for (new i = 0; i < UI_MAX_NOTIF; i++)
    {
        PlayerTextDrawHide(playerid, uiNtBG[playerid][i]);
        PlayerTextDrawHide(playerid, uiNtBar[playerid][i]);
        PlayerTextDrawHide(playerid, uiNtTx[playerid][i]);
        uiNtExpire[playerid][i] = 0;
    }
    return 1;
}

// UITick: menyembunyikan notifikasi yang kedaluwarsa (tiap 1 detik).
public UITick()
{
    new now = GetTickCount();
    for (new p = 0; p < MAX_PLAYERS; p++)
    {
        if (!IsPlayerConnected(p) || !uiNtMade[p]) continue;
        for (new i = 0; i < UI_MAX_NOTIF; i++)
        {
            if (uiNtExpire[p][i] != 0 && uiNtExpire[p][i] <= now)
            {
                PlayerTextDrawHide(p, uiNtBG[p][i]);
                PlayerTextDrawHide(p, uiNtBar[p][i]);
                PlayerTextDrawHide(p, uiNtTx[p][i]);
                uiNtExpire[p][i] = 0;
            }
        }
    }
    return 1;
}

// UI_OnDisconnect: bersih-bersih saat pemain keluar.
stock UI_OnDisconnect(playerid)
{
    UI_HideNotif(playerid);
    UI_HideMenu(playerid);
    uiMenuHandler[playerid][0] = EOS;
    uiMenuCount[playerid] = 0;
    return 1;
}
