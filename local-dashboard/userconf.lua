local webview = require("webview")

-- Define username, password, delay, and refresh from environment variables
local username = os.getenv("HA_USERNAME")
local password = os.getenv("HA_PASSWORD")
local login_delay = tonumber(os.getenv("LOGIN_DELAY")) or 2  -- Default to 2 seconds
local start_url = os.getenv("START_URL") or "http://localhost:8123"
local browser_refresh = tonumber(os.getenv("BROWSER_REFRESH")) or 600  -- Default to 600 seconds

-- Check for required environment variables
if not username or not password then
    print("Error: HA_USERNAME and HA_PASSWORD environment variables must be set")
    os.exit(1)
end

-- Convert delays to milliseconds
local delay_ms = login_delay * 1000
if not delay_ms or delay_ms < 0 then
    print("Error: LOGIN_DELAY must be a non-negative number (in seconds)")
    os.exit(1)
end
local refresh_ms = browser_refresh * 1000
if not refresh_ms or refresh_ms < 0 then
    print("Error: BROWSER_REFRESH must be a non-negative number (in seconds)")
    os.exit(1)
end

local window = require("window")
window.add_signal("init", function(w)
    w.win.fullscreen = true
end)

webview.add_signal("init", function(view)
    -- Auto-login and refresh on every page load
    view:add_signal("load-status", function(v, status)
        if status == "finished" then
            -- Auto-login on auth page
            if v.uri:match("^" .. start_url .. "/auth/authorize%?response_type=code") then
                v:eval_js([[
                    setTimeout(function() {
                        var userField = document.querySelector('input[name="username"]');
                        var passField = document.querySelector('input[name="password"]');
                        var submitBtn = document.querySelector('mwc-button');
                        if (userField && passField && submitBtn) {
                            userField.value = "";
                            userField.dispatchEvent(new Event('input', { bubbles: true }));
                            userField.value = "]] .. username .. [[";
                            userField.dispatchEvent(new Event('input', { bubbles: true }));
                            passField.value = "";
                            passField.dispatchEvent(new Event('input', { bubbles: true }));
                            passField.value = "]] .. password .. [[";
                            passField.dispatchEvent(new Event('input', { bubbles: true }));
                            submitBtn.click();
                        }
                    }, ]] .. delay_ms .. [[);
                ]], { source = "auto_login.js" })
            end

            -- Periodic refresh of current page if refresh_ms > 0
            if refresh_ms > 0 then
                v:eval_js([[
                    // Clear any existing interval to avoid duplicates
                    if (window.refreshInterval) clearInterval(window.refreshInterval);
                    window.refreshInterval = setInterval(function() {
                        location.reload();
                    }, ]] .. refresh_ms .. [[);
                ]], { source = "auto_refresh.js" })
            end
        end
    end)
end)
