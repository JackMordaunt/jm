/*
Package view is Atlas's ui: a navigation drawer, a top bar with search,
notifications and the language menu behind a globe, and six pages of a
small project-management app. Every word it shows comes from package msg
in the locale in use; the people, projects and messages are the user's
own content and stay as written.

Choosing a language puts it in use at once and hands it to on_language,
which the host saves, so the next start opens in it.
*/
package i18n_view

import "jm:i18n"
import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../msg"

Page :: enum u8 {
	Home,
	Inbox,
	Projects,
	Calendar,
	Team,
	Settings,
}

// PAGE_IDS is each page's value in the drawer: stable whatever the
// language, unlike its label.
@(rodata)
PAGE_IDS := [Page]string {
	.Home     = "home",
	.Inbox    = "inbox",
	.Projects = "projects",
	.Calendar = "calendar",
	.Team     = "team",
	.Settings = "settings",
}

@(rodata)
PAGE_TITLES := [Page]msg.Msg {
	.Home     = .Nav_Home,
	.Inbox    = .Nav_Inbox,
	.Projects = .Nav_Projects,
	.Calendar = .Nav_Calendar,
	.Team     = .Nav_Team,
	.Settings = .Nav_Settings,
}

@(rodata)
PAGE_ICONS := [Page]fluent.Icon {
	.Home     = .Home,
	.Inbox    = .Mail,
	.Projects = .Folder,
	.Calendar = .Calendar,
	.Team     = .Person,
	.Settings = .Settings,
}

Inbox_Filter :: enum u8 {
	All,
	Unread,
	Mentions,
}

Span :: enum u8 {
	Today,
	Week,
	Month,
}

Theme :: enum u8 {
	Light,
	Dark,
	System,
}

Model :: struct {
	strings:        msg.Strings,
	page:           Page,
	language_open:  bool, // the top bar's language menu
	settings_open:  bool, // the settings page's language menu
	toasts:         fluent.Toasts,
	notes:          [2][256]u8, // toast bodies, which must outlive their toast: each new one takes the other
	note_turn:      int,
	selected:       int, // bulk edit's count
	filter:         Inbox_Filter,
	read:           [len(INBOX)]bool,
	by_due_date:    bool,
	span:           Span,
	theme:          int, // a Theme, as radio_group keeps it
	email:          bool,
	search:         ui.Text_State,
	scheme:         fluent.Scheme,
	fonts:          fluent.Fonts,
	on_language:    proc(user: rawptr, locale: i18n.Locale),
	user:           rawptr,
}

// model_init readies m in locale, saving a change of language through
// on_language.
model_init :: proc(m: ^Model, locale: i18n.Locale, fonts: fluent.Fonts, on_language: proc(user: rawptr, locale: i18n.Locale) = nil, user: rawptr = nil) {
	msg.init(&m.strings, locale)
	m.fonts = fonts
	m.on_language = on_language
	m.user = user
	m.email = true
	m.selected = 3
	m.read = {false, false, true, true}
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.search)
	fluent.toasts_destroy(&m.toasts)
}

// notify floats a toast saying title, with body filled from key and
// args into the next of m.notes, so it lasts as long as the toast.
notify :: proc(m: ^Model, title: msg.Msg, key: msg.Msg, args: ..i18n.Arg) {
	fluent.toast_dismiss_all(&m.toasts)
	m.note_turn = (m.note_turn + 1) % len(m.notes)
	body, _ := msg.trb(&m.strings, m.notes[m.note_turn][:], key, ..args)
	fluent.toast_push(&m.toasts, tr(m, title), body, .Success)
}

// choose_language puts locale in use and has it saved.
choose_language :: proc(m: ^Model, locale: i18n.Locale) {
	msg.use(&m.strings, locale)
	if m.on_language != nil {
		m.on_language(m.user, locale)
	}
	notify(m, .Changes_Saved, .Language_Saved, i18n.locale_name(locale))
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	dark := Theme(m.theme) == .Dark
	m.scheme = fluent.theme_scheme(dark ? .Web_Dark : .Web_Light)
	fluent.use(&m.scheme, dark ? .Dark : .Light)
	fluent.use_fonts(m.fonts)
	window := gtx.constraints.max
	ops.fill(gtx.scene, ops.Rect{0, 0, window.x, window.y}, m.scheme[.Neutral_Background2])
	page(gtx, m)
	fluent.toaster(gtx, &m.toasts, window, pause_on_hover = true)
}

