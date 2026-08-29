# India Recycles Board

Internal team task board for India Recycles. Same structure and interaction model as
the N7 Board (`hii2023/mastertodo`), rebuilt on **India Recycles' own Supabase project**
instead of a Firebase project owned by someone else.

Single static page. No build step, no dependencies to install.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app: markup, styles, and logic |
| `ir-sw.js` | Service worker (offline shell + installable PWA) |

## Backend

Everything lives in the **India Recycles Supabase project** `sqosmiifjqecidxhyjtg`,
inside the `India Recycle Org` organisation that `indiarecyclesllp@gmail.com` owns.
Same project that already serves the marketing site CMS and the thrift store, so there
is no new account, no new bill, and nothing to hand over separately later.

The page uses the modern **publishable** key (`sb_publishable_...`), not the legacy
`anon` JWT, so it is unaffected when the legacy keys are finally disabled.

### Tables (all prefixed `irb_`)

- **`irb_tasks`** — one row per task. `subtasks` and `logs` are `jsonb` arrays.
- **`irb_activity`** — append-only feed powering the Dashboard's Recent Activity.
- **`irb_config`** — two rows, `users` and `categories`, each holding `{ "list": [...] }`.
  This is what the Settings panel edits.

### Function

- **`irb_append_log(p_id, p_entry, p_done, p_completed_at)`** — appends one entry to a
  task's `logs` array server-side. Comments and done/reopen stamps go through this so
  two people acting on the same task at the same time cannot overwrite each other's
  entries. (Verified: five concurrent appends all survive.)

Realtime is enabled on all three tables, so a change on one device shows up on every
other open board within a second, with no refresh.

## Managing users and categories

Gear icon (top right) → **Settings**:

- **Users** — type a name, `+ Add`. Remove with the `×` on a pill. Removing someone who
  still owns tasks asks for confirmation first; their tasks are kept, not deleted.
  You cannot remove the last remaining user.
- **Categories** — same pattern.

Both lists are stored in Supabase, so they are shared by everyone, not per-device.
`Parking` is the default bucket for unassigned work.

## Using the board

| Action | How |
|---|---|
| New task | `+` button, or press `N` |
| Edit a task | Double-click (double-tap on mobile) the card |
| Mark done / reopen | Click the circle on the left |
| Comments & history | Speech-bubble icon on the card |
| Reorder | Drag a card (long-press first on mobile) |
| Filter | Chips at the top, or the sidebar on desktop |
| Stats | **Dashboard** button |
| Light / dark | Theme button (remembered per device) |

Reordering is filter-safe: dragging inside a filtered view only reshuffles the visible
cards within their existing slots, so hidden tasks never move.

## Running it locally

```bash
python3 -m http.server 4455 --directory .
```

Then open http://localhost:4455.

## Installing as an app

Settings → **Install App**, or the `⇩` button in the top bar. Android/Chrome installs
directly; on iOS use Safari's Share → Add to Home Screen. `ir-sw.js` must sit in the
same folder as `index.html` for standalone mode to work.

## A note on access

The board has no login, matching the app it was modelled on. Anyone with the URL can
read and edit it, and the `irb_` row-level-security policies are deliberately open to
the anonymous role so the page works without sign-in.

Those policies are scoped to the three `irb_` tables only — they grant no access to the
store, the site CMS, or any other data in the project.

If this needs to be locked down later, the options in increasing order of effort are:
host it at an unguessed URL, put a passcode gate in front of it using the same pattern
as `recycle_verify_passcode`, or move writes behind `SECURITY DEFINER` functions that
take a passcode (which would cost live realtime updates).
