local obs = obslua
local ffi = require("ffi")

ffi.cdef[[
    typedef void* HWND;
    typedef void* HANDLE;
    typedef int BOOL;
    typedef unsigned long DWORD;
    typedef void* LPARAM;
    typedef unsigned int UINT;
    typedef unsigned char uint8_t;
    typedef unsigned int uint32_t;
    typedef long long intptr_t;
    typedef unsigned short WORD;
    typedef unsigned char BYTE;
    typedef unsigned short wchar_t;
	int DwmSetWindowAttribute(HWND hwnd, DWORD dwAttribute, void* pvAttribute, DWORD cbAttribute);
    typedef struct _STARTUPINFOA {
        DWORD cb;
        char* lpReserved;
        char* lpDesktop;
        char* lpTitle;
        DWORD dwX;
        DWORD dwY;
        DWORD dwXSize;
        DWORD dwYSize;
        DWORD dwXCountChars;
        DWORD dwYCountChars;
        DWORD dwFillAttribute;
        DWORD dwFlags;
        WORD wShowWindow;
        WORD cbReserved2;
        BYTE* lpReserved2;
        HANDLE hStdInput;
        HANDLE hStdOutput;
        HANDLE hStdError;
    } STARTUPINFOA;
    typedef struct _PROCESS_INFORMATION {
        HANDLE hProcess;
        HANDLE hThread;
        DWORD dwProcessId;
        DWORD dwThreadId;
    } PROCESS_INFORMATION;
    typedef struct _SECURITY_ATTRIBUTES {
        DWORD nLength;
        void* lpSecurityDescriptor;
        BOOL bInheritHandle;
    } SECURITY_ATTRIBUTES;
    BOOL EnumWindows(void* lpEnumFunc, LPARAM lParam);
    BOOL IsWindowVisible(HWND hWnd);
    BOOL IsIconic(HWND hWnd);
    BOOL ShowWindow(HWND hWnd, int nCmdShow);
    BOOL SetFocus(HWND hWnd);
    BOOL PostMessageA(HWND hWnd, UINT Msg, intptr_t wParam, intptr_t lParam);
    int GetWindowTextW(HWND hWnd, wchar_t* lpString, int nMaxCount);
    int GetClassNameW(HWND hWnd, wchar_t* lpClassName, int nMaxCount);
    DWORD GetWindowThreadProcessId(HWND hWnd, DWORD* lpdwProcessId);
    DWORD GetCurrentProcessId(void);
    void* OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId);
    BOOL QueryFullProcessImageNameA(void* hProcess, DWORD dwFlags, char* lpExeName, DWORD* lpdwSize);
    BOOL CloseHandle(HANDLE hObject);
    void* GetForegroundWindow(void);
    void keybd_event(uint8_t bVk, uint8_t bScan, uint32_t dwFlags, intptr_t dwExtraInfo);
    HANDLE CreateFileA(const char* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, void* lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
    BOOL CreateProcessA(const char* lpApplicationName, char* lpCommandLine, void* lpProcessAttributes, void* lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, void* lpEnvironment, const char* lpCurrentDirectory, STARTUPINFOA* lpStartupInfo, PROCESS_INFORMATION* lpProcessInformation);
    DWORD GetExitCodeProcess(HANDLE hProcess, DWORD* lpExitCode);
    DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds);
    BOOL TerminateProcess(HANDLE hProcess, UINT uExitCode);
    DWORD GetLastError(void);
    unsigned long long GetTickCount64(void);
    int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const wchar_t* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, BOOL* lpUsedDefaultChar);
]]

local dwmapi = ffi.load("dwmapi")
local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")
local MY_PID = tonumber(kernel32.GetCurrentProcessId())
local SW_MINIMIZE = 6
local SW_RESTORE = 9
local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
local VK_MENU = 0x12
local VK_T = 0x54
local VK_DOWN = 0x28
local VK_RETURN = 0x0D
local KEYEVENTF_KEYUP = 0x0002
local WM_CLOSE = 0x0010
local CREATE_NO_WINDOW = 0x08000000
local STARTF_USESTDHANDLES = 0x00000100
local STILL_ACTIVE = 259
local WAIT_TIMEOUT = 0x00000102
local GENERIC_WRITE = 0x40000000
local FILE_SHARE_READ = 0x00000001
local FILE_SHARE_WRITE = 0x00000002
local OPEN_EXISTING = 3
local CP_UTF8 = 65001
local SCRIPTS_RU = "Скрипты"
local SCRIPTS_EN = "Scripts"
local RESET_DELAY_MS = 3000
local DISPLAY_CHECK_DELAY_MS = 500
local NULL_HANDLE = ffi.cast("HANDLE", 0)
local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
local NULL_HWND = ffi.cast("HWND", 0)
local hwaccel_priority = {"cuda", "qsv", "d3d11va", "dxva2",}
local default_loc = nil
local current_loc = nil
local input_file = ""
local crf_value = 26
local use_hw_accel = true
local ffmpeg_exe = ""
local global_settings = nil
local game_source_name = ""
local display_source_name = ""
local window_sources_str = ""
local switcher_enabled = false
local stretch_enabled = false
local toggle_obs_ui_enabled = true
local script_window_enabled = false
local display_check_enabled = false
local active = false
local game_item, display_item = nil, nil
local window_items = {}
local hooked_ok, unhooked_ok = false, false
local resetting = false
local reset_start_time = 0
local last_foreground_hwnd = nil
local pending_visibility_check = false
local is_captured = false
local blacklist = {}
local blacklist_str_val = ""
local blacklist_active = false
local scene_blacklist = {}
local scene_blacklist_str_val = ""
local game_item_hidden_by_script = false
local obs_fully_loaded = false
local initialized = false
local display_check_pending = nil
local script_ui_hotkey_id = obs.OBS_INVALID_HOTKEY_ID
local scene_change_callback = nil
local scene_change_connected = false
local window_sources_data = {}
local scene_sources_signals = {}
local needs_refresh = false
local current_scene_handler = nil
local scene_item_modified_cb = nil
local available_hwaccels = {}
local hwaccels_detected = false
local nul_handle = nil
local comp_state = nil

