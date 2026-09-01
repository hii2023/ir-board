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

- **`irb_recurring`** — one row per repeating schedule (what repeats, who it's assigned
  to, how often).
- **`irb_recurring_runs`** — ledger of occurrences already created. Kept separate from
  `irb_tasks` on purpose: deleting a generated task does **not** cause it to reappear.

### Functions

- **`irb_append_log(p_id, p_entry, p_done, p_completed_at)`** — appends one entry to a
  task's `logs` array server-side. Comments and done/reopen stamps go through this so
  two people acting on the same task at the same time cannot overwrite each other's
  entries. (Verified: five concurrent appends all survive.)
- **`irb_generate_recurring(p_lookback_days)`** — turns due schedule occurrences into
  real tasks. Idempotent via the `irb_recurring_runs` primary key, so every board can
  safely call it on load without creating duplicates.

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

## Recurring tasks

The **R** button in the top bar opens the schedules page. You can also create a schedule
without leaving the New Task sheet: tap the **R** toggle near the bottom of the form and the
repeat options appear in place of the due date.

A schedule describes work that repeats: what it is, **who it is assigned to**, a category,
optional subtasks, and how often it repeats.

| Repeats | You set |
|---|---|
| Daily | nothing else |
| Weekly | which weekdays (any combination) |
| Monthly | a day of the month, 1 to 31 |

A "31st" monthly schedule falls back to the last day in shorter months, so it fires in
February and never skips a month.

Each schedule also takes a start date and an optional end date. The toggle on the right
pauses a schedule: no new tasks are created, nothing already on the board is affected,
and flipping it back on resumes.

### How the tasks appear

Schedules do not live in a separate list. On each of its dates, a schedule creates a **real
task on the board**, owned by the person you assigned, with its category and subtasks
copied in. Those tasks are shown in a different colour: a **cyan left edge, a cyan tint,
and a `↻ Recurring` badge**.

From there they behave like any other task. Tick one off, comment on it, drag it, edit it,
delete it. None of that changes the schedule, and a deleted occurrence will not come back.

### When they get created

Whenever someone opens the board, and again if a board is left open across midnight.
There is no server cron: generation runs from the page, and the `irb_recurring_runs`
ledger makes it safe for several people to open the board at the same time.

Missed days are backfilled up to **14 days** and land as overdue, so work that was skipped
while nobody had the board open still shows up. Older gaps are not backfilled, which keeps
a schedule with an old start date from dumping months of history onto the board.

## Using the board

The top bar uses single letters so everything fits on a phone: **R** recurring,
**D** dashboard, **C** compact/detailed, plus the settings gear.

| Action | How |
|---|---|
| New task | `+` button, or press `N` |
| Edit a task | Double-click (double-tap on mobile) the card |
| Mark done / reopen | Click the circle on the left |
| Comments & history | Speech-bubble icon on the card |
| Reorder | Drag a card (long-press first on mobile) |
| Filter | Overdue / This Wk chips, plus **☰ Filter** for date and category (desktop uses the sidebar) |
| Stats | **D** button |
| Repeating work | **R** button |
| Theme / install | Settings (gear) |
| Light / dark | Settings → Appearance (remembered per device) |

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

## Layout notes

The board is built to fit a phone screen without sideways scrolling, and without the
action buttons ever being pushed off the right edge (the settings gear used to disappear
once enough people were added). On narrow screens the brand name and, on very small
phones, the task count give up their space first.

**When editing the CSS:** the responsive rules live in one block at the very end of the
`<style>` tag, and they must stay there. Media queries add no specificity, so a phone rule
placed before the base rule it overrides is silently ignored.

## Filtering on a phone

The chip bar keeps only the two everyday shortcuts inline — **Overdue** and **This Wk** —
plus an owner row. Everything else lives behind **☰ Filter**:

- **Date**: Next Week, This Month, No Due Date
- **Category**: every category you've configured, each with a count of active tasks, plus
  No Category

The Filter chip turns green with a dot when something inside it is on, and **Clear** in the
sheet resets just those. Overdue and This Wk stay independent of it. On desktop nothing
changed: the sidebar still lists every date option and category directly.