// page is the drawer, the top bar and the page in use.
page :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.row(gtx, align = .Fill)
	nav(gtx, m)
	ui.flexible(gtx, 1)
	ui.column(gtx, align = .Fill)
	top_bar(gtx, m)
	ui.flexible(gtx, 1)
	ui.scope(gtx, int(m.page))
	ui.scroll_box(gtx)
	ui.inset(gtx, {24, 8, 24, 32})
	ui.column(gtx, gap = 16, align = .Fill)
	switch m.page {
	case .Home:
		page_home(gtx, m)
	case .Inbox:
		page_inbox(gtx, m)
	case .Projects:
		page_projects(gtx, m)
	case .Calendar:
		page_calendar(gtx, m)
	case .Team:
		page_team(gtx, m)
	case .Settings:
		page_settings(gtx, m)
	}
}

// tr is key's text in the locale in use.
tr :: proc(m: ^Model, key: msg.Msg) -> string {
	return msg.tr(&m.strings, key)
}

// trf is key's text with args, in the frame's allocator.
trf :: proc(gtx: ^ui.Ctx, m: ^Model, key: msg.Msg, args: ..i18n.Arg) -> string {
	return msg.trf(&m.strings, key, ..args, allocator = gtx.allocator)
}

// count is value alone in the locale's digits.
count :: proc(gtx: ^ui.Ctx, m: ^Model, value: int) -> string {
	return i18n.number(msg.locale(&m.strings), value, gtx.allocator)
}

// --- chrome -----------------------------------------------------------------

nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fluent.nav(gtx)
	if fluent.nav_header(gtx) {
		fluent.app_item(gtx, tr(m, .App_Name), .Grid, static = true)
	}
	if fluent.nav_body(gtx) {
		fluent.nav_section_header(gtx, tr(m, .Nav_Workspace))
		selected := PAGE_IDS[m.page]
		for page in Page {
			if fluent.nav_item(gtx, tr(m, PAGE_TITLES[page]), PAGE_IDS[page], &selected, PAGE_ICONS[page], key = u64(page)) {
				m.page = page
			}
		}
	}
	if fluent.nav_footer(gtx) {
		none := ""
		fluent.nav_item(gtx, tr(m, .Nav_Help), "help", &none, .Question_Circle)
		fluent.nav_item(gtx, tr(m, .Nav_Sign_Out), "sign-out", &none, .Arrow_Left)
	}
}

top_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.inset(gtx, {24, 12, 16, 8})
	ui.row(gtx, align = .Center, gap = 8)
	fluent.text_preset(gtx, tr(m, PAGE_TITLES[m.page]), .Title3, fluent.color(.Neutral_Foreground1))
	ui.fill_space(gtx)
	fluent.input(gtx, &m.search, tr(m, .Search_Placeholder), before = .Search, width = 280, name = tr(m, .Search))
	fluent.button(gtx, "", .Subtle, .Alert, name = tr(m, .Notifications))
	language_menu(gtx, m, &m.language_open)
	fluent.avatar(gtx, "Maya Patel", .S32, color = .Colorful)
}

// language_menu is the globe: a button naming the language in use that
// opens the list of the languages Atlas ships, each in its own name with
// its English name beside it.
language_menu :: proc(gtx: ^ui.Ctx, m: ^Model, open: ^bool, key: u64 = 0) {
	current := msg.locale(&m.strings)
	ui.stack(gtx, key = key)
	fluent.menu_button(gtx, i18n.locale_name(current), open, .Subtle, .Globe, name = tr(m, .Language), key = key)
	if fluent.menu(gtx, open, key = key) {
		fluent.menu_header(gtx, tr(m, .Language_Menu_Title))
		for locale in i18n.Locale {
			if !msg.shipped(locale) {
				continue
			}
			checked := locale == current
			if fluent.menu_item(gtx, i18n.locale_name(locale), secondary = i18n.locale_english(locale), check = .Radio, checked = &checked, key = u64(locale) + 1) {
				choose_language(m, locale)
			}
		}
	}
}

// --- pages ------------------------------------------------------------------

Activity :: struct {
	kind:    msg.Msg,
	person:  string,
	subject: string,
	ago:     msg.Msg,
	amount:  int,
}