local function now_ms()
    return tonumber(kernel32.GetTickCount64())
end

local function is_valid_handle(h)
    return h ~= nil and h ~= NULL_HANDLE and h ~= INVALID_HANDLE_VALUE
end

local function is_valid_hwnd(h)
    return h ~= nil and h ~= NULL_HWND
end

local function get_window_title_utf8(hwnd)
    local buf = ffi.new("wchar_t[512]")
    local len = user32.GetWindowTextW(hwnd, buf, 512)
    if len == 0 then return nil end
    local utf8_buf = ffi.new("char[2048]")
    local out_len = kernel32.WideCharToMultiByte(CP_UTF8, 0, buf, len, utf8_buf, 2048, nil, nil)
    if out_len == 0 then return nil end
    return ffi.string(utf8_buf, out_len)
end

local function get_window_class_utf8(hwnd)
    local buf = ffi.new("wchar_t[256]")
    local len = user32.GetClassNameW(hwnd, buf, 256)
    if len == 0 then return nil end
    local utf8_buf = ffi.new("char[1024]")
    local out_len = kernel32.WideCharToMultiByte(CP_UTF8, 0, buf, len, utf8_buf, 1024, nil, nil)
    if out_len == 0 then return nil end
    return ffi.string(utf8_buf, out_len)
end

local function ensure_nul_handle()
    if is_valid_handle(nul_handle) then
        return nul_handle
    end
    local sa = ffi.new("SECURITY_ATTRIBUTES[1]")
    sa[0].nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
    sa[0].lpSecurityDescriptor = nil
    sa[0].bInheritHandle = 1
    local h = kernel32.CreateFileA("NUL", GENERIC_WRITE, ffi.cast("DWORD", FILE_SHARE_READ + FILE_SHARE_WRITE), sa, OPEN_EXISTING, 0, nil)
    if not is_valid_handle(h) then
        return nil
    end
    nul_handle = h
    return nul_handle
end

