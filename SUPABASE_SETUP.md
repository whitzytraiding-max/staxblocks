# STAX online leaderboard + friends — Supabase setup

Pure HTTPS from Godot (no native plugin), so iOS + Android share ONE leaderboard.

## 1. Create the project
1. Go to https://supabase.com → new project (free tier is fine). Pick a region near your players.
2. Once it's up, open **Project Settings → API** and copy:
   - **Project URL** (e.g. `https://abcdxyz.supabase.co`)
   - **anon public** key (the long one labelled `anon` / `public` — safe to ship in the app)

## 2. Paste the keys into the app
In `scripts/Net.gd`, set:
```gdscript
const SUPABASE_URL      := "https://abcdxyz.supabase.co"   # your Project URL
const SUPABASE_ANON_KEY := "eyJhbGci..."                    # your anon public key
```
Until these are filled in, the game runs exactly as before (all network calls no-op).

## 3. Run the SQL
Open **SQL Editor → New query**, paste the whole block below, Run.

```sql
-- ── Tables ──────────────────────────────────────────────────────────────────
create table if not exists public.players (
  id          uuid primary key,
  friend_code text unique not null,
  name        text not null default 'PLAYER',
  best_score  int  not null default 0,
  level       int  not null default 1,
  updated_at  timestamptz not null default now()
);

create table if not exists public.friendships (
  player_id  uuid not null references public.players(id) on delete cascade,
  friend_id  uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (player_id, friend_id)
);

create index if not exists idx_players_best on public.players (best_score desc);

-- ── Lock the tables: no direct access. Everything goes through the functions ──
alter table public.players      enable row level security;
alter table public.friendships  enable row level security;
-- (RLS on with no policies = the anon key cannot read/write tables directly)

-- ── Functions (SECURITY DEFINER: run as owner, bypass RLS in a controlled way) ─

-- Upsert the caller's row; keeps the higher score. Creates the row on first call.
create or replace function public.submit_score(
  p_id uuid, p_code text, p_name text, p_score int, p_level int)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into players (id, friend_code, name, best_score, level, updated_at)
  values (p_id, p_code, left(p_name, 12), greatest(p_score, 0), p_level, now())
  on conflict (id) do update
    set name       = left(excluded.name, 12),
        best_score = greatest(players.best_score, excluded.best_score),
        level      = excluded.level,
        updated_at = now();
end; $$;

-- Top N globally. Returns NO ids/codes, so clients can't grief other players.
create or replace function public.get_global_board(p_limit int default 50)
returns table(rank int, name text, best_score int, level int)
language sql security definer set search_path = public as $$
  select (row_number() over (order by best_score desc, updated_at asc))::int,
         name, best_score, level
  from players
  order by best_score desc, updated_at asc
  limit greatest(1, least(p_limit, 1000));
$$;

-- The caller's global rank (1-based).
create or replace function public.get_my_rank(p_id uuid)
returns int language sql security definer set search_path = public as $$
  select count(*)::int + 1 from players
  where best_score > coalesce((select best_score from players where id = p_id), 0);
$$;

-- Add a friend by their code (one-way: you see people you add). Returns their name.
create or replace function public.add_friend_by_code(p_id uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare fid uuid; fname text;
begin
  select id, name into fid, fname from players where friend_code = upper(p_code);
  if fid is null or fid = p_id then return null; end if;
  insert into friendships (player_id, friend_id) values (p_id, fid)
    on conflict do nothing;
  return fname;
end; $$;

-- Friends leaderboard (your friends + you), sorted. is_me flags your own row.
create or replace function public.get_friends_board(p_id uuid)
returns table(rank int, name text, best_score int, level int, is_me boolean)
language sql security definer set search_path = public as $$
  with f as (
    select friend_id as id from friendships where player_id = p_id
    union select p_id
  )
  select (row_number() over (order by p.best_score desc, p.updated_at asc))::int,
         p.name, p.best_score, p.level, (p.id = p_id)
  from players p join f on f.id = p.id
  order by p.best_score desc, p.updated_at asc;
$$;

-- ── Let the public anon role call ONLY these functions ──────────────────────
grant execute on function public.submit_score(uuid,text,text,int,int) to anon;
grant execute on function public.get_global_board(int)                 to anon;
grant execute on function public.get_my_rank(uuid)                     to anon;
grant execute on function public.add_friend_by_code(uuid,text)         to anon;
grant execute on function public.get_friends_board(uuid)               to anon;
```

## 4. Test
- Launch STAX on two devices (or wipe the save between runs). Each generates a UUID +
  friend code and pushes a row up on launch / game over.
- In **Table Editor → players** you should see rows appear with names + best scores.
- Friends UI (add-by-code + friends board) is the next build step in-app.

## Notes / limitations (v1)
- **Identity is anonymous** (device UUID in the save). Wiping the app loses the account.
  Optional "sign in to back up" can come later.
- **Scores are client-submitted** → a determined user can inflate their OWN score. The
  functions never expose other players' ids, so you can't tamper with anyone else.
  Fine for a casual game; server-validated runs would be a much bigger lift.
- **Store requirements before shipping social:** a privacy policy, plus a name filter +
  a "report" path (Apple requires UGC moderation for anything social).

---

# Account-based cloud save (Sign in with Apple / Google)

Makes progress survive uninstall / a new phone. **Optional & deferred** — players still play as a
guest; signing in backs up + restores. Uses Supabase Auth via an OAuth web flow (no native SDK
plugin). The durable `player_id` is stored on the account, so the leaderboard/friends row is
reclaimed automatically on reinstall.

## A. Run the SQL (SQL Editor → New query → paste → Run)

