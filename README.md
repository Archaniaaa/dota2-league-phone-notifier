# Dota 2 / League of Legends Queue Phone Notifier

This Windows notifier watches one signal: after you select a game and arm it, the selected game becomes the foreground application and remains there for a short confirmation period. It then sends one urgent push through [ntfy](https://docs.ntfy.sh/publish/) and disarms. Dota mode watches `dota2.exe`; experimental League mode watches `LeagueClientUx.exe`. It does not read game memory, inject code, inspect traffic, alter game files, send game input, or click **Accept**.

Game State Integration is intentionally not used. GSI normally reports `WAIT_FOR_PLAYERS_TO_LOAD` or `HERO_SELECTION` after the ready-check/Accept stage, which is too late for this job. Process creation, window titles, console logs, and audio recognition are not reliable match-found signals either.

League mode uses the same foreground-only design. Riot does not document queue pop as a guaranteed foreground transition, so League support is experimental: it works only when `LeagueClientUx.exe` actually becomes the Windows foreground process during Ready Check.

## Download and quick start

1. Download `Dota2-League-Phone-Notifier-v1.1.0.zip` from the [latest GitHub release](https://github.com/Archaniaaa/dota2-league-phone-notifier/releases/latest).
2. Extract the ZIP to a normal user-writable folder such as Documents.
3. Install the official ntfy app on the phone.
4. Start Dota 2 or the League client.
5. Double-click `Start-DotaMatchNotifier.cmd` and follow the prompts.
6. On first run, let the script generate a private topic and subscribe to that exact topic in ntfy.
7. Send a test notification before joining a real queue.

Do not run the scripts directly from inside the ZIP. Windows may show a downloaded-file warning because the scripts are open source but not commercially code-signed; review the source and release checksum before running it.

## Prerequisites

- Windows 10 or Windows 11.
- Dota 2 or the League of Legends client running on the PC.
- Windows PowerShell 5.1 or PowerShell 7; no PowerShell modules are required.
- Internet connectivity.
- The official ntfy mobile app on Android or iPhone.
- The PC must remain powered on, awake, online, and logged in.

No administrator privileges, firewall rules, inbound network access, or global execution-policy changes are needed. The only external connection made by the script is an outbound HTTPS publish request to the configured ntfy server.

## Privacy and security

- Each installation generates its own random ntfy topic under `%LOCALAPPDATA%`; no topic is included in this repository.
- Topics and full publish URLs are deliberately omitted from logs.
- The notifier does not collect telemetry or send data anywhere other than the configured ntfy HTTPS endpoint.
- Never share `config.json`, logs, or screenshots that reveal a topic. If a topic is exposed, delete the configuration, generate a new one, and update the phone subscription.

## Phone setup

1. Install the official ntfy mobile app.
2. Run the notifier once. On first setup, accept the offer to generate a secure random topic.
3. Subscribe in the app to the exact topic shown by the script.
4. Allow notification sound and high-priority notifications for ntfy.
5. Exempt ntfy from restrictive battery optimization when necessary.
6. Send and receive a test notification before matchmaking.

A public ntfy topic acts like a secret: anyone who knows it can publish to it or subscribe to it. Do not share it, put it in screenshots, or reuse it elsewhere. After first-run setup, the notifier does not print the full topic in normal output or logs.

The production configuration is saved at:

```text
%LOCALAPPDATA%\DotaMatchNotifier\config.json
```

## Dota setup

In Dota 2, enable:

```text
Settings > Options > Advanced Options >
Bring Dota 2 to front when match found
```

Borderless Window mode is recommended if exclusive fullscreen does not reliably regain focus. Other Dota options that bring the game to the foreground can create false positives; for the cleanest behavior, temporarily disable them, especially foreground behavior for Ready Checks.

## League of Legends setup

Keep the League client open while queuing. League mode watches `LeagueClientUx.exe`; it does not use the unsupported League Client API. No documented Riot setting guarantees that Ready Check takes foreground. If the client only flashes on the taskbar instead of becoming foreground, the notification will not trigger.

Test League mode with a harmless simulated transition first: arm without joining a queue, then manually Alt+Tab into the League client. Only rely on it for a real queue after that test succeeds.

## Usage

### Double-click

Start Dota 2 or the League client, then double-click `Start-DotaMatchNotifier.cmd`. Choose **1** for Dota 2 or **2** for League of Legends each time. The launcher prefers PowerShell 7 (`pwsh.exe`) and falls back to Windows PowerShell. It keeps the console open if the script reports an error.

Follow the prompts: optionally test the phone, start matchmaking, Alt+Tab to the notifier, and press Enter. The notifier verifies that the selected game is not foreground before it displays, for example:

```text
ARMED: Waiting for Dota 2 to become the foreground application.
Do not manually switch back to Dota while armed.
```

The normal mode sends one alert and exits.

### Direct PowerShell invocation

From this directory, with PowerShell 7:

```powershell
pwsh.exe -NoProfile -File .\DotaMatchNotifier.ps1
```

Skip the game-selection prompt with `-Game`:

```powershell
pwsh.exe -NoProfile -File .\DotaMatchNotifier.ps1 -Game Dota2
pwsh.exe -NoProfile -File .\DotaMatchNotifier.ps1 -Game League
```

With Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\DotaMatchNotifier.ps1
```

`-ExecutionPolicy Bypass` applies only to that Windows PowerShell process; it does not alter the machine or user execution policy.

### Modes and overrides

Send a generic test and exit (neither game needs to be running):

```powershell
.\DotaMatchNotifier.ps1 -TestNotification
```

Detect and log without contacting ntfy:

```powershell
.\DotaMatchNotifier.ps1 -Game Dota2 -DryRun
.\DotaMatchNotifier.ps1 -Game League -DryRun
```

Allow multiple cycles in one session:

```powershell
.\DotaMatchNotifier.ps1 -Continuous
```

Continuous mode disarms after every notification. It requires an explicit Enter key press and the complete arming check before it monitors again; it never re-arms merely because the selected game changes focus. The selected game remains fixed for that script session.

Override settings for one run:

```powershell
.\DotaMatchNotifier.ps1 -Topic 'dota-temporary_secret' -PollIntervalMs 250 -ConfirmationDelayMs 750
.\DotaMatchNotifier.ps1 -ConfigPath 'C:\Users\me\my-notifier-config.json'
```

Topics may contain only `A-Z`, `a-z`, `0-9`, `_`, and `-`, with no whitespace, slash, query string, or other punctuation, and ntfy limits them to 64 characters. The server must be an absolute HTTPS URI without embedded credentials, query text, or a fragment. The topic command-line override is not saved.

### Configuration, logs, and uninstall

To change the saved topic or server, edit:

```text
%LOCALAPPDATA%\DotaMatchNotifier\config.json
```

To start over, delete that file and run the notifier again. It will offer to generate a new secret topic. Logs are stored in:

```text
%LOCALAPPDATA%\DotaMatchNotifier\Logs
```

Logs never include the full topic or publish URL. Logs older than 30 days are removed, and only the 50 most recent log files are retained.

To completely uninstall, close the notifier, delete the `DotaMatchNotifier` project folder, and delete `%LOCALAPPDATA%\DotaMatchNotifier`. There are no services, scheduled tasks, registry entries, modules, firewall rules, or game files to remove. You may also unsubscribe from the topic in the phone app.

## Limitations

- The PC, selected game client, notifier, and internet connection must remain active; Windows must not sleep.
- Manually focusing the selected game while armed causes a false positive.
- Other Dota foreground events can cause false positives.
- League support is experimental. Ready Check may flash the taskbar without taking foreground, producing no alert.
- Any unrelated League client foreground transition while League mode is armed causes a false positive.
- Windows can occasionally prevent applications from stealing focus.
- Push delivery can be delayed by internet conditions, phone battery optimization, and Do Not Disturb or Focus modes.
- The notifier does not remotely accept a match or automate gameplay.
- The tool is independent and is not endorsed by Valve.
- No guarantee is made about Valve/VAC or Riot/Vanguard policy. This implementation does not read memory, inject code, inspect network traffic, modify game files, or send input to either game.
- A timeout during publishing can have an uncertain delivery result; bounded retries favor delivering the urgent alert and could rarely produce a duplicate push.

## Troubleshooting

### Dota does not return to foreground

Confirm **Bring Dota 2 to front when match found** is enabled. Try Borderless Window mode, and verify Windows is not blocking focus changes. The notifier cannot force Dota into the foreground; it only observes Windows' foreground window.

### League Ready Check does not trigger

Run `DotaMatchNotifier.ps1 -Game League -DryRun`, arm without joining a queue, and manually Alt+Tab into the League client. If that simulation works but a real Ready Check does not, League is not taking foreground on queue pop. The foreground-only detector cannot fix that; do not rely on League mode on that PC.

### Test push does not arrive

Confirm that the PC is online, the phone is subscribed to the same topic, ntfy is allowed to notify, and `https://ntfy.sh` is reachable. Run `DotaMatchNotifier.ps1 -TestNotification` again. Delivery failure returns exit code `20` after three short attempts.

### Wrong ntfy topic

Delete `%LOCALAPPDATA%\DotaMatchNotifier\config.json`, run the notifier again, and subscribe the phone to the newly generated topic. Alternatively, carefully edit `Topic` in the JSON file. Never add a slash or URL query string to the topic field.

### Windows execution-policy error

Use the CMD launcher, or invoke Windows PowerShell with the process-only option shown above. Do not change the global execution policy. If Windows marked a downloaded copy as blocked, right-click the file, open **Properties**, and select **Unblock**, if that option appears.

### PowerShell cannot load `user32.dll`

Run the script on Windows 10 or 11 in a normal interactive desktop session, not PowerShell remoting, Windows Sandbox without a desktop, or a non-Windows host. Confirm the script is using standard 64-bit or 32-bit Windows PowerShell/PowerShell.

### Phone notification arrives silently

Enable sound and high-priority notifications for ntfy, allow the `video_game` notification category if shown, check the phone's volume, and disable Do Not Disturb/Focus for the test. Exempt ntfy from battery optimization.

### False notification immediately after arming

The selected game was probably still foreground or another foreground event fired. Alt+Tab to the notifier, ensure the game is visibly behind another application, and do not manually switch to the game while armed.

### PC went to sleep

Keep the PC powered and awake for the entire queue. Adjust Windows sleep settings for the session; the notifier does not change power settings itself.

### Corporate proxy or security software blocks `ntfy.sh`

Ask the network administrator whether outbound HTTPS POST requests to `ntfy.sh` are allowed. A custom HTTPS ntfy server can be set in `config.json`, but do not weaken TLS or add credentials to the URI.

## Manual acceptance test

### Dota 2

1. Install and subscribe to ntfy.
2. Start Dota 2.
3. Start the notifier.
4. Send and receive a test notification.
5. Arm the notifier without matchmaking.
6. Manually Alt+Tab into Dota to simulate the foreground transition.
7. Confirm one phone notification arrives.
8. Confirm the script exits after the notification.
9. Restart the notifier.
10. Start a real queue.
11. Alt+Tab away and arm it.
12. Confirm the phone notification arrives when Dota presents the match-found screen.

Do not leave the PC unattended during the initial real-match test. Missing the ready check can cause a matchmaking penalty.

### League of Legends

1. Start the League client.
2. Run the notifier and select League, or use `-Game League`.
3. Send and receive a test notification.
4. Arm the notifier without joining a queue.
5. Manually Alt+Tab into the League client.
6. Confirm one `QUEUE READY` phone notification arrives and the script exits.
7. Restart the notifier with League selected.
8. Join a low-risk queue, Alt+Tab away, and arm it.
9. Confirm the phone notification arrives only if the League Ready Check makes the client foreground.

Do not leave the PC unattended during initial League testing. Missing Ready Check can cause queue restrictions or other penalties.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Completed successfully, including a dry run. |
| `1` | Configuration, validation, or unexpected runtime failure. |
| `2` | First-run configuration was declined. |
| `10` | The selected game process was not running when required. |
| `20` | Notification delivery failed after bounded retries. |
| `130` | Cancelled with Ctrl+C while armed. |

## Technical behavior

The script uses `GetForegroundWindow` and `GetWindowThreadProcessId` from `user32.dll`, then safely resolves the process and compares it with the selected profile (`dota2` or `LeagueClientUx`). It polls every 250 ms by default, waits 750 ms to confirm a candidate transition, publishes UTF-8 text with an eight-second HTTP timeout, and retries temporary delivery failure at most twice. CPU use should remain negligible. The main script is compatible with Windows PowerShell 5.1 and PowerShell 7 and requires no external modules.
