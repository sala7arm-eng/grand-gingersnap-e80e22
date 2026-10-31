# The Hunt v3.8.1 — Download and Map Reliability Build

This is a static browser game build for desktop and mobile. It includes the existing game pages, account flow, lobby, profile, friend requests, map and match UI from the prior build, with map-tile fallback and clearer deployment instructions.

## Install / deploy
1. Download and extract this ZIP using Windows File Explorer (right-click → Extract All).
2. Open `config.js` in Notepad. Set `supabaseUrl` to your project's root URL, for example `https://YOUR_PROJECT_REF.supabase.co`.
3. Set `supabaseAnonKey` to your Supabase **Publishable key** (`sb_publishable_...`) or legacy **anon** key. Never use a secret or service-role key in browser code.
4. Save the file. Upload the *contents* of the extracted folder to Netlify so `index.html` is at the published root. Do not upload this ZIP into Supabase SQL Editor.
5. After Netlify deploys, open the site and hard-refresh with `Ctrl+Shift+R`.
6. Test with two separate accounts/devices and allow location permission when prompted.

## Database
If the existing schema/migrations already ran successfully, do not rerun them just for this frontend update. SQL files are scripts: open a specific `.sql` file, copy its contents into Supabase SQL Editor, and run only if needed.

## Map
The map attempts Esri World Street Map tiles first and switches to OpenStreetMap tiles if the primary layer errors. Satellite imagery is an optional Esri layer. If both providers are blocked by the network, tiles may still be unavailable; this cannot be diagnosed solely by checking the ZIP. Provider availability, browser extensions, firewall and network access can affect tile loading.

## Validation performed
JavaScript syntax checks (`node --check`) and ZIP integrity test were run for this package. These checks do not validate live Supabase credentials, database policies, Realtime, geolocation permissions, or actual tile delivery on your network. Online multiplayer should be tested with at least two accounts before relying on it.


## v3.8.2 repair notes
- Street map now defaults to OpenStreetMap rather than Esri street tiles, which can show grey/blank tiles in some areas. Satellite imagery remains available as an optional layer.
- Map tile failures now show a status warning after repeated errors.
- Match leaderboard refreshes on runner_catches changes as well as catch-code changes, so eliminations should appear promptly.
- The IN WORK / TO BE CONTINUED footer is retained only on home.html.
- Location sharing and Supabase multiplayer still require a live test with the configured project and at least two accounts; code edits alone cannot verify cloud permissions.


## v3.8.3 — Zombies mode
- Adds a Zombies mode choice when creating a lobby and shortcut links on the home page.
- Zombies lobbies use the existing hunter role internally but label that team “Zombie”. When a zombie submits a runner's five-digit code, the runner changes teams and receives a new code to infect others.
- IMPORTANT: run `zombies-mode-migration.sql` in Supabase SQL Editor before deploying this build. Test with multiple accounts first. The internal role uses the existing hunter value to avoid breaking current role constraints.


## v3.8.4 background update
- Added Moonlit Canopy and Ember Grove to Settings > Background & colours.
- Themes save to this device and are applied across pages via the existing theme preference.
- The IN WORK / TO BE CONTINUED footer is intended to appear on home.html only.
- Radio tracks in this build are generated with Web Audio synthesis; they are not recordings of real instruments.


## v3.8.5 — lobby privacy and seasonal themes
- Zombies create-lobby route now opens a focused form with only lobby name and code name, plus Open/Private segmented access control.
- Open lobbies appear in the open-lobby list without exposing their codes. Private lobbies are excluded from the list and require a code to join.
- Classic create flow retains its game-mode selector and also supports Open/Private.
- Added Haunted Halloween and Zombie Outbreak themes in Settings → Background & colours.
- Run `lobby-privacy-migration.sql` in Supabase SQL Editor after the existing migrations before creating lobbies with the new access control.

## v3.8.6 lobby selection/search changes
- Removed the selectable game-mode dropdown from the create-lobby page. The Classic create button opens the Classic lobby flow; the dedicated Zombies button opens `create-lobby.html?mode=zombies`, where mode is locked to Zombies.
- Removed Open/Private toggles from the join/search page for both modes.
- Lobby search now filters by lobby code only and only queries public/open waiting lobbies. Zombies search is additionally restricted to Zombies mode.
- The separate Join by code form allows players to enter a code for a private lobby.
- The create page retains the Open/Private access switch; it sends `p_is_public` to the Supabase RPC so the choice is saved on creation. This depends on `lobby-privacy-migration.sql` having been run successfully.
- Checked app-online.js JavaScript syntax. Live access-control enforcement must still be verified in Supabase with separate host/joiner accounts.