local function spawn_hidden(cmdline)
    if not cmdline or #cmdline == 0 then
        return nil, nil, "empty cmdline"
    end
    ensure_nul_handle()
    local si = ffi.new("STARTUPINFOA[1]")
    si[0].cb = ffi.sizeof("STARTUPINFOA")
    if nul_handle ~= nil then
        si[0].dwFlags = STARTF_USESTDHANDLES
        si[0].hStdInput = nul_handle
        si[0].hStdOutput = nul_handle
        si[0].hStdError = nul_handle
    end
    local buf = ffi.new("char[?]", #cmdline + 1)
    ffi.copy(buf, cmdline)
    local pi = ffi.new("PROCESS_INFORMATION[1]")
    local inherit = (nul_handle ~= nil) and 1 or 0
    local ok = kernel32.CreateProcessA(nil, buf, nil, nil, inherit, CREATE_NO_WINDOW, nil, nil, si, pi)
    if ok == 0 then
        return nil, nil, kernel32.GetLastError()
    end
    kernel32.CloseHandle(pi[0].hThread)
    return pi[0].hProcess, tonumber(pi[0].dwProcessId), nil
end

local function run_hidden_sync(cmdline, timeout_ms)
    local h, pid, err = spawn_hidden(cmdline)
    if not h then return nil, tostring(err) end
    local wait = kernel32.WaitForSingleObject(h, timeout_ms or 5000)
    local code = nil
    if wait == WAIT_TIMEOUT then
        kernel32.TerminateProcess(h, 1)
        kernel32.WaitForSingleObject(h, 1000)
    else
        local buf = ffi.new("DWORD[1]")
        kernel32.GetExitCodeProcess(h, buf)
        code = tonumber(buf[0])
    end
    kernel32.CloseHandle(h)
    if code == nil then return nil, "timeout" end
    return code, nil
end

local function poll_process(h)
    local buf = ffi.new("DWORD[1]")
    local ok = kernel32.GetExitCodeProcess(h, buf)
    if ok == 0 then return "error", nil end
    local code = tonumber(buf[0])
    if code == STILL_ACTIVE then return "running", nil end
    if code == 0 then return "ok", 0 end
    return "failed", code
end

local function kill_process(h)
    if h then kernel32.TerminateProcess(h, 1) end
end

local function close_process(h)
    if is_valid_handle(h) then kernel32.CloseHandle(h) end
end

local function test_hwaccel_init(name)
    local cmd = '"' .. ffmpeg_exe .. '" -hide_banner -loglevel quiet '
        .. '-init_hw_device ' .. name .. ' '
        .. '-f lavfi -i nullsrc -t 0.1 -f null -'
    local code = run_hidden_sync(cmd, 5000)
    return code == 0
end

local function detect_hwaccels()
    if hwaccels_detected then return end
    hwaccels_detected = true
    available_hwaccels = {}
    for _, name in ipairs(hwaccel_priority) do
        if test_hwaccel_init(name) then
            available_hwaccels[name] = true
        end
    end
end

local function build_ffmpeg_cmd(in_path, out_path, crf, hwaccel)
    local clean_ffmpeg = ffmpeg_exe:gsub("/", "\\")
    local clean_input  = in_path:gsub("/", "\\")
    local clean_output = out_path:gsub("/", "\\")
    local decoder_arg = hwaccel and (" -hwaccel " .. hwaccel) or ""
    return string.format('"%s" -y%s -i "%s" -c:v libx264 -crf %d -preset veryfast -pix_fmt yuv420p -x264-params "bframes=0" -movflags +faststart -c:a copy "%s"', clean_ffmpeg, decoder_arg, clean_input, crf, clean_output)
end

local function finalize_compression_success()
    local st = comp_state
    comp_state = nil
    local clean = st.output_path:gsub("/", "\\")
    spawn_hidden('explorer.exe /select,"' .. clean .. '"')
end

local function finalize_compression_failure()
    comp_state = nil
end

local function launch_attempt(index)
    if not comp_state then return end
    local total = #comp_state.attempts
    if index > total then
        finalize_compression_failure()
        return
    end
    local name = comp_state.attempts[index]
    local hwaccel = (name ~= "__software__") and name or nil
    comp_state.attempt_index = index
    comp_state.current_label = hwaccel or "software"
    local cmd = build_ffmpeg_cmd(comp_state.input_path, comp_state.output_path, comp_state.crf, hwaccel)
    local h, pid = spawn_hidden(cmd)
    if not h then
        launch_attempt(index + 1)
        return
    end
    comp_state.process_handle = h
    comp_state.pid = pid
end

local function start_compression(in_path, crf, hw_enabled)
    if comp_state then return false end
    if in_path == nil or in_path == "" then return false end
    local f = io.open(in_path, "r")
    if not f then return false end
    io.close(f)
    local dir, filename = in_path:match("^(.*[/\\])(.-)$")
    if not dir then dir = ""; filename = in_path end
    local out_path = dir .. "Compressed " .. filename
    local attempts = {}
    if hw_enabled then
        for _, name in ipairs(hwaccel_priority) do
            if available_hwaccels[name] then
                attempts[#attempts + 1] = name
            end
        end
    end
    attempts[#attempts + 1] = "__software__"
    comp_state = {input_path = in_path, output_path = out_path,crf = crf, attempts = attempts, attempt_index = 0, current_label = nil, process_handle = nil, pid = nil}
    launch_attempt(1)
    return true
end

local function getString(key)
    local str = current_loc and obs.obs_data_get_string(current_loc, key) or ""
    if str == "" and default_loc then
        str = obs.obs_data_get_string(default_loc, key)
    end
    return (str ~= "") and str or key
end

local function init_locale()
    if default_loc then return end
    local dir = script_path():match("(.*[/\\])") or ""
    local loc_dir = dir .. "locale/"
    local lang = obs.obs_get_locale()
    default_loc = obs.obs_data_create_from_json_file(loc_dir .. "en-US.json")
    current_loc = obs.obs_data_create_from_json_file(loc_dir .. lang .. ".json") or obs.obs_data_create_from_json_file(loc_dir .. lang:sub(1,2) .. ".json")
end

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

local function compress_file()
    if input_file == "" or input_file == nil then return false end
    if not file_exists(ffmpeg_exe) then return false end
    if comp_state then return false end
    if use_hw_accel then
        detect_hwaccels()
    end
    if start_compression(input_file, crf_value, use_hw_accel) then
        if global_settings ~= nil then
            obs.obs_data_set_string(global_settings, "input_file", "")
        end
        input_file = ""
    end
    return true
end

function script_description()
    init_locale()
    return getString("ScriptDescription")
end

local function get_canvas_size()
    local vi = obs.obs_video_info()
    if not obs.obs_get_video_info(vi) then
        return 1920, 1080
    end
    return vi.base_width, vi.base_height
end

local function get_current_scene()
    local src = obs.obs_frontend_get_current_scene()
    if src == nil then return nil end
    local scene = obs.obs_scene_from_source(src)
    obs.obs_source_release(src)
    return scene
end

local function get_current_scene_name()
    local src = obs.obs_frontend_get_current_scene()
    if src == nil then return nil end
    local name = obs.obs_source_get_name(src)
    obs.obs_source_release(src)
    return name
end

local function is_valid_hotkey(id)
    return id ~= nil and id ~= obs.OBS_INVALID_HOTKEY_ID
end

local function apply_stretch_to_item(item)
    if item == nil then return end
    local canvas_w, canvas_h = get_canvas_size()
    obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_STRETCH)
    local bounds = obs.vec2()
    bounds.x = canvas_w
    bounds.y = canvas_h
    obs.obs_sceneitem_set_bounds(item, bounds)
    obs.obs_sceneitem_set_bounds_alignment(item, 0)
    local pos = obs.vec2()
    pos.x = 0
    pos.y = 0
    obs.obs_sceneitem_set_pos(item, pos)
    local scale = obs.vec2()
    scale.x = 1
    scale.y = 1
    obs.obs_sceneitem_set_scale(item, scale)
    obs.obs_sceneitem_set_rot(item, 0)
end

local function set_visible(item, visible)
    if item == nil then return end
    obs.obs_sceneitem_set_visible(item, visible)
end

local function show_game()
    set_visible(game_item, true)
    set_visible(display_item, false)
    for _, item in pairs(window_items) do
        set_visible(item, false)
    end
end

local function show_display()
    set_visible(game_item, false)
    set_visible(display_item, true)
    for _, item in pairs(window_items) do
        set_visible(item, false)
    end
end

local function show_windows(active_items)
    set_visible(display_item, false)
    for name, item in pairs(window_items) do
        set_visible(item, active_items[name] == true)
    end
end

local function show_both_game_display()
    set_visible(game_item, true)
    set_visible(display_item, true)
    for _, item in pairs(window_items) do
        set_visible(item, false)
    end
end

local function get_process_name_from_hwnd(hwnd)
    if not is_valid_hwnd(hwnd) then return nil end
    local pid = ffi.new("DWORD[1]")
    user32.GetWindowThreadProcessId(hwnd, pid)
    if pid[0] == 0 then return nil end
    local hProcess = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid[0])
    if not is_valid_handle(hProcess) then return nil end
    local EXE_PATH_BUF = 32767
    local exePath = ffi.new("char[?]", EXE_PATH_BUF)
    local dwSize = ffi.new("DWORD[1]", EXE_PATH_BUF)
    local success = kernel32.QueryFullProcessImageNameA(hProcess, 0, exePath, dwSize)
    kernel32.CloseHandle(hProcess)
    if success == 0 then return nil end
    local path = ffi.string(exePath)
    local name = path:match("([^\\]+)$")
    return name and name:lower() or nil
end

local function get_window_source_process(source)
    if not source then return nil end
    local settings = obs.obs_source_get_settings(source)
    if not settings then return nil end
    local window_val = obs.obs_data_get_string(settings, "window")
    obs.obs_data_release(settings)
    if not window_val or window_val == "" then return nil end
    local process = window_val:match(":([^:]+)$")
    if process then
        return process:lower()
    else
        return window_val:lower()
    end
end

local function hide_game_if_visible()
    if not game_item then return end
    if obs.obs_sceneitem_visible(game_item) then
        set_visible(game_item, false)
        game_item_hidden_by_script = true
    end
end

local function show_game_if_hidden_by_script()
    if not game_item then return end
    if game_item_hidden_by_script then
        set_visible(game_item, true)
        game_item_hidden_by_script = false
    end
end

local function apply_visibility_state()
    if not game_item and not display_item and not next(window_items) then
        return
    end
    if resetting then
        if game_item then hide_game_if_visible() end
        if not active then return end
        local current_hwnd = user32.GetForegroundWindow()
        local current_proc = get_process_name_from_hwnd(current_hwnd)
        local matching_windows = {}
        for name, data in pairs(window_sources_data) do
            if data.process and data.process == current_proc then
                matching_windows[name] = true
            end
        end
        if next(matching_windows) then
            set_visible(display_item, false)
            for name, item in pairs(window_items) do
                set_visible(item, matching_windows[name] == true)
            end
            if stretch_enabled then
                for name in pairs(matching_windows) do
                    apply_stretch_to_item(window_items[name])
                end
            end
        else
            set_visible(display_item, display_item ~= nil)
            for _, item in pairs(window_items) do
                set_visible(item, false)
            end
            if stretch_enabled then
                apply_stretch_to_item(display_item)
            end
        end
        return
    end
    local current_hwnd = user32.GetForegroundWindow()
    local current_proc = get_process_name_from_hwnd(current_hwnd)
    local blacklist_hit = false
    if current_proc then
        blacklist_hit = blacklist[current_proc] == true
    end
    if not active then
        if not game_item then return end
        if blacklist_hit then
            if not is_captured then
                hide_game_if_visible()
            end
        else
            show_game_if_hidden_by_script()
        end
        return
    end
    local matching_windows = {}
    for name, data in pairs(window_sources_data) do
        if data.process and data.process == current_proc then
            matching_windows[name] = true
        end
    end
    if blacklist_hit then
        set_visible(game_item, false)
        if next(matching_windows) then
            show_windows(matching_windows)
            if stretch_enabled then
                for name in pairs(matching_windows) do
                    apply_stretch_to_item(window_items[name])
                end
            end
        else
            show_display()
            if stretch_enabled then
                apply_stretch_to_item(display_item)
            end
        end
        return
    end
    if next(matching_windows) then
        if game_item and is_captured then
            show_game()
            if stretch_enabled then
                apply_stretch_to_item(game_item)
            end
        else
            show_windows(matching_windows)
            if stretch_enabled then
                for name in pairs(matching_windows) do
                    apply_stretch_to_item(window_items[name])
                end
            end
        end
        return
    end
    if game_item and is_captured then
        show_game()
        if stretch_enabled then
            apply_stretch_to_item(game_item)
        end
        return
    end
    if game_item and display_item then
        show_both_game_display()
    elseif game_item then
        set_visible(game_item, true)
        set_visible(display_item, false)
        for _, item in pairs(window_items) do
            set_visible(item, false)
        end
        if stretch_enabled then
            apply_stretch_to_item(game_item)
        end
    elseif display_item then
        set_visible(game_item, false)
        set_visible(display_item, true)
        for _, item in pairs(window_items) do
            set_visible(item, false)
        end
        if stretch_enabled then
            apply_stretch_to_item(display_item)
        end
    else
        for _, item in pairs(window_items) do
            set_visible(item, false)
        end
    end
end

local function on_hooked()
    is_captured = true
    if active then
        resetting = false
    end
    if game_item then
        apply_visibility_state()
    end
end

local function on_unhooked()
    is_captured = false
    if active then
        resetting = false
    end
    if game_item then
        apply_visibility_state()
    end
end

local function connect_signals_switcher()
    if game_item == nil then return end
    local source = obs.obs_sceneitem_get_source(game_item)
    if source == nil then return end
    local handler = obs.obs_source_get_signal_handler(source)
    if not handler then return end
    if not hooked_ok then
        hooked_ok = obs.signal_handler_connect(handler, "hooked", on_hooked)
    end
    if not unhooked_ok then
        unhooked_ok = obs.signal_handler_connect(handler, "unhooked", on_unhooked)
    end
end

local function disconnect_signals_switcher()
    if game_item == nil then return end
    local source = obs.obs_sceneitem_get_source(game_item)
    if source == nil then return end
    local handler = obs.obs_source_get_signal_handler(source)
    if not handler then return end
    if hooked_ok then
        obs.signal_handler_disconnect(handler, "hooked", on_hooked)
        hooked_ok = false
    end
    if unhooked_ok then
        obs.signal_handler_disconnect(handler, "unhooked", on_unhooked)
        unhooked_ok = false
    end
end

local function start_reset(force)
    if not game_item then return end
    if not is_captured then return end
    if not force then
        if not active then return end
        if blacklist_active then return end
    end
    if not resetting then
        resetting = true
        reset_start_time = now_ms()
    else
        reset_start_time = now_ms()
    end
    hide_game_if_visible()
end

local function check_reset_timeout()
    if not resetting then return end
    if now_ms() - reset_start_time >= RESET_DELAY_MS then
        resetting = false
        if is_captured then
            is_captured = false
        end
        apply_visibility_state()
    end
end

local function is_obs_main_window(hwnd)
    local class = get_window_class_utf8(hwnd)
    if not class or not class:find("QWindowIcon") then
        return false
    end
    local title = get_window_title_utf8(hwnd)
    if not title or not title:find("OBS") then
        return false
    end
    local pid = ffi.new("DWORD[1]")
    user32.GetWindowThreadProcessId(hwnd, pid)
    return pid[0] == MY_PID
end

local function find_obs_window()
    local found = ffi.new("HWND[1]", nil)
    local callback = ffi.cast("BOOL(__stdcall*)(HWND, LPARAM)", function(hwnd, lparam)
        if is_obs_main_window(hwnd) then
            found[0] = hwnd
            return false
        end
        return true
    end)
    user32.EnumWindows(callback, nil)
    pcall(function() callback:free() end)
    local hwnd = found[0]
    if not is_valid_hwnd(hwnd) then return nil end
    return hwnd
end

local function restore_obs_window(hwnd)
    local cloak = ffi.new("BOOL[1]", 1)
    dwmapi.DwmSetWindowAttribute(hwnd, 13, cloak, ffi.sizeof("BOOL"))
    user32.ShowWindow(hwnd, SW_RESTORE)
	user32.ShowWindow(hwnd, SW_MINIMIZE)
    cloak[0] = 0
    dwmapi.DwmSetWindowAttribute(hwnd, 13, cloak, ffi.sizeof("BOOL"))
end

local function find_scripts_window(obs_hwnd)
    if not is_valid_hwnd(obs_hwnd) then return nil end
    local pid = ffi.new("DWORD[1]")
    user32.GetWindowThreadProcessId(obs_hwnd, pid)
    if pid[0] == 0 then return nil end
    local found = ffi.new("HWND[1]", nil)
    local callback = ffi.cast("BOOL(__stdcall*)(HWND, LPARAM)", function(hwnd, lparam)
        local wnd_pid = ffi.new("DWORD[1]")
        user32.GetWindowThreadProcessId(hwnd, wnd_pid)
        if wnd_pid[0] ~= pid[0] then return true end
        local title = get_window_title_utf8(hwnd)
        if not title then return true end
        if title:find(SCRIPTS_RU, 1, true) or title:find(SCRIPTS_EN, 1, true) then
            found[0] = hwnd
            return false
        end
        return true
    end)
    user32.EnumWindows(callback, nil)
    pcall(function() callback:free() end)
    local hwnd = found[0]
    if not is_valid_hwnd(hwnd) then return nil end
    return hwnd
end

local function press_key(vk)
    user32.keybd_event(vk, 0, 0, 0)
    user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)
