# goodfriend — web (read-only)

A spreadsheet-style dashboard of your People and upcoming reminders. Reads the
same Supabase database as the iOS app. No build step — plain HTML/CSS/JS.

## One-time Supabase setup

In your Supabase dashboard:

1. **Authentication → Providers → Email**: make sure **Email** is enabled
   (magic-link / OTP is on by default).
2. **Authentication → URL Configuration → Redirect URLs**: add the URLs you'll
   open the site from, e.g.
   - `http://localhost:5173` (local testing)
   - your deployed URL later (e.g. `https://goodfriend.vercel.app`)

## Run it locally

From this `web/` folder, start any static server. Easiest (Python is already on
your Mac):

```
cd web
python3 -m http.server 5173
```

Then open <http://localhost:5173> and sign in with your email.

> Opening `index.html` directly (file://) will **not** work for login — the
> magic link needs a real `http://` address to redirect back to.

## Deploy (later, free)

Drag this `web/` folder onto <https://app.netlify.com/drop>, or connect the repo
to Vercel and set the root to `web/`. Then add that URL to the Supabase redirect
list above.

## If the tables are empty but your phone has data

The iOS app signs in with **Apple**; the web signs in with **email**. If your
Apple ID's email matches the email you use here, Supabase treats them as the
same account and you'll see your data. If Apple used a private-relay address (or
didn't share your email), they may be **different accounts** with different data.
If that happens, tell me — we reconcile it in Supabase (match the user IDs).
