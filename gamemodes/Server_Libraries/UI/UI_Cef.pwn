//================================================================
// Society Roleplay - UI_Cef
// Router UI: CEF/WebView (HTML) untuk pemain SA-MP Mobile Launcher
// yang WebView-nya aktif, fallback textdraw+dialog untuk lainnya.
//
// Cara kerja:
//  - Saat connect, timer 2.5 dtk mengecek CefIsCEFReady() (artinya
//    RPC_LibraryInit diterima = client mobile launcher).
//  - Kalau ya: CefInitBrowser() -> loading -> OnCefBrowserInit ->
//    CefSyncUI() -> OnCefUIReady -> pemain ditandai UI_IsCef().
//  - Dialog_Show (via patch easyDialog.inc) otomatis dialihkan ke
//    UI_CefDialog() untuk pemain CEF; pemain lain tetap dialog biasa.
//  - TextDraw sistem (needs/kendaraan/zona/inventory) dialihkan ke
//    event __ui_hud oleh masing-masing sistem via fungsi UI_Hud*.
//
// Protokol event (server <-> web), separator = 0x1F (unit separator):
//  Server -> web:
//    "__ui_dialog" : nama<US>style<US>caption<US>info<US>button1<US>button2
//    "__ui_dialog_close" : (tutup dialog yang terbuka)
//    "__ui_hud"    : section<US>data...
//       "needs"   : makan<US>minum<US>stress   (0-100)
//       "zone"    : "show"<US>nama<US>warna | "hide"   (warna: 0 hijau, 1 merah)
//       "vehicle" : "show"<US>plat<US>nama<US>kunci<US>bensin | "hide"
//       "inv"     : "show"<US>nama1:jumlah;nama2:jumlah;... | "hide"
//  Web -> server (cef.emit):
//    "__ui_dialog_resp" : nama<US>response<US>listitem<US>inputtext
//    "__ui_inv_click"   : index
//
// Di-include dari gamemodes/Society_Main.pwn SETELAH <Pawn.RakNet>
// dan <MobileCEF>, SEBELUM <easyDialog>.
//================================================================

#if defined _UI_CEF_INC_
    #endinput
#endif
#define _UI_CEF_INC_

// Separator field payload (unit separator, tidak mungkin diketik pemain)
#define UI_SEP (0x1F)

static stock bool:g_UICefActive[MAX_PLAYERS];

//----------------------------------------------------------------
// Status & lifecycle
//----------------------------------------------------------------

// UI_IsCef: true jika pemain memakai mobile launcher + WebView aktif.
stock bool:UI_IsCef(playerid)
{
    if (!(0 <= playerid < MAX_PLAYERS)) return false;
    return g_UICefActive[playerid];
}

stock UI_SetCefActive(playerid, bool:active)
{
    if (0 <= playerid < MAX_PLAYERS) g_UICefActive[playerid] = active;
    return 1;
}

// UI_CefInitCheck: dipanggil via timer setelah connect. RPC_LibraryInit
// dikirim native client tepat saat join, jadi setelah 2.5 dtk statusnya
// sudah pasti (hanya mobile launcher yang mengirimnya).
forward UI_CefInitCheck(playerid);
public UI_CefInitCheck(playerid)
{
    if (!IsPlayerConnected(playerid)) return 0;
    if (CefIsCEFReady(playerid))
    {
        CefInitBrowser(playerid, "cef://__internal/loading.html");
    }
    return 1;
}

stock UI_OnPlayerConnect(playerid)
{
    g_UICefActive[playerid] = false;
    SetTimerEx("UI_CefInitCheck", 2500, false, "d", playerid);
    return 1;
}

stock UI_OnPlayerDisconnect(playerid)
{
    g_UICefActive[playerid] = false;
    return 1;
}

// UI_Init: daftarkan callback event web->server. Dipanggil sekali dari
// OnGameModeInit (setelah CefSetPacketId).
stock UI_Init()
{
    CefRegisterEventCallback("__ui_dialog_resp", "UI_OnDialogResp");
    CefRegisterEventCallback("__ui_inv_click", "UI_OnInvClick");
    return 1;
}

//----------------------------------------------------------------
// Helper payload
//----------------------------------------------------------------

