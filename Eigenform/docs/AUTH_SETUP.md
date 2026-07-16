# Auth setup checklist

The app's auth code is complete and builds without a backend — until
`Auth/SupabaseConfig.swift` has real values, the sign-in wall shows setup
instructions instead of a form. Work through this list once to light it up.

## 1. Create the Supabase project

1. Sign in at [supabase.com](https://supabase.com) and create a new project
   (free tier is fine). Pick a strong database password and store it in a
   password manager; the app never uses it.
2. Open **Project Settings → API** and copy two values into
   `Eigenform/Auth/SupabaseConfig.swift`:
   - **Project URL** → `projectURL`
   - **anon / public key** → `anonKey`

   The anon key is safe to commit — it only grants what Row Level Security
   and auth policies allow. Never put the `service_role` key in the app.

## 2. Auth settings (dashboard → Authentication)

### Sign In / Providers → Email

- **Enable email provider**: on
- **Confirm email**: on (the app is built for this — signup shows a
  "check your email" screen until the address is verified)
- **Secure email change**: on (default; the app's copy tells users to
  confirm from both inboxes)
- **Minimum password length**: 8 (matches the app's client-side rule)
- If your plan offers it, enable **leaked password protection**
  (blocks passwords found in known breaches)

### URL Configuration

- Add to **Redirect URLs**:
  - `eigenform://auth-callback`
  - `eigenform://auth-callback?flow=recovery`

  Every OAuth callback and email link redirects here; iOS routes the
  `eigenform://` scheme to the app (declared in `Eigenform/Info.plist`).

## 3. Sign in with Apple

The app uses the native flow: the Apple button produces an identity token
(bound to a nonce) that Supabase verifies directly.

1. You need a paid Apple Developer account. In Xcode, automatic signing will
   register the Sign in with Apple capability for the App ID the first time
   you build to a device (the entitlement is already in
   `Eigenform/Eigenform.entitlements`).
2. In Supabase **Authentication → Sign In / Providers → Apple**:
   - Enable the provider.
   - Add the app's bundle ID `com.kevinhuang.eigenform` to
     **Authorized Client IDs**. (Client secret is only needed for web
     flows — not for native `signInWithIdToken`.)

## 4. Sign in with Google

Runs through Supabase's OAuth flow in an in-app web sheet, so only a web
OAuth client is needed:

1. In [Google Cloud Console](https://console.cloud.google.com), create a
   project (or reuse one) → **APIs & Services → Credentials → Create
   Credentials → OAuth client ID**, type **Web application**.
   - Add authorized redirect URI:
     `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`
   - Configure the OAuth consent screen (app name, support email) if
     prompted.
2. In Supabase **Authentication → Sign In / Providers → Google**: enable it
   and paste the web client's **Client ID** and **Client Secret**.

## 5. Account deletion RPC

The client can't delete its own `auth.users` row, so deletion goes through a
`SECURITY DEFINER` function that only ever deletes the caller. Run this in
the **SQL Editor**:

```sql
create or replace function public.delete_user()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;

-- Only signed-in users may call it.
revoke execute on function public.delete_user() from anon, public;
grant execute on function public.delete_user() to authenticated;
```

Deleting the `auth.users` row cascades to sessions and identities. If you
later add user-data tables, give them `on delete cascade` foreign keys to
`auth.users(id)` so this function keeps wiping everything.

## 6. Optional polish

- **Email templates** (Authentication → Emails): default Supabase templates
  work; restyle them when branding matters. The built-in sender is fine for
  development, but set up custom SMTP before launch — the default is
  heavily rate-limited (a few emails per hour).
- **Rate limits** (Authentication → Rate Limits): defaults are sensible;
  review before launch.

## Security notes (how the app side is built)

- Sessions are stored in the iOS Keychain and silently refreshed by the
  Supabase SDK; the auth flow is PKCE end to end.
- Sign in with Apple uses a fresh random nonce per attempt (SHA-256 in the
  request, raw to Supabase) so identity tokens can't be replayed.
- The password-reset flow never reveals whether an account exists.
- When you add server-side user data, enable RLS on every table from day
  one; the anon key's safety depends on it.