@(rodata)
ACTIVITY := [?]Activity {
	{.Activity_Commented, "Priya Shah", "Q4 roadmap", .Minutes_Ago, 5},
	{.Activity_Completed, "Tomás García", "Launch checklist", .Hours_Ago, 2},
	{.Activity_Created, "Wei Chen", "Design review", .Days_Ago, 3},
	{.Activity_Completed, "Amara Okafor", "Billing migration", .Days_Ago, 21},
}

// PRESETS are counts that between them reach every plural form some
// shipped language has (view_test pins it).
@(rodata)
PRESETS := [?]int{0, 1, 2, 3, 5, 11, 21, 102, 1_000_000}

page_home :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	fluent.text_preset(gtx, trf(gtx, m, .Greeting, "Maya"), .Title2, fg1)
	fluent.text_preset(gtx, tr(m, .Home_Summary), .Body1, fg2)
	if ui.wrap(gtx, gap = 12) {
		stat(gtx, m, .Tasks_Due_Today, 4, .Checkmark_Circle)
		stat(gtx, m, .Unread_Messages, 12, .Mail)
		stat(gtx, m, .Active_Projects, 1, .Folder)
		stat(gtx, m, .Members_Online, 2, .Person)
	}
	if fluent.card(gtx, .Filled, key = 1) {
		ui.column(gtx, gap = 12, align = .Fill, key = 1)
		fluent.text_preset(gtx, tr(m, .Quick_Actions), .Subtitle2, fg1)
		if ui.wrap(gtx, gap = 8) {
			fluent.button(gtx, tr(m, .New_Task), .Primary, .Add)
			fluent.button(gtx, tr(m, .New_Project), .Secondary, .Folder)
			fluent.button(gtx, tr(m, .Invite_Member), .Secondary, .Person)
		}
	}
	if fluent.card(gtx, .Filled, key = 2) {
		ui.column(gtx, gap = 12, align = .Fill, key = 2)
		fluent.text_preset(gtx, tr(m, .Bulk_Edit), .Subtitle2, fg1)
		if ui.row(gtx, gap = 8, align = .Center) {
			if fluent.button(gtx, "", .Secondary, .Subtract, name = "-") {
				m.selected = max(m.selected - 1, 0)
			}
			fluent.text_preset(gtx, trf(gtx, m, .Items_Selected, m.selected), .Body1_Strong, fg1)
			if fluent.button(gtx, "", .Secondary, .Add, name = "+") {
				m.selected += 1
			}
		}
		if ui.wrap(gtx, gap = 4) {
			for preset, ii in PRESETS {
				if fluent.button(gtx, count(gtx, m, preset), .Outline, size = .Small, key = u64(ii)) {
					m.selected = preset
				}
			}
		}
		if ui.wrap(gtx, gap = 8) {
			state := m.selected == 0 ? fluent.Interaction.Disabled : .Live
			fluent.button(gtx, tr(m, .Archive), .Secondary, .Folder, state = state)
			fluent.button(gtx, tr(m, .Export), .Secondary, .Open, state = state)
			fluent.button(gtx, tr(m, .Delete), .Secondary, .Delete, state = state)
		}
	}
	if fluent.card(gtx, .Filled, key = 3) {
		ui.column(gtx, gap = 12, align = .Fill, key = 3)
		if ui.row(gtx, align = .Center) {
			fluent.text_preset(gtx, tr(m, .Recent_Activity), .Subtitle2, fg1)
			ui.fill_space(gtx)
			fluent.button(gtx, tr(m, .View_All), .Transparent, size = .Small)
		}
		for entry, ii in ACTIVITY {
			if ui.row(gtx, gap = 12, align = .Center, key = u64(ii)) {
				fluent.avatar(gtx, entry.person, .S32, color = .Colorful, key = u64(ii))
				if ui.column(gtx, gap = 2, key = u64(ii)) {
					fluent.text_preset(gtx, trf(gtx, m, entry.kind, entry.person, entry.subject), .Body1, fg1, key = u64(ii))
					fluent.text_preset(gtx, trf(gtx, m, entry.ago, entry.amount), .Caption1, fg2, key = u64(ii))
				}
			}
		}
	}
}