// UI_JsonUnwrap: ambil string pertama dari JSON array ["..."] yang dikirim
// cef.emit(), sekaligus unescape (\" \\ \n \uXXXX, mis. \u001f -> 0x1F).
stock UI_JsonUnwrap(const json[], out[], outsize)
{
    new i = 0, o = 0, l = strlen(json);
    while (i < l && json[i] != '"') i++;
    if (i >= l) { out[0] = EOS; return 0; }
    i++; // lewati '"' pembuka
    while (i < l && o < outsize - 1)
    {
        new c = json[i];
        if (c == '"') break; // '"' penutup (yang tidak di-escape)
        if (c == '\\' && i + 1 < l)
        {
            new e = json[i + 1];
            if (e == 'n') { out[o++] = '\n'; i += 2; continue; }
            if (e == 'r') { out[o++] = '\r'; i += 2; continue; }
            if (e == 't') { out[o++] = '\t'; i += 2; continue; }
            if (e == '"') { out[o++] = '"'; i += 2; continue; }
            if (e == '\\') { out[o++] = '\\'; i += 2; continue; }
            if (e == '/') { out[o++] = '/'; i += 2; continue; }
            if (e == 'u' && i + 5 < l)
            {
                new v = 0;
                for (new k = 0; k < 4; k++)
                {
                    new h = json[i + 2 + k];
                    v <<= 4;
                    if (h >= '0' && h <= '9') v |= h - '0';
                    else if (h >= 'a' && h <= 'f') v |= h - 'a' + 10;
                    else if (h >= 'A' && h <= 'F') v |= h - 'A' + 10;
                }
                if (v >= 0 && v < 256) out[o++] = v;
                i += 6;
                continue;
            }
            i++; // escape tak dikenal: buang backslash-nya saja
            continue;
        }
        out[o++] = c;
        i++;
    }
    out[o] = EOS;
    return 1;
}

// UI_StripSep: buang karakter separator dari string (pengaman).
stock UI_StripSep(const src[], dest[], len)
{
    new o = 0;
    for (new i = 0, l = strlen(src); i < l && o < len - 1; i++)
    {
        if (src[i] == UI_SEP) continue;
        dest[o++] = src[i];
    }
    dest[o] = EOS;
    return 1;
}

// UI_SplitField: ambil field ke-index (0-based) dari payload.
stock UI_SplitField(const payload[], index, out[], outsize)
{
    new field = 0, o = 0;
    out[0] = EOS;
    for (new i = 0, l = strlen(payload); i <= l; i++)
    {
        new c = (i < l) ? payload[i] : 0;
        if (c == UI_SEP || c == 0)
        {
            if (field == index) { out[o] = EOS; return 1; }
            field++;
            o = 0;
            if (field > index) { out[0] = EOS; return 0; }
        }
        else if (field == index)
        {
            if (o < outsize - 1) out[o++] = c;
        }
    }
    out[0] = EOS;
    return 0;
}

//----------------------------------------------------------------
// Dialog: server -> web
//----------------------------------------------------------------

// UI_CefDialog: kirim dialog ke WebView pemain (dipanggil otomatis dari
// Dialog_Open yang di-patch di easyDialog.inc).
stock UI_CefDialog(playerid, const funcname[], style, const caption[],
    const info[], const button1[], const button2[])
{
    if (!UI_IsCef(playerid)) return 0;
    new fn[32], cap[128], inf[3000], b1[32], b2[32];
    UI_StripSep(funcname, fn, sizeof fn);
    UI_StripSep(caption, cap, sizeof cap);
    // info list bisa panjang; batasi agar muat di paket event (maks 4000)
    new ilen = strlen(info);
    if (ilen > 2999) ilen = 2999;
    for (new i = 0; i < ilen; i++)
    {
        if (info[i] == UI_SEP) inf[i] = ' ';
        else inf[i] = info[i];
    }
    inf[ilen] = EOS;
    UI_StripSep(button1, b1, sizeof b1);
    UI_StripSep(button2, b2, sizeof b2);
    new payload[3400];
    format(payload, sizeof payload, "%s%c%d%c%s%c%s%c%s%c%s",
        fn, UI_SEP, style, UI_SEP, cap, UI_SEP, inf, UI_SEP, b1, UI_SEP, b2);
    CefSendEvent(playerid, "__ui_dialog", payload);
    return 1;
}

// UI_CloseCefDialog: tutup dialog CEF yang sedang terbuka.
stock UI_CloseCefDialog(playerid)
{
    if (!UI_IsCef(playerid)) return 0;
    CefSendEvent(playerid, "__ui_dialog_close", "");
    return 1;
}

//----------------------------------------------------------------
// Dialog: web -> server
//----------------------------------------------------------------