```sql
-- One profile per authenticated user. Stores the durable player_id (so the
-- leaderboard/friends row is reclaimed) + a JSONB progress snapshot.
create table if not exists public.profiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  player_id   uuid not null,
  friend_code text,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;
create policy "own profile" on public.profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- First sign-in on a device: if this account has no profile, create it and LINK
-- the device's current (guest) player_id + snapshot — claiming existing progress.
-- If a profile already exists, return it (reinstall / new device → restore).
create or replace function public.link_or_get_profile(
  p_player_id uuid, p_friend_code text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row public.profiles%rowtype; v_existed boolean;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_row from public.profiles where user_id = v_uid;
  if found then
    v_existed := true;
    -- Restoring on a new install: the device's fresh guest id is being abandoned in
    -- favour of the account's durable id. Delete the guest's leaderboard row so it
    -- doesn't linger as a duplicate (also blocks smurfing via reinstall). Its score
    -- was already merged into the account client-side + re-submitted under the durable id.
    if p_player_id is not null and p_player_id <> v_row.player_id then
      delete from public.players where id = p_player_id;
    end if;
  else
    insert into public.profiles (user_id, player_id, friend_code, data)
    values (v_uid, p_player_id, p_friend_code, coalesce(p_data, '{}'::jsonb))
    returning * into v_row;
    v_existed := false;
  end if;
  return jsonb_build_object('player_id', v_row.player_id, 'friend_code', v_row.friend_code,
                            'data', v_row.data, 'existed', v_existed);
end; $$;

-- Push the merged snapshot up (client merges field-wise max before calling).
create or replace function public.push_profile(p_data jsonb, p_friend_code text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  update public.profiles
     set data = coalesce(p_data, data),
         friend_code = coalesce(p_friend_code, friend_code),
         updated_at = now()
   where user_id = v_uid;
end; $$;

-- Pull the latest snapshot (launch refresh).
create or replace function public.get_profile()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row public.profiles%rowtype;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_row from public.profiles where user_id = v_uid;
  if not found then return null; end if;
  return jsonb_build_object('player_id', v_row.player_id, 'friend_code', v_row.friend_code,
                            'data', v_row.data, 'existed', true);
end; $$;

-- These require a signed-in user (auth.uid()), so grant to authenticated (NOT anon).
grant execute on function public.link_or_get_profile(uuid,text,jsonb) to authenticated;
grant execute on function public.push_profile(jsonb,text)             to authenticated;
grant execute on function public.get_profile()                        to authenticated;
```

## B. Allow the app's redirect (Dashboard → Authentication → URL Configuration)
- Add **`stax://auth`** to **Redirect URLs** (the allow-list). Leave Site URL as-is.

## C. Google provider (Dashboard → Authentication → Providers → Google)
1. **Google Cloud Console** → APIs & Services → Credentials → *Create OAuth client ID* → **Web
   application**.
   - Authorized redirect URI: `https://dftjbfjgyzpfznsfezpa.supabase.co/auth/v1/callback`
   - (Fill the OAuth consent screen first if prompted — app name, support email, logo.)
2. Copy the **Client ID** + **Client secret** → paste into Supabase's Google provider → Enable.

## D. Apple provider (Dashboard → Authentication → Providers → Apple)
1. **Apple Developer** → Certificates, IDs & Profiles:
   - Your **App ID** → enable the **Sign in with Apple** capability.
   - Create a **Services ID** (this string is the *Client ID*). Configure it: Return URL =
     `https://dftjbfjgyzpfznsfezpa.supabase.co/auth/v1/callback`, domain = `dftjbfjgyzpfznsfezpa.supabase.co`.
   - Create a **Sign in with Apple key** (.p8) → note the **Key ID** + your **Team ID**.
2. In Supabase's Apple provider: paste the **Services ID** (client id), **Team ID**, **Key ID**, and
   the **.p8 key** contents (Supabase generates the client secret from these) → Enable.

> Friend / build side: register the **`stax://`** URL scheme so the redirect reopens the app —
> iOS `Info.plist` `CFBundleURLTypes`, Android `<intent-filter>` (VIEW + BROWSABLE, scheme `stax`).
> Also add the **Sign in with Apple** capability in Xcode. (The client code + exact values come in
> the next build step.)

## E. Code page for the test build (no deep-link plugin needed)
Godot can't catch the `stax://` redirect without a native plugin, so the test build sends the
browser to a tiny page that **shows the sign-in code** to copy-paste into STAX. Host this once:
1. Save the HTML below as `index.html`, drag the folder onto **Netlify Drop** (app.netlify.com/drop).
   You get a URL like `https://stax-auth.netlify.app`.
2. Put that URL in **two** places: `scripts/Auth.gd` → `const AUTH_REDIRECT`, **and** Supabase
   Authentication → URL Configuration → **Redirect URLs** allow-list.

```html
<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="background:#0a0814;color:#fff;font-family:sans-serif;text-align:center;padding:40px">
<h2>STAX sign-in</h2>
<p>Copy this code and paste it back in the app:</p>
<input id="c" readonly style="font-size:20px;padding:12px;width:90%;text-align:center"
       onclick="this.select()">
<p><button onclick="navigator.clipboard.writeText(document.getElementById('c').value)"
   style="font-size:18px;padding:12px 24px;margin-top:12px">Copy code</button></p>
<script>
  var code = new URLSearchParams(location.search).get('code') || '(no code — try again)';
  document.getElementById('c').value = code;
</script>
</body>
```

## F. Test the SQL now (before any client code)
- After running section A, **Table Editor → profiles** should exist (empty).
- Providers verify once C/D are filled: Dashboard → Authentication → Providers shows them enabled.
- End-to-end: friend builds the app (with `AUTH_REDIRECT` set) → tap Sign in → browser → copy code →
  paste in STAX → `profiles` row appears; delete app, reinstall, sign in → progress restored.