// stat is a card with one count in a sentence of its own.
stat :: proc(gtx: ^ui.Ctx, m: ^Model, key: msg.Msg, value: int, ic: fluent.Icon) {
	if fluent.card(gtx, .Filled, key = u64(key)) {
		if ui.sized(gtx, {min = {200, 0}, max = {ui.INF, ui.INF}}, key = u64(key)) {
			if ui.row(gtx, gap = 8, align = .Center, key = u64(key)) {
				fluent.badge(gtx, "", .Brand, .Tint, .Extra_Large, .Rounded, ic, key = u64(key))
				fluent.text_preset(gtx, trf(gtx, m, key, value), .Body1_Strong, fluent.color(.Neutral_Foreground1), key = u64(key))
			}
		}
	}
}

Inbox_Message :: struct {
	from:    string,
	subject: string,
	minutes: int,
	mention: bool,
}

@(rodata)
INBOX := [?]Inbox_Message {
	{"Priya Shah", "Q4 roadmap: comments on milestones", 4, true},
	{"Wei Chen", "Design review moved to Thursday", 38, false},
	{"Tomás García", "Launch checklist is complete", 185, false},
	{"Amara Okafor", "Billing migration status", 2900, true},
}

page_inbox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	if ui.row(gtx, gap = 8, align = .Center) {
		FILTERS :: [Inbox_Filter]msg.Msg {
			.All      = .Filter_All,
			.Unread   = .Filter_Unread,
			.Mentions = .Filter_Mentions,
		}
		for label, filter in FILTERS {
			if fluent.button(gtx, tr(m, label), m.filter == filter ? .Primary : .Subtle, key = u64(filter)) {
				m.filter = filter
			}
		}
		ui.fill_space(gtx)
		if fluent.button(gtx, tr(m, .Mark_All_Read), .Secondary, .Checkmark) {
			m.read = true
		}
	}
	shown := 0
	for message, ii in INBOX {
		if (m.filter == .Unread && m.read[ii]) || (m.filter == .Mentions && !message.mention) {
			continue
		}
		shown += 1
		if fluent.card(gtx, .Filled, key = u64(ii)) {
			if ui.row(gtx, gap = 12, align = .Center, key = u64(ii)) {
				fluent.avatar(gtx, message.from, .S40, color = .Colorful, key = u64(ii))
				if ui.column(gtx, gap = 2, key = u64(ii)) {
					fluent.text_preset(gtx, message.from, m.read[ii] ? .Body1 : .Body1_Strong, fg1, key = u64(ii))
					fluent.text_preset(gtx, message.subject, .Body1, fg1, key = u64(ii))
					fluent.text_preset(gtx, ago(gtx, m, message.minutes), .Caption1, fg2, key = u64(ii))
				}
				ui.fill_space(gtx)
				fluent.button(gtx, tr(m, .Reply), .Subtle, .Send, key = u64(ii))
				fluent.button(gtx, tr(m, .Forward), .Subtle, .Arrow_Right, key = u64(ii))
				toggle := m.read[ii] ? msg.Msg.Mark_Unread : .Mark_Read
				if fluent.button(gtx, tr(m, toggle), .Subtle, key = u64(ii)) {
					m.read[ii] = !m.read[ii]
				}
			}
		}
	}
	if shown == 0 {
		fluent.text_preset(gtx, tr(m, .Inbox_Empty), .Subtitle1, fg1)
		fluent.text_preset(gtx, tr(m, .Inbox_Empty_Body), .Body1, fg2)
	}
}

// ago is how long ago minutes was, in the largest whole unit: a message
// of its own, which another message can carry as an argument.
ago :: proc(gtx: ^ui.Ctx, m: ^Model, minutes: int) -> string {
	switch {
	case minutes < 1:
		return tr(m, .Just_Now)
	case minutes < 60:
		return trf(gtx, m, .Minutes_Ago, minutes)
	case minutes < 24 * 60:
		return trf(gtx, m, .Hours_Ago, minutes / 60)
	}
	return trf(gtx, m, .Days_Ago, minutes / (24 * 60))
}

Status :: enum u8 {
	On_Track,
	At_Risk,
	Off_Track,
	Completed,
}

Project :: struct {
	name:     string,
	owner:    string,
	status:   Status,
	progress: int,
	tasks:    int,
	due_days: int,
}

@(rodata)
PROJECTS := [?]Project {
	{"Q4 roadmap", "Priya Shah", .On_Track, 64, 23, 12},
	{"Billing migration", "Amara Okafor", .At_Risk, 38, 41, 5},
	{"Mobile redesign", "Wei Chen", .Off_Track, 12, 2, 1},
	{"Launch checklist", "Tomás García", .Completed, 100, 1, 0},
}