// UI_OnDialogResp: respons dialog dari WebView -> teruskan ke handler
// dialog_<nama> yang sama seperti dialog biasa (gaya easyDialog).
forward UI_OnDialogResp(playerid, const data[]);
public UI_OnDialogResp(playerid, const data[])
{
    new packed[2048];
    UI_JsonUnwrap(data, packed, sizeof packed); // "['nama<US>resp<US>item<US>input']"
    new name[32], sResp[8], sItem[8], input[1024];
    UI_SplitField(packed, 0, name, sizeof name);
    UI_SplitField(packed, 1, sResp, sizeof sResp);
    UI_SplitField(packed, 2, sItem, sizeof sItem);
    UI_SplitField(packed, 3, input, sizeof input);
    new response = strval(sResp);
    new listitem = strval(sItem);
    // Sanitasi seperti easyDialog: '%' -> '#'
    for (new i = 0, l = strlen(input); i < l; i++)
    {
        if (input[i] == '%') input[i] = '#';
    }
    new func[40];
    format(func, sizeof func, "dialog_%s", name);
    new hasFunc = (funcidx(func) != -1);
    new hasPerformed = funcidx("OnDialogPerformed");
    if (hasPerformed == -1 ||
        CallLocalFunction("OnDialogPerformed", "dsdd", playerid, name, response, hasFunc))
    {
        if (hasFunc)
            CallLocalFunction(func, "ddds", playerid, response, listitem,
                input[0] ? input : "\1");
    }
    return 1;
}

//----------------------------------------------------------------
// HUD: server -> web (pengganti textdraw)
//----------------------------------------------------------------

stock UI_HudNeeds(playerid, Float:makan, Float:minum, Float:stress)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[64];
    format(payload, sizeof payload, "needs%c%d%c%d%c%d", UI_SEP,
        floatround(makan, floatround_round), UI_SEP,
        floatround(minum, floatround_round), UI_SEP,
        floatround(stress, floatround_round));
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

stock UI_HudZone(playerid, const name[], bool:isGreen)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[96], nm[48];
    UI_StripSep(name, nm, sizeof nm);
    format(payload, sizeof payload, "zone%cshow%c%s%c%d", UI_SEP, UI_SEP, nm,
        UI_SEP, isGreen ? 0 : 1);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

stock UI_HudZoneHide(playerid)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[32];
    format(payload, sizeof payload, "zone%chide", UI_SEP);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

stock UI_HudVehicle(playerid, const plate[], const nama[], const kunci[], bensin)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[192], pl[32], nm[32], kn[16];
    UI_StripSep(plate, pl, sizeof pl);
    UI_StripSep(nama, nm, sizeof nm);
    UI_StripSep(kunci, kn, sizeof kn);
    format(payload, sizeof payload, "vehicle%cshow%c%s%c%s%c%s%c%d", UI_SEP,
        UI_SEP, pl, UI_SEP, nm, UI_SEP, kn, UI_SEP, bensin);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

stock UI_HudVehicleHide(playerid)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[32];
    format(payload, sizeof payload, "vehicle%chide", UI_SEP);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

// UI_HudInvShow: kirim isi tas. items[] = "nama:jumlah;nama:jumlah;..."
stock UI_HudInvShow(playerid, const items[])
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[512], it[480];
    UI_StripSep(items, it, sizeof it);
    // ':' dan ';' adalah delimiter item, buang dari nama
    for (new i = 0, l = strlen(it); i < l; i++)
    {
        if (it[i] == ':' || it[i] == ';') it[i] = ' ';
    }
    format(payload, sizeof payload, "inv%cshow%c%s", UI_SEP, UI_SEP, it);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

stock UI_HudInvHide(playerid)
{
    if (!UI_IsCef(playerid)) return 0;
    new payload[32];
    format(payload, sizeof payload, "inv%chide", UI_SEP);
    CefSendEvent(playerid, "__ui_hud", payload);
    return 1;
}

// UI_OnInvClick: klik item inventory di WebView -> teruskan ke sistem
// inventory (Inventory_OnCefClick didefinisikan di Inventory_System.pwn).
forward UI_OnInvClick(playerid, const data[]);
public UI_OnInvClick(playerid, const data[])
{
    new packed[32];
    UI_JsonUnwrap(data, packed, sizeof packed); // '["<index>"]'
    new idx = strval(packed);
    CallLocalFunction("Inventory_OnCefClick", "dd", playerid, idx);
    return 1;
}