end

local function open_scripts_menu()
    local down_presses = 5
    user32.keybd_event(VK_MENU, 0, 0, 0)
    user32.keybd_event(VK_T, 0, 0, 0)
    user32.keybd_event(VK_T, 0, KEYEVENTF_KEYUP, 0)
    user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)
    for i = 1, down_presses do
        press_key(VK_DOWN)
    end
    press_key(VK_RETURN)
end

local function toggle_obs_ui(pressed)
    if not pressed then return end
    if not toggle_obs_ui_enabled then return end
    local obs_hwnd = find_obs_window()
    if not is_valid_hwnd(obs_hwnd) then return end
    local scripts_hwnd = nil
    if script_window_enabled then
        scripts_hwnd = find_scripts_window(obs_hwnd)
    end
    local obs_visible = (user32.IsWindowVisible(obs_hwnd) == 1) and (user32.IsIconic(obs_hwnd) == 0)
    if obs_visible then
        if is_valid_hwnd(scripts_hwnd) then
            user32.PostMessageA(scripts_hwnd, WM_CLOSE, 0, 0)
        end
        user32.ShowWindow(obs_hwnd, SW_MINIMIZE)
    else
        if is_valid_hwnd(scripts_hwnd) then
            user32.PostMessageA(scripts_hwnd, WM_CLOSE, 0, 0)
        end
        restore_obs_window(obs_hwnd)
        user32.SetFocus(obs_hwnd)
        if script_window_enabled then
            open_scripts_menu()
        end
    end
