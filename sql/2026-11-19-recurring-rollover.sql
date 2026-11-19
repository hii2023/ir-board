-- 2026-11-19: stop recurring chores from piling up.
-- Before: every occurrence inserted a NEW task, so a missed daily chore left one
-- extra overdue card per day (323 duplicate open copies had built up).
-- After: a schedule keeps at most ONE open task. A new occurrence moves that open
-- task's due date forward instead of adding another card. Once it is ticked done,
-- the next occurrence creates a fresh task as before.

-- 1. Safety copy of every task before the cleanup below.
create table if not exists public.irb_tasks_bak_20261119 as table public.irb_tasks;
alter table public.irb_tasks_bak_20261119 enable row level security;

-- 2. Record who did each action (name picked on the device, no login).
alter table public.irb_activity add column if not exists actor text;

-- 3. Generator with carry-forward.
create or replace function public.irb_generate_recurring(p_lookback_days integer default 14)
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  r          record;
  d          date;
  d_from     date;
  d_to       date;
  matches    boolean;
  dom        int;
  n_ins      int;
  v_task_id  uuid;
  v_open_id  uuid;
  v_open_due text;
  v_created  int := 0;
  v_stamp    text;
begin
  d_to := current_date;

  for r in select * from public.irb_recurring where active loop
    d_from := greatest(r.start_date, d_to - greatest(coalesce(p_lookback_days, 14), 0));
    d := d_from;

    while d <= d_to loop
      if r.end_date is not null and d > r.end_date then
        exit;
      end if;

      matches := false;
      if r.freq = 'daily' then
        matches := true;
      elsif r.freq = 'weekly' then
        matches := extract(dow from d)::int = any (r.weekdays);
      elsif r.freq = 'monthly' then
        dom := least(coalesce(r.day_of_month, 1),
                     extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::int);
        matches := extract(day from d)::int = dom;
      end if;

      if matches then
        insert into public.irb_recurring_runs (recurring_id, occ_date)
        values (r.id, d)
        on conflict do nothing;

        get diagnostics n_ins = row_count;

        if n_ins > 0 then
          -- Is the previous copy still open? Then carry it forward, no new card.
          select id, due_date into v_open_id, v_open_due
            from public.irb_tasks
           where recurring_id = r.id and not done
           order by due_date desc nulls last, created_at desc
           limit 1;

          if v_open_id is not null then
            if v_open_due is null or v_open_due < to_char(d, 'YYYY-MM-DD') then
              update public.irb_tasks
                 set due_date = to_char(d, 'YYYY-MM-DD')
               where id = v_open_id;
            end if;
            v_task_id := v_open_id;
          else
            v_stamp := to_char(d, 'MM/DD/YYYY') || ' 00:00';

            insert into public.irb_tasks
              (name, descr, owner, owners, category, due_date, link, done,
               sort_order, created_at, subtasks, logs, recurring_id)
            values
              (r.name, r.descr, r.owner,
               case when jsonb_array_length(coalesce(r.owners,'[]'::jsonb)) > 0
                    then r.owners
                    when coalesce(r.owner,'') <> '' then jsonb_build_array(r.owner)
                    else '[]'::jsonb end,
               r.category, to_char(d, 'YYYY-MM-DD'), r.link, false,
               (extract(epoch from now()) * 1000)::bigint,
               (extract(epoch from d) * 1000)::bigint,
               r.subtasks,
               jsonb_build_array(jsonb_build_object(
                 'text', 'Created from recurring schedule',
                 'time', v_stamp,
                 'type', 'created')),
               r.id)
            returning id into v_task_id;

            v_created := v_created + 1;
          end if;

          update public.irb_recurring_runs
             set task_id = v_task_id
           where recurring_id = r.id and occ_date = d;
        end if;
      end if;

      d := d + 1;
    end loop;
  end loop;

  return v_created;
end;
$function$;

-- 4. One-time cleanup: per schedule keep only the newest open copy.
--    None of the removed copies had comments or ticked subtasks (checked first).
--    Everything removed is still in irb_tasks_bak_20261119.
with o as (
  select id, row_number() over (partition by recurring_id
                                order by due_date desc nulls last, created_at desc) rn
    from public.irb_tasks
   where recurring_id is not null and not done
)
delete from public.irb_tasks t using o
 where t.id = o.id and o.rn > 1;
