## TechKit script catalog (macos)

Run with: bash "__TECHKIT__/macos/<script>" [args]
Refer to a tool by its Name (in the analysis, wrap it in **double asterisks** to make it clickable). Full details: __CATALOG__.

- System Report (system_report.sh) — Model/chip/serial, macOS version, Rosetta, uptime, memory+swap pressure, storage summary, battery, reboot history. Use for: first look at any Mac; need specs/serial; general health check.
- Disk Health (disk_health.sh) — SMART status, APFS container usage, snapshot count; --verify runs live read-only volume check. Use for: slow Mac; disk full mysteries; suspected drive failure. | args: --verify
- Resource Usage (top_processes.sh) — Top CPU/memory processes, memory pressure, swap, hung (I/O-stuck) processes, thermal throttling. Use for: Mac is slow; fans loud; beachballs. | args: top_n
- Startup Programs (startup_items.sh) — Third-party LaunchDaemons/Agents with target binaries, login items, BTM dump, running non-Apple jobs, cron. Use for: slow login; popups; suspected adware/persistence.
- Network Diagnostics (network_diagnostics.sh) — Layered check: interfaces, gateway, internet by IP, DNS, captive-portal/HTTP, DNS config, proxy, Wi-Fi, VPN tunnels. Use for: no internet; Wi-Fi connected but nothing loads; only some sites work.
- Connectivity Test (test_connectivity.sh) — Targeted host test: DNS (system + direct), ping, TCP port via nc, optional traceroute. Use for: can't reach a specific server/printer/share. | args: host* port --trace
- Crash & Log Summary (log_summary.sh) — Crash/hang/panic reports (7d) with per-app frequency, unified-log errors by source, shutdown causes. Use for: app keeps crashing; Mac restarted by itself; kernel panic. | args: hours
- Collect Logs (collect_logs.sh) — Bundle crash reports + unified-log errors + install/system/wifi log tails into tar.gz on USB; sudo adds .logarchive. Use for: take evidence away; escalate with attachments; gather data for the AI to analyze. | args: hours
- Update Status (update_status.sh) — Version/build, update history, auto-update settings; --check queries Apple for pending updates. Use for: is this Mac up to date; update stuck or failing. | args: --check
- Security Check (security_status.sh) — SIP, Gatekeeper, FileVault, firewall, XProtect versions, admin users, SSH/screen/file sharing, 3rd-party extensions. Use for: security check; suspected malware; before handing the Mac back.
- User Accounts (user_account_report.sh) — Local users (uid>=500) with admin flag and last login, logged-in users, home sizes (--sizes), hidden/disabled markers. Use for: account audit; before user cleanup; who uses this Mac. | args: --sizes
- Remove Inactive Users (remove_inactive_users.sh) [DESTRUCTIVE-dry-runs-first,needs-admin] — Disable (default) or delete local users with no login in N days. Dry-run unless --force (sudo). Admin accounts are NEVER touched (no override). Also protects the current user. Use for: clean up shared Mac accounts; remove departed-user accounts. | args: days --delete --remove-home --include-unknown --exclude --force
- Find Large Files (find_large_files.sh) — Largest files (Spotlight-accelerated), folder sizes, known hogs (iOS backups, Xcode, Docker, Trash, snapshots). Use for: disk full; what is using the space. | args: path min_size_mb
- Clean Caches (clear_caches.sh) [DESTRUCTIVE-dry-runs-first] — Clean user caches, 30d+ old logs, saved app state, optional Trash. Dry-run unless --force. Use for: free space safely; weird app behavior possibly cache-related. | args: --force --trash
- Battery Health (battery_health.sh) — Cycle count, condition, capacity vs design from system_profiler + ioreg, charger info. Skips desktops. Use for: MacBook battery complaints; random shutdowns on battery.
- Full Triage Snapshot (triage_snapshot.sh) — Runs all read-only diagnostics + raw extras (ifconfig, ps, system_profiler), saves+tars to USB collections. Use for: unknown problem - collect everything; intermittent issue; gather evidence for AI analysis. | args: out_dir