end

local function clear_window_sources_data()
    for source, data in pairs(scene_sources_signals) do
        local handler = obs.obs_source_get_signal_handler(source)
        if handler then
            obs.signal_handler_disconnect(handler, "update", data.cb)
            obs.signal_handler_disconnect(handler, "rename", data.cb)
        end
    end
    scene_sources_signals = {}
    window_sources_data = {}
    window_items = {}
end

local function teardown_active_switcher()
    disconnect_signals_switcher()
    clear_window_sources_data()
    active = false
    resetting = false
    blacklist_active = false
    game_item = nil
    display_item = nil
    game_item_hidden_by_script = false
end

local function on_scene_item_modified(cd)
    if active then
        teardown_active_switcher()
    else
        disconnect_signals_switcher()
    end
    needs_refresh = true
end

local function disconnect_scene_signals()
    if current_scene_handler and scene_item_modified_cb then
        obs.signal_handler_disconnect(current_scene_handler, "item_add", scene_item_modified_cb)
        obs.signal_handler_disconnect(current_scene_handler, "item_remove", scene_item_modified_cb)
        obs.signal_handler_disconnect(current_scene_handler, "rename", scene_item_modified_cb)
    end
    current_scene_handler = nil
    scene_item_modified_cb = nil
end

local function connect_scene_signals(scene)
    disconnect_scene_signals()
    local source = obs.obs_scene_get_source(scene)
    if source then
        current_scene_handler = obs.obs_source_get_signal_handler(source)
        if current_scene_handler then
            scene_item_modified_cb = on_scene_item_modified
            obs.signal_handler_connect(current_scene_handler, "item_add", scene_item_modified_cb)
            obs.signal_handler_connect(current_scene_handler, "item_remove", scene_item_modified_cb)
            obs.signal_handler_connect(current_scene_handler, "rename", scene_item_modified_cb)
        end
    end
end