page_projects :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	if ui.row(gtx, gap = 8, align = .Center) {
		fluent.text_preset(gtx, tr(m, .Sort_By), .Body1, fg2)
		if fluent.button(gtx, tr(m, .Sort_Name), !m.by_due_date ? .Primary : .Subtle, key = 1) {
			m.by_due_date = false
		}
		if fluent.button(gtx, tr(m, .Sort_Due_Date), m.by_due_date ? .Primary : .Subtle, key = 2) {
			m.by_due_date = true
		}
		ui.fill_space(gtx)
		fluent.button(gtx, tr(m, .New_Project), .Primary, .Add)
	}
	order := [len(PROJECTS)]int{0, 1, 2, 3}
	if m.by_due_date {
		order = {3, 2, 1, 0}
	} else {
		order = {1, 3, 2, 0}
	}
	STATUS := [Status]struct {
		label: msg.Msg,
		color: fluent.Badge_Color,
	} {
		.On_Track  = {.Status_On_Track, .Success},
		.At_Risk   = {.Status_At_Risk, .Warning},
		.Off_Track = {.Status_Off_Track, .Danger},
		.Completed = {.Status_Completed, .Informative},
	}
	for index in order {
		project := PROJECTS[index]
		if fluent.card(gtx, .Filled, key = u64(index)) {
			ui.column(gtx, gap = 12, align = .Fill, key = u64(index))
			if ui.row(gtx, gap = 8, align = .Center, key = u64(index)) {
				fluent.text_preset(gtx, project.name, .Subtitle2, fg1, key = u64(index))
				status := STATUS[project.status]
				fluent.badge(gtx, tr(m, status.label), status.color, .Tint, key = u64(index))
				ui.fill_space(gtx)
				fluent.button(gtx, tr(m, .Edit), .Subtle, .Edit, key = u64(index))
				fluent.button(gtx, tr(m, .Share), .Subtle, .Share, key = u64(index))
				fluent.button(gtx, "", .Subtle, .More_Horizontal, name = tr(m, .More_Options), key = u64(index))
			}
			if ui.wrap(gtx, gap = 16, key = u64(index)) {
				fluent.text_preset(gtx, trf(gtx, m, .Project_Progress, project.progress), .Body1, fg1, key = u64(index))
				fluent.text_preset(gtx, trf(gtx, m, .Project_Tasks, project.tasks), .Body1, fg2, key = u64(index))
				if project.status != .Completed {
					fluent.text_preset(gtx, trf(gtx, m, .Due_In_Days, project.due_days), .Body1, fg2, key = u64(index))
				}
				fluent.text_preset(gtx, trf(gtx, m, .Project_Owner, project.owner), .Body1, fg2, key = u64(index))
			}
		}
	}
}

Event :: struct {
	title:   string,
	time:    string,
	all_day: bool,
	span:    Span,
}

@(rodata)
EVENTS := [?]Event {
	{"Team stand-up", "09:30", false, .Today},
	{"Design review", "14:00", false, .Week},
	{"Quarterly planning", "", true, .Week},
	{"Billing migration cut-over", "22:00", false, .Week},
	{"Company offsite", "", true, .Month},
}

page_calendar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	if ui.row(gtx, gap = 8, align = .Center) {
		SPANS :: [Span]msg.Msg {
			.Today = .Today,
			.Week  = .Week,
			.Month = .Month,
		}
		for label, span in SPANS {
			if fluent.button(gtx, tr(m, label), m.span == span ? .Primary : .Subtle, key = u64(span)) {
				m.span = span
			}
		}
	}
	scheduled := 0
	for event in EVENTS {
		if event.span <= m.span {
			scheduled += 1
		}
	}
	if scheduled == 0 {
		fluent.text_preset(gtx, tr(m, .No_Events), .Body1, fg2)
		return
	}
	fluent.text_preset(gtx, trf(gtx, m, .Events_Scheduled, scheduled), .Subtitle2, fg1)
	for event, ii in EVENTS {
		if event.span > m.span {
			continue
		}
		if fluent.card(gtx, .Filled, key = u64(ii)) {
			if ui.row(gtx, gap = 16, align = .Center, key = u64(ii)) {
				if ui.sized(gtx, {min = {72, 0}, max = {72, ui.INF}}, key = u64(ii)) {
					fluent.text_preset(gtx, event.all_day ? tr(m, .All_Day) : event.time, .Body1_Strong, fg1, key = u64(ii))
				}
				fluent.text_preset(gtx, event.title, .Body1, fg1, key = u64(ii))
			}
		}
	}
}

