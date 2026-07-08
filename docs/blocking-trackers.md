# Blocking trackers (network layer)

The consent-popup patches in this kit (`Auto-reject OneTrust consent banner`,
Tinder `Disable consent prompt`) suppress the *prompt* and leave consent
**ungranted**. That is the correct in-app outcome, but it is **not** tracker
blocking: many SDKs phone home regardless of the TCF/consent flag, and a patch
only touches the one app it's built for. The real, app-agnostic block happens at
the **network layer** — a local DNS filter that drops tracker domains for *every*
app at once, no re-sign, survives app updates.

This is the "universal" answer. Use it alongside the per-app popup patches, not
instead of them.

## Tool (Android, no root)

**RethinkDNS** (FOSS, Play Store / F-Droid / github.com/celzero/rethink-app) — a
local no-root VPN that does per-app DNS filtering with blocklists. Recommended.

Alternatives (any one is fine — they all use the local-VPN slot, so run only one):
- **NextDNS** — cloud resolver, config in a web dashboard, thinnest on battery.
- **AdGuard for Android** — paid, most polished, app-level rules.
- **PCAPdroid** / **Blokada 5 (FOSS fork)** — lighter FOSS options.

Only one app can hold the VPN slot at a time. If you patch *and* run a blocker,
that's fine — the patch is in-process, the blocker is the network layer.

## Blocklists to enable

Don't hand-curate the 90 TCF partners — a maintained list already covers them
plus OneTrust, analytics, and ad SDKs. In RethinkDNS → *Configure → DNS →
Blocklists*, enable:

- **OISD (full)** — broad, low false-positive, good default.
- **HaGeZi – Pro** (or *Multi Pro*) — aggressive on mobile analytics/telemetry;
  catches Adjust/Braze/Amplitude/AppsFlyer/Branch that OISD sometimes leaves.

That combination blocks the OneTrust CDN, the IAB/TCF vendor endpoints behind the
"90 partners", and the common mobile analytics SDKs.

## Targeted supplement (optional)

If you'd rather add explicit rules, or want to confirm the big offenders are
covered, these are the tracker/consent hosts for Tinder + Meetup. **Block these:**

```
# Consent-management (the popup's own backend)
cdn.cookielaw.org
geolocation.onetrust.com
cookie-cdn.cookiepro.com
*.onetrust.com

# Mobile analytics / attribution SDKs (Match Group + Meetup)
app.adjust.com
*.adjust.com
*.braze.com
*.appboy.com
api.amplitude.com
*.amplitude.com
*.appsflyer.com
*.branch.io
api.segment.io
*.leanplum.com

# Ad / measurement
googleads.g.doubleclick.net
pagead2.googlesyndication.com
*.doubleclick.net
www.google-analytics.com
*.crashlytics.com
```

## Do NOT block (functional — breaks the app)

Allow-list these if a broad blocklist catches them:

```
# Tinder core API + media
api.gotinder.com
*.gotinder.com
*.tindercdn.com
# Meetup core API + media
api.meetup.com
*.meetup.com
secure.meetupstatic.com
# Auth / push you probably want kept
firebaseinstallations.googleapis.com   # FCM registration (push)
*.googleapis.com                        # maps tiles, play services
graph.facebook.com                      # only if you use Facebook login
```

Note: `*.googleapis.com` carries both tracking (`app-measurement`,
`firebase-settings`) and functional traffic (Maps, Play Integrity, FCM). The
maintained blocklists already split these at the subdomain level — prefer them
over a blanket `googleapis.com` rule, which would break Meetup map tiles and push.

## Verifying

RethinkDNS → *Logs* shows live DNS queries per app with blocked/allowed status.
Open Tinder/Meetup, watch the log: the consent-CDN and analytics hosts should
show **blocked**; `api.gotinder.com` / `api.meetup.com` should show **allowed**.
If something in the app breaks, find the last blocked host in the log for that app
and allow-list it.