local function init_switcher_items()
    local scene = get_current_scene()
    if not scene then return false end
    connect_scene_signals(scene)
    if game_source_name ~= "" then
        game_item = obs.obs_scene_find_source(scene, game_source_name)
    else
        game_item = nil
    end
    if not active then
        return game_item ~= nil
    end
    if display_source_name ~= "" then
        display_item = obs.obs_scene_find_source(scene, display_source_name)
    else
        display_item = nil
    end
    clear_window_sources_data()
    local enum_items = obs.obs_scene_enum_items(scene)
    if enum_items then
        for _, item in ipairs(enum_items) do
            local source = obs.obs_sceneitem_get_source(item)
            if source then
                local handler = obs.obs_source_get_signal_handler(source)
                if handler then
                    local cb = function()
                        needs_refresh = true
                    end
                    obs.signal_handler_connect(handler, "update", cb)
                    obs.signal_handler_connect(handler, "rename", cb)
                    scene_sources_signals[source] = { cb = cb }
                end
            end
        end
        obs.sceneitem_list_release(enum_items)
    end
    for name in string.gmatch(window_sources_str, "[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            local item = obs.obs_scene_find_source(scene, trimmed)
            if item then
                local source = obs.obs_sceneitem_get_source(item)
                if source then
                    local proc = get_window_source_process(source)
                    if proc then
                        window_sources_data[trimmed] = {process = proc}
                        window_items[trimmed] = item
                    end
                end
            end
        end
    end
    local window_count = 0
    for _ in pairs(window_sources_data) do window_count = window_count + 1 end
    local valid = (window_count >= 1) or (game_item ~= nil and display_item ~= nil)
    if not valid then
        clear_window_sources_data()
        display_item = nil
        return false
    end
    return true
end

local function update_blacklist(blacklist_str)
    blacklist = {}
    blacklist_str_val = blacklist_str or ""
    if blacklist_str and blacklist_str ~= "" then
        for name in string.gmatch(blacklist_str, "[^,]+") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                blacklist[trimmed:lower()] = true
            end
        end
    end
end

local function update_scene_blacklist(str)
    scene_blacklist = {}
    scene_blacklist_str_val = str or ""
    if str and str ~= "" then
        for name in string.gmatch(str, "[^,]+") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                scene_blacklist[trimmed] = true
            end
        end
    end
end

local function is_current_scene_blacklisted()
    if next(scene_blacklist) == nil then return false end
    local name = get_current_scene_name()
    if not name then return false end
    return scene_blacklist[name] == true
end

local function refresh_switcher()
    if game_item and game_item_hidden_by_script then
        set_visible(game_item, true)
    end
    disconnect_signals_switcher()
    disconnect_scene_signals()
    clear_window_sources_data()
    active = false
    game_item = nil
    display_item = nil
    game_item_hidden_by_script = false
    is_captured = false
    local scene_blacklisted = is_current_scene_blacklisted()
    active = switcher_enabled and not scene_blacklisted
    local ok = init_switcher_items()
    if not ok then
        active = false
    end
    -- Сигналы game_capture подключаем только когда источник найден.
    -- После этого сразу проверяем размеры: если источник захвачен
    -- (w>0 и h>0) — запускаем reset, чтобы гарантированно получить
    -- событие unhooked и знать актуальное состояние. Если 0x0 —
    -- ничего не делаем, источник ничего не захватывает.
    if game_item then
        connect_signals_switcher()
        local source = obs.obs_sceneitem_get_source(game_item)
        if source then
            local w = obs.obs_source_get_width(source)
            local h = obs.obs_source_get_height(source)
            if w > 0 and h > 0 then
                is_captured = true
                start_reset(true)
            else
                is_captured = false
            end
        end
    end
    last_foreground_hwnd = user32.GetForegroundWindow()
    pending_visibility_check = false
    blacklist_active = false
    if last_foreground_hwnd then
        local proc_name = get_process_name_from_hwnd(last_foreground_hwnd)
        if proc_name and blacklist[proc_name] then
            blacklist_active = true
        end
    end
    apply_visibility_state()
end

local function perform_display_check(item, hide_back)
    local source = obs.obs_sceneitem_get_source(item)
    if source == nil then
        if hide_back then obs.obs_sceneitem_set_visible(item, false) end
        return
    end
    local width  = obs.obs_source_get_width(source)
    local height = obs.obs_source_get_height(source)
    if width == 0 or height == 0 then
        if obs.obs_frontend_open_source_properties ~= nil then
            obs.obs_frontend_open_source_properties(source)
        end
    end
    if hide_back then
        obs.obs_sceneitem_set_visible(item, false)
    end
end

local function check_display_source()
    if not display_check_enabled then return end
    if display_source_name == nil or display_source_name == "" then return end
    local scene = get_current_scene()
    if not scene then return end
    local item = obs.obs_scene_find_source(scene, display_source_name)
    if not item then return end
    local was_visible = obs.obs_sceneitem_visible(item)
    if not was_visible then
        obs.obs_sceneitem_set_visible(item, true)
    end
    display_check_pending = {
        item = item,
        start_time = now_ms(),
        restore_hidden = not was_visible,
    }
end

local function tick_display_check()
    if not display_check_pending then return end
    if now_ms() - display_check_pending.start_time < DISPLAY_CHECK_DELAY_MS then return end
    local item = display_check_pending.item
    local source = obs.obs_sceneitem_get_source(item)
    if source == nil then
        display_check_pending = nil
        return
    end
    local width = obs.obs_source_get_width(source)
    local height = obs.obs_source_get_height(source)
    local restore_hidden = display_check_pending.restore_hidden
    display_check_pending = nil
    if width == 0 or height == 0 then
        if obs.obs_frontend_open_source_properties ~= nil then
            obs.obs_frontend_open_source_properties(source)
        end
    end
    if restore_hidden then
        obs.obs_sceneitem_set_visible(item, false)
    end
end

local function on_scene_changed(event, data)
    if event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        obs_fully_loaded = true
        if not initialized then
            initialized = true
            refresh_switcher()
            check_display_source()
        end
    elseif event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        if initialized then
            refresh_switcher()
            check_display_source()
        end
    end
end

function script_tick(seconds)
    tick_display_check()
    if comp_state and comp_state.process_handle then
        local status = poll_process(comp_state.process_handle)
        if status ~= "running" then
            close_process(comp_state.process_handle)
            comp_state.process_handle = nil
            if status == "ok" then
                finalize_compression_success()
            else
                launch_attempt(comp_state.attempt_index + 1)
            end
        end
    end
    if not obs_fully_loaded then
        return
    end
    if not initialized then
        initialized = true
        refresh_switcher()
        check_display_source()
        return
    end
    if needs_refresh then
        needs_refresh = false
        refresh_switcher()
    end
    if not active and not game_item then return end
    local current_hwnd = user32.GetForegroundWindow()
    if current_hwnd ~= last_foreground_hwnd then
        pending_visibility_check = true
    end
    if pending_visibility_check then
        local proc_name = nil
        local proc_unknown = false
        if is_valid_hwnd(current_hwnd) then
            proc_name = get_process_name_from_hwnd(current_hwnd)
            if proc_name == nil then
                proc_unknown = true
            end
        end
        if not proc_unknown then
            pending_visibility_check = false
            last_foreground_hwnd = current_hwnd
            local new_blacklist_active = (proc_name and blacklist[proc_name] == true) or false
            if new_blacklist_active ~= blacklist_active then
                blacklist_active = new_blacklist_active
            end
            if active and game_item and not blacklist_active and is_captured then
                start_reset()
            end
            apply_visibility_state()
        end
    end
    check_reset_timeout()
end

function script_load(settings)
    init_locale()
    local script_dir = script_path():match("(.*[/\\])") or ""
    ffmpeg_exe = script_dir .. "ffmpeg.exe"
    if settings then
        game_source_name = obs.obs_data_get_string(settings, "game_source") or ""
        display_source_name = obs.obs_data_get_string(settings, "display_source") or ""
        window_sources_str = obs.obs_data_get_string(settings, "window_sources") or ""
        switcher_enabled = obs.obs_data_get_bool(settings, "switcher_enabled")
        stretch_enabled = obs.obs_data_get_bool(settings, "stretch_enabled")
        toggle_obs_ui_enabled = obs.obs_data_get_bool(settings, "toggle_obs_ui_enabled")
        script_window_enabled = obs.obs_data_get_bool(settings, "script_window_enabled")
        display_check_enabled = obs.obs_data_get_bool(settings, "display_check_enabled")
        use_hw_accel = obs.obs_data_get_bool(settings, "use_hw_accel")
        update_blacklist(obs.obs_data_get_string(settings, "blacklist"))
        update_scene_blacklist(obs.obs_data_get_string(settings, "scene_blacklist"))
        input_file = obs.obs_data_get_string(settings, "input_file")
        if obs.obs_data_has_user_value(settings, "crf_value") then
            crf_value = obs.obs_data_get_int(settings, "crf_value")
        end
    end
    script_ui_hotkey_id = obs.obs_hotkey_register_frontend("toggle_obs_ui", getString("HotkeyToggleOBSUI"), toggle_obs_ui)
    if settings and is_valid_hotkey(script_ui_hotkey_id) then
        local arr = obs.obs_data_get_array(settings, "toggle_obs_ui")
        if arr then
            obs.obs_hotkey_load(script_ui_hotkey_id, arr)
            obs.obs_data_array_release(arr)
        end
    end
    initialized = false
    local probe_scene = obs.obs_frontend_get_current_scene()
    if probe_scene then
        obs.obs_source_release(probe_scene)
        obs_fully_loaded = true
    else
        obs_fully_loaded = false
    end
    if not scene_change_connected then
        scene_change_callback = on_scene_changed
        obs.obs_frontend_add_event_callback(scene_change_callback)
        scene_change_connected = true
    end
end

function script_save(settings)
    obs.obs_data_set_string(settings, "game_source", game_source_name)
    obs.obs_data_set_string(settings, "display_source", display_source_name)
    obs.obs_data_set_string(settings, "window_sources", window_sources_str)
    obs.obs_data_set_bool(settings, "switcher_enabled", switcher_enabled)
    obs.obs_data_set_bool(settings, "stretch_enabled", stretch_enabled)
    obs.obs_data_set_bool(settings, "toggle_obs_ui_enabled", toggle_obs_ui_enabled)
    obs.obs_data_set_bool(settings, "script_window_enabled", script_window_enabled)
    obs.obs_data_set_bool(settings, "display_check_enabled", display_check_enabled)
    obs.obs_data_set_bool(settings, "use_hw_accel", use_hw_accel)
    obs.obs_data_set_int(settings, "crf_value", crf_value)
    obs.obs_data_set_string(settings, "blacklist", blacklist_str_val)
    obs.obs_data_set_string(settings, "scene_blacklist", scene_blacklist_str_val)
    if is_valid_hotkey(script_ui_hotkey_id) then
        local arr = obs.obs_hotkey_save(script_ui_hotkey_id)
        obs.obs_data_set_array(settings, "toggle_obs_ui", arr)
        obs.obs_data_array_release(arr)
    end
end

function script_update(settings)
    if not settings then return end
    if global_settings then
        obs.obs_data_release(global_settings)
        global_settings = nil
    end
    global_settings = settings
    obs.obs_data_addref(global_settings)
    input_file = obs.obs_data_get_string(settings, "input_file")
    if obs.obs_data_has_user_value(settings, "crf_value") then
        crf_value = obs.obs_data_get_int(settings, "crf_value")
    end
    use_hw_accel = obs.obs_data_get_bool(settings, "use_hw_accel")
    local new_game_name = obs.obs_data_get_string(settings, "game_source") or ""
    local new_display_name = obs.obs_data_get_string(settings, "display_source") or ""
    local new_window_sources = obs.obs_data_get_string(settings, "window_sources") or ""
    local new_blacklist_str = obs.obs_data_get_string(settings, "blacklist") or ""
    local new_scene_blacklist_str = obs.obs_data_get_string(settings, "scene_blacklist") or ""
    local new_switcher = obs.obs_data_get_bool(settings, "switcher_enabled")
    local new_stretch = obs.obs_data_get_bool(settings, "stretch_enabled")
    local new_toggle_ui = obs.obs_data_get_bool(settings, "toggle_obs_ui_enabled")
    local new_script_win = obs.obs_data_get_bool(settings, "script_window_enabled")
    local new_display_check = obs.obs_data_get_bool(settings, "display_check_enabled")
    local needs_heavy_reinit = false
    if new_game_name ~= game_source_name then
        game_source_name = new_game_name
        needs_heavy_reinit = true
    end
    if new_display_name ~= display_source_name then
        display_source_name = new_display_name
        needs_heavy_reinit = true
    end
    if new_window_sources ~= window_sources_str then
        window_sources_str = new_window_sources
        needs_heavy_reinit = true
    end
    if new_blacklist_str ~= blacklist_str_val then
        update_blacklist(new_blacklist_str)
        needs_heavy_reinit = true
    end
    if new_scene_blacklist_str ~= scene_blacklist_str_val then
        update_scene_blacklist(new_scene_blacklist_str)
        needs_heavy_reinit = true
    end
    if new_switcher ~= switcher_enabled then
        switcher_enabled = new_switcher
        needs_heavy_reinit = true
    end
    if new_stretch ~= stretch_enabled then
        stretch_enabled = new_stretch
        needs_heavy_reinit = true
    end
    if new_toggle_ui ~= toggle_obs_ui_enabled then
        toggle_obs_ui_enabled = new_toggle_ui
    end
    if new_script_win ~= script_window_enabled then
        script_window_enabled = new_script_win
    end
    if new_display_check ~= display_check_enabled then
        display_check_enabled = new_display_check
    end
    if needs_heavy_reinit and initialized then
        refresh_switcher()
    end
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "crf_value", 26)
    obs.obs_data_set_default_bool(settings, "use_hw_accel", true)
    obs.obs_data_set_default_bool(settings, "switcher_enabled", false)
    obs.obs_data_set_default_bool(settings, "stretch_enabled", false)
    obs.obs_data_set_default_bool(settings, "toggle_obs_ui_enabled", true)
    obs.obs_data_set_default_bool(settings, "script_window_enabled", false)
    obs.obs_data_set_default_bool(settings, "display_check_enabled", false)
