/*
	easyDialog.inc - Dialogs made easier!

	With this useful include, scripters can easily create
	dialogs and show them to players.

	This include will prevent dialog spoofing, ID collision
	and a lot more.

	Created by Emmet on Friday, January 24, 2014.
	Updated by Southclaws 2017-10-13 to add include guard.
	Updated by MichelDev 2023-02-24 new style and fix error HidePlayerDialog (open-mp RC2)
	Updated by adib-yg 2023-11-15 to add the DIALOG_STYLE tag.
	Patched for Society Roleplay: hapus tag const pada parameter Dialog_Open
	(compiler Pawn 3.10.10 melempar error 035 untuk const[] -> [] pada file besar).
*/

#if defined _easyDialog_included
	#endinput
#endif
#define _easyDialog_included

#if !defined isnull
	#define isnull(%1) \
		((!(%1[0])) || (((%1[0]) == '\1') && (!(%1[1]))))
#endif

#if !defined HidePlayerDialog
	#define HidePlayerDialog(%1) \
		ShowPlayerDialog(%1, -1, 0, " ", " ", " ", " ")
#endif

#define Dialog:%0(%1) \
	forward dialog_%0(%1); public dialog_%0(%1)

#define Dialog_Show(%0,%1, \
	Dialog_Open(%0, #%1,

#define Dialog_Opened(%0) \
	(CallRemoteFunction("Dialog_IsOpened", "i", (%0)))

#if !defined _INC_open_mp
	#if !defined DIALOG_STYLE
		#define DIALOG_STYLE: _:
	#endif
#endif

static
	s_DialogName[MAX_PLAYERS][32 char],
	bool: s_DialogOpened[MAX_PLAYERS]
;

forward OnDialogPerformed(playerid, const dialog[], response, success);

forward @dialog_format(); @dialog_format() {
	new emptyString[] = '\1';
	format(emptyString, sizeof(emptyString), emptyString);
}

forward Dialog_IsOpened(playerid);
public Dialog_IsOpened(playerid) {
	return (s_DialogOpened[playerid]);
}

stock Dialog_Close(playerid) {
	s_DialogName[playerid]{0} = 0;
	s_DialogOpened[playerid] = false;

#if defined _UI_CEF_INC_
	// Society RP: tutup juga dialog HTML bila pemain memakai CEF.
	if (UI_IsCef(playerid)) {
		CefSendEvent(playerid, "__ui_dialog_close", "");
	}
#endif

	return HidePlayerDialog(playerid);
}

stock Dialog_Open(playerid, function[], DIALOG_STYLE:style, caption[], info[], button1[], button2[], {Float,_}:...) {
	static
		string[4096],
		args
	;

	if (!strlen(info)) {
		return 0;
	}
#if defined _UI_CEF_INC_
	// Society RP: pemain dengan CEF aktif mendapat dialog HTML (WebView),
	// bukan dialog SA-MP biasa. Semua 90 Dialog_Show otomatis dialihkan.
	if (UI_IsCef(playerid)) {
		return UI_CefDialog(playerid, function, _:style, caption, info, button1, button2);
	}
#endif
	if ((args = numargs()) > 7) {
		while (--args >= 7) {
			#emit LCTRL 5
			#emit LOAD.alt args
			#emit SHL.C.alt 2
			#emit ADD.C 12
			#emit ADD
			#emit LOAD.I
			#emit PUSH.pri
		}
		#emit PUSH.S info
		#emit PUSH.C 4096
		#emit PUSH.C string

		#emit LOAD.S.pri 8
		#emit CONST.alt 16
		#emit SUB
		#emit PUSH.pri

		#emit SYSREQ.C format
		#emit LCTRL 5
		#emit SCTRL 4

		ShowPlayerDialog(playerid, 32700, style, caption, string, button1, button2);
	}
	else {
		ShowPlayerDialog(playerid, 32700, style, caption, info, button1, button2);
	}
	s_DialogOpened[playerid] = true;

	strpack(s_DialogName[playerid], function, 32 char);

	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[]) {
	static
		s_Public = cellmax;

	if (s_Public == cellmax) {
		s_Public = funcidx("OnDialogPerformed");
	}

	// Sanitize inputs.
	for (new i = 0, l = strlen(inputtext); i < l; i ++) {
		if (inputtext[i] == '%') {
			inputtext[i] = '#';
		}
	}
	
	if (dialogid == 32700 && strlen(s_DialogName[playerid]) > 0) {
		new
			string[40];

		strcat(string, "dialog_");
		strcat(string, s_DialogName[playerid]);

		Dialog_Close(playerid);

		if ((s_Public == -1) || (CallLocalFunction("OnDialogPerformed", "dsdd", playerid, string[7], response, funcidx(string) != -1))) {
	 		CallLocalFunction(string, "ddds", playerid, response, listitem, (!inputtext[0]) ? ("\1") : (inputtext));
		}
	}
	#if defined DR_OnDialogResponse
		return DR_OnDialogResponse(playerid, dialogid, response, listitem, inputtext);
	#else
		return 0;
	#endif
}

#if defined _ALS_OnDialogResponse
	#undef OnDialogResponse
#else
	#define _ALS_OnDialogResponse
#endif

#define OnDialogResponse DR_OnDialogResponse

#if defined DR_OnDialogResponse
	forward DR_OnDialogResponse(playerid, dialogid, response, listitem, inputtext[]);
#endif
