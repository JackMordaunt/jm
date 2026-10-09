/*
Package msg is everything Atlas says, in every language it ships: the Msg
enum names each message, and locales/<tag>.txt holds each locale's text,
embedded in the binary by #load and parsed by jm:i18n when the locale is
put to use. English is the source language and the fallback for any
message a translation leaves out.

To add a message, add its member here and its line to locales/en.txt;
msg_test fails until every other locale translates it.
*/
package msg

import "jm:i18n"

Msg :: enum u16 {
	// App and navigation
	App_Name,
	Nav_Workspace,
	Nav_Home,
	Nav_Inbox,
	Nav_Projects,
	Nav_Calendar,
	Nav_Team,
	Nav_Settings,
	Nav_Help,
	Nav_Sign_Out,

	// Toolbar
	Search,
	Search_Placeholder,
	Notifications,
	Language,
	Language_Menu_Title,
	Account,
	Refresh,

	// Common actions
	Save,
	Cancel,
	Delete,
	Edit,
	Share,
	Archive,
	Duplicate,
	Rename,
	Download,
	Upload,
	Export,
	Close,
	Back,
	Next,
	Done,
	More_Options,

	// Home
	Greeting,
	Home_Summary,
	Tasks_Due_Today,
	Unread_Messages,
	Active_Projects,
	Members_Online,
	Recent_Activity,
	View_All,
	Quick_Actions,
	New_Task,
	New_Project,
	Invite_Member,
	Bulk_Edit,

	// Activity
	Activity_Commented,
	Activity_Completed,
	Activity_Created,
	Just_Now,
	Minutes_Ago,
	Hours_Ago,
	Days_Ago,

	// Inbox
	Inbox_Empty,
	Inbox_Empty_Body,
	Mark_All_Read,
	Mark_Read,
	Mark_Unread,
	Reply,
	Forward,
	Filter_All,
	Filter_Unread,
	Filter_Mentions,

	// Projects
	Status_On_Track,
	Status_At_Risk,
	Status_Off_Track,
	Status_Completed,
	Project_Progress,
	Project_Tasks,
	Due_In_Days,
	Project_Owner,
	Sort_By,
	Sort_Name,
	Sort_Due_Date,

	// Calendar
	Today,
	Week,
	Month,
	Events_Scheduled,
	No_Events,
	All_Day,

	// Team
	Invite_By_Email,
	Role_Admin,
	Role_Member,
	Role_Guest,
	Members_Count,
	Last_Active,

	// Settings
	Settings_Profile,
	Settings_Appearance,
	Theme_Light,
	Theme_Dark,
	Theme_System,
	Language_Saved,
	Email_Notifications,
	Storage_Used,
	Files_Count,

	// Feedback
	Confirm_Delete,
	Cannot_Undo,
	Changes_Saved,
	Error_Generic,
	Items_Selected,
}

// SOURCES is each shipped locale's text; a locale without one is not
// offered.
@(rodata)
SOURCES := [i18n.Locale]string {
	.English             = #load("locales/en.txt", string),
	.Spanish             = #load("locales/es.txt", string),
	.French              = #load("locales/fr.txt", string),
	.German              = #load("locales/de.txt", string),
	.Italian             = #load("locales/it.txt", string),
	.Portuguese_Brazil   = #load("locales/pt-BR.txt", string),
	.Dutch               = #load("locales/nl.txt", string),
	.Polish              = #load("locales/pl.txt", string),
	.Russian             = #load("locales/ru.txt", string),
	.Ukrainian           = #load("locales/uk.txt", string),
	.Turkish             = #load("locales/tr.txt", string),
	.Arabic              = #load("locales/ar.txt", string),
	.Hindi               = #load("locales/hi.txt", string),
	.Bengali             = #load("locales/bn.txt", string),
	.Thai                = #load("locales/th.txt", string),
	.Vietnamese          = #load("locales/vi.txt", string),
	.Indonesian          = #load("locales/id.txt", string),
	.Japanese            = #load("locales/ja.txt", string),
	.Korean              = #load("locales/ko.txt", string),
	.Chinese_Simplified  = #load("locales/zh-Hans.txt", string),
	.Chinese_Traditional = #load("locales/zh-Hant.txt", string),
}

// Strings is the text Atlas shows: English, loaded once as the base, and
// the locale in use, whose gaps load fills from it. At most 20 KB, and
// nothing allocated.
Strings :: struct {
	base:   i18n.Table(Msg),
	active: i18n.Table(Msg),
}

#assert(size_of(Strings) <= 20 * 1024)

// init loads English and then locale.
init :: proc(s: ^Strings, locale: i18n.Locale) {
	i18n.load(&s.base, .English, SOURCES[.English])
	use(s, locale)
}

// use puts locale in use; one not shipped falls back to English.
use :: proc(s: ^Strings, locale: i18n.Locale) {
	chosen := shipped(locale) ? locale : .English
	i18n.load(&s.active, chosen, SOURCES[chosen], &s.base)
}

// shipped is whether Atlas has locale's text.
shipped :: proc(locale: i18n.Locale) -> bool {
	return SOURCES[locale] != ""
}

// locale is the locale in use.
locale :: proc(s: ^Strings) -> i18n.Locale {
	return i18n.table_locale(&s.active)
}

// tr is key's text, with no arguments: a string that lives as long as
// the program.
tr :: proc(s: ^Strings, key: Msg) -> string {
	return i18n.text(&s.active, key)
}

// trb is key's text with args filled in, written to buf: for text that
// must outlive the frame. ok is false when it was cut to fit.
trb :: proc(s: ^Strings, buf: []u8, key: Msg, args: ..i18n.Arg) -> (text: string, ok: bool) {
	return i18n.bformat(buf, &s.active, key, ..args)
}

// trf is key's text with args filled in, in allocator: the frame's, in a
// ui proc.
trf :: proc(s: ^Strings, key: Msg, args: ..i18n.Arg, allocator := context.temp_allocator) -> string {
	return i18n.format(&s.active, key, ..args, allocator = allocator)
}