end

function script_unload()
    if comp_state and comp_state.process_handle then
        kill_process(comp_state.process_handle)
        close_process(comp_state.process_handle)
        comp_state.process_handle = nil
    end
    comp_state = nil
    if is_valid_handle(nul_handle) then
        close_process(nul_handle)
    end
    nul_handle = nil
    disconnect_scene_signals()
    disconnect_signals_switcher()
    clear_window_sources_data()
    active = false
    game_item = nil
    display_item = nil
    if scene_change_connected and scene_change_callback then
        obs.obs_frontend_remove_event_callback(scene_change_callback)
        scene_change_connected = false
        scene_change_callback = nil
    end
    if global_settings then
        obs.obs_data_release(global_settings)
        global_settings = nil
    end
    if default_loc then obs.obs_data_release(default_loc) default_loc = nil end
    if current_loc then obs.obs_data_release(current_loc) current_loc = nil end
end

function script_properties()
    init_locale()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_text(props, "script_description_text", getString("ScriptDescription"), obs.OBS_TEXT_INFO)
    local g_switcher_toggles = obs.obs_properties_create()
    obs.obs_properties_add_bool(g_switcher_toggles, "switcher_enabled", getString("SwitcherEnabled"))
    obs.obs_properties_add_bool(g_switcher_toggles, "stretch_enabled", getString("StretchEnabled"))
    obs.obs_properties_add_bool(g_switcher_toggles, "display_check_enabled", getString("DisplayCheckEnabled"))
    obs.obs_properties_add_group(props, "group_switcher_toggles", getString("GroupSwitcherManagement"), obs.OBS_GROUP_NORMAL, g_switcher_toggles)
    local g_switcher = obs.obs_properties_create()
    obs.obs_properties_add_text(g_switcher, "display_source", getString("DisplaySource"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(g_switcher, "game_source", getString("GameSource"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(g_switcher, "window_sources", getString("WindowSources"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(g_switcher, "blacklist", getString("Blacklist"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(g_switcher, "scene_blacklist", getString("SceneBlacklist"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_group(props, "group_switcher", getString("GroupSwitcherSettings"), obs.OBS_GROUP_NORMAL, g_switcher)
    local g_hotkeys = obs.obs_properties_create()
    obs.obs_properties_add_bool(g_hotkeys, "toggle_obs_ui_enabled", getString("ToggleOBSUIEnabled"))
    obs.obs_properties_add_bool(g_hotkeys, "script_window_enabled", getString("ScriptWindowEnabled"))
    obs.obs_properties_add_group(props, "group_hotkeys", getString("GroupHotkeys"), obs.OBS_GROUP_NORMAL, g_hotkeys)
    local g_compress = obs.obs_properties_create()
    obs.obs_properties_add_path(g_compress, "input_file", getString("InputFile"), obs.OBS_PATH_FILE, getString("VideoFilesFilter"), nil)
    obs.obs_properties_add_int_slider(g_compress, "crf_value", getString("CRFValue"), 0, 51, 1)
    obs.obs_properties_add_bool(g_compress, "use_hw_accel", getString("UseHWDecoding"))
    obs.obs_properties_add_button(g_compress, "compress_button", getString("CompressButton"), function(properties, property) return compress_file() end)
    obs.obs_properties_add_group(props, "group_compress", getString("GroupCompress"), obs.OBS_GROUP_NORMAL, g_compress)
    return props
end