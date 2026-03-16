# Google Calendar Sync

EasyAppointments supports bidirectional synchronization with Google Calendar. Each provider
links their own Google Calendar account via an OAuth 2.0 consent flow, and appointments are
kept in sync between both systems automatically.

---

## 1. Google Cloud Console Setup

These steps are performed once per deployment by the operator.

### Create a Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use an existing one)
3. Note the project name for reference

### Enable the Google Calendar API

1. Navigate to **APIs & Services > Library**
2. Search for **Google Calendar API**
3. Click **Enable**

### Configure the OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Select **External** user type, then click **Create**
3. Fill in the required fields:
   - **App name**: your product name (e.g., "Padlockd Scheduling")
   - **User support email**: your support email
   - **Developer contact information**: your email
4. On the **Scopes** step, click **Add or Remove Scopes** and add:
   - `https://www.googleapis.com/auth/calendar`
5. On the **Test users** step, add the Google accounts of every provider who will sync
   their calendar (required while the app is in Testing mode)
6. Click **Save and Continue** through the remaining steps

> **Important**: While the consent screen is in **Testing** mode, only the listed test
> users can authorize. To remove this restriction, submit the app for verification — but
> Testing mode is fine for most single-tenant deployments.

### Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **+ Create Credentials > OAuth client ID**
3. Select **Web application** as the application type
4. Set the following (replace `ea.yourdomain.com` with your actual EA URL):
   - **Authorized JavaScript origins**: `https://ea.yourdomain.com`
   - **Authorized redirect URIs**: `https://ea.yourdomain.com/index.php/google/oauth_callback`
5. Click **Create**
6. Copy the **Client ID** and **Client Secret**

> **Do NOT create a Service Account.** EasyAppointments uses OAuth 2.0 where each provider
> links their own Google Calendar via the consent flow. A service account cannot act on
> behalf of individual provider Google accounts without domain-wide delegation.

---

## 2. EasyAppointments Configuration

Set these environment variables on your deployment (e.g., in Coolify):

```
EA_GOOGLE_SYNC=true
EA_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
EA_GOOGLE_CLIENT_SECRET=GOCSPX-xxxx
```

These values come from the OAuth 2.0 credentials created in the previous step.

If using `config.php` directly (non-Docker), set the corresponding constants:

```php
const GOOGLE_SYNC_FEATURE = 'true';
const GOOGLE_CLIENT_ID    = 'xxxx.apps.googleusercontent.com';
const GOOGLE_CLIENT_SECRET = 'GOCSPX-xxxx';
```

Environment variables take precedence over `config.php` constants when both are set.

---

## 3. Per-Provider Activation

Each provider must individually link their Google Calendar. This is done in the EA admin UI:

1. Log in to the EasyAppointments backend
2. Go to the **Calendar** page
3. Select a provider from the provider list
4. Click the **Enable Sync** button
5. A Google consent popup will appear — the provider grants access with their Google account
6. After authorization, select which Google Calendar to sync with from the dropdown
7. Sync is now active for that provider

Each provider can only sync with one Google Calendar at a time.

---

## 4. How Sync Works

### Real-time Sync

Every time an appointment is created, updated, or deleted in EasyAppointments, the change
is immediately pushed to the provider's linked Google Calendar (and vice versa for the
next sync cycle).

### Periodic Full Sync

A background cron runs every **15 minutes** inside the Docker container. This full
bidirectional sync catches:

- Events deleted directly in Google Calendar
- Drift between systems caused by network failures
- Failed real-time syncs that need retry

The cron only runs when `EA_GOOGLE_SYNC=true` is set. Logs are written to
`/var/log/ea-sync.log` inside the container.

### Manual Sync

- **Admin UI**: Click the **Trigger Sync** button on the Calendar page for a specific provider
- **CLI**: Run `php index.php console sync` from the application root (syncs all enabled
  providers)

---

## 5. Troubleshooting

### Provider gets "Access Denied" or token error

The OAuth token has expired or been revoked. The provider needs to re-authorize:

1. Go to **Calendar** page in the backend
2. Select the affected provider
3. Click **Disable Sync**, then **Enable Sync** again
4. Complete the Google consent flow

### Only some users can authorize (403 error)

The OAuth consent screen is in **Testing** mode. Only Google accounts listed as test users
can authorize. Either:

- Add the user's Google account to the test users list in Google Cloud Console
- Submit the app for verification to allow any Google account

### "Redirect URI mismatch" error

The redirect URI configured in Google Cloud Console must **exactly** match your EA
deployment URL, including:

- Protocol (`https://` not `http://`)
- Domain (no trailing slash)
- Path: `/index.php/google/oauth_callback`

Example: `https://ea.yourdomain.com/index.php/google/oauth_callback`

### Sync appears enabled but events aren't syncing

1. Check that `EA_GOOGLE_SYNC=true` is set in the environment
2. Verify the provider has completed the OAuth flow (check Calendar page)
3. Check container sync logs: `docker exec <container> cat /var/log/ea-sync.log`
4. Run a manual sync to check for errors:
   `docker exec <container> php /var/www/html/index.php console sync`

### Recurring events

Recurring (repeating) events in Google Calendar are not fully supported. Individual
occurrences will sync, but the recurrence rule itself is not preserved.

---

## Architecture Reference

```
Provider's Browser                    EasyAppointments              Google Calendar
       |                                    |                             |
       |-- clicks "Enable Sync" ----------->|                             |
       |<--- Google OAuth consent popup ----|                             |
       |-- grants access ----------------->|                             |
       |                                    |-- stores OAuth tokens ----->|
       |                                    |                             |
       |-- creates appointment ----------->|                             |
       |                                    |-- real-time sync ---------->|
       |                                    |                             |
       |                                    |<-- periodic full sync ----->|
       |                                    |   (every 15 min via cron)   |
```

---

[Back](readme.md)