Member :: struct {
	name:    string,
	role:    msg.Msg,
	minutes: int,
}

@(rodata)
MEMBERS := [?]Member {
	{"Maya Patel", .Role_Admin, 0},
	{"Priya Shah", .Role_Admin, 4},
	{"Wei Chen", .Role_Member, 130},
	{"Tomás García", .Role_Member, 1500},
	{"Amara Okafor", .Role_Member, 45},
	{"Jonas Berg", .Role_Guest, 8700},
}

page_team :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	if ui.row(gtx, gap = 8, align = .Center) {
		fluent.text_preset(gtx, trf(gtx, m, .Members_Count, len(MEMBERS)), .Subtitle2, fg1)
		ui.fill_space(gtx)
		fluent.button(gtx, tr(m, .Invite_By_Email), .Primary, .Mail)
	}
	for member, ii in MEMBERS {
		if fluent.card(gtx, .Filled, key = u64(ii)) {
			if ui.row(gtx, gap = 12, align = .Center, key = u64(ii)) {
				fluent.avatar(gtx, member.name, .S40, color = .Colorful, key = u64(ii))
				if ui.column(gtx, gap = 2, key = u64(ii)) {
					fluent.text_preset(gtx, member.name, .Body1_Strong, fg1, key = u64(ii))
					// A message carrying another as its argument.
					fluent.text_preset(gtx, trf(gtx, m, .Last_Active, ago(gtx, m, member.minutes)), .Caption1, fg2, key = u64(ii))
				}
				ui.fill_space(gtx)
				fluent.badge(gtx, tr(m, member.role), member.role == .Role_Admin ? .Brand : .Subtle, .Tint, key = u64(ii))
			}
		}
	}
}

page_settings :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fg1, fg2 := fluent.color(.Neutral_Foreground1), fluent.color(.Neutral_Foreground2)
	if fluent.card(gtx, .Filled, key = 1) {
		ui.column(gtx, gap = 12, align = .Fill, key = 1)
		fluent.text_preset(gtx, tr(m, .Settings_Profile), .Subtitle2, fg1)
		if ui.row(gtx, gap = 12, align = .Center) {
			fluent.avatar(gtx, "Maya Patel", .S48, color = .Colorful)
			fluent.text_preset(gtx, "Maya Patel", .Body1_Strong, fg1)
		}
	}
	if fluent.card(gtx, .Filled, key = 2) {
		ui.column(gtx, gap = 12, align = .Fill, key = 2)
		fluent.text_preset(gtx, tr(m, .Language), .Subtitle2, fg1)
		language_menu(gtx, m, &m.settings_open, key = 1)
	}
	if fluent.card(gtx, .Filled, key = 3) {
		ui.column(gtx, gap = 12, align = .Fill, key = 3)
		fluent.text_preset(gtx, tr(m, .Settings_Appearance), .Subtitle2, fg1)
		themes := [3]string{tr(m, .Theme_Light), tr(m, .Theme_Dark), tr(m, .Theme_System)}
		fluent.radio_group(gtx, themes[:], &m.theme)
	}
	if fluent.card(gtx, .Filled, key = 4) {
		ui.column(gtx, gap = 12, align = .Fill, key = 4)
		fluent.text_preset(gtx, tr(m, .Notifications), .Subtitle2, fg1)
		fluent.checkbox(gtx, &m.email, tr(m, .Email_Notifications))
		fluent.text_preset(gtx, trf(gtx, m, .Storage_Used, 1_536, 2_048), .Body1, fg2)
		fluent.text_preset(gtx, trf(gtx, m, .Files_Count, 1_234_567), .Body1, fg2)
	}
	if ui.row(gtx, gap = 8) {
		if fluent.button(gtx, tr(m, .Save), .Primary, .Save) {
			fluent.toast_dismiss_all(&m.toasts)
			fluent.toast_push(&m.toasts, tr(m, .Changes_Saved), intent = .Success)
		}
		fluent.button(gtx, tr(m, .Cancel), .Secondary)
	}
}
