-- =====================================================================
-- 옹기종기(Onggi) 0단계 프로토타입 — Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 통째로 붙여넣고 Run 하세요.
-- 실행 전: Authentication > Sign In / Providers 에서
--          "Allow anonymous sign-ins" 를 켜 주세요.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------

-- 사용자 프로필 (캐릭터 정보 포함). id = 로그인 사용자 id
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nickname    text not null check (char_length(nickname) between 1 and 20),
  species     text not null default 'cat'
              check (species in ('cat', 'bear', 'bunny', 'chick', 'monkey', 'puppy')),
  color       text not null default 'cream'
              check (color in ('cream', 'peach', 'mint', 'sky', 'lilac', 'cocoa')),
  created_at  timestamptz not null default now()
);

-- 그룹 (친구방, 스터디방 등). 초대 코드로 입장
create table public.groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 1 and 30),
  invite_code  text not null unique
               default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  created_by   uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now()
);

-- 그룹 멤버 (한 사람이 여러 그룹에 가입 가능, 그룹당 최대 10명)
create table public.group_members (
  group_id   uuid not null references public.groups(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

-- 현재 상태 (사용자당 1행). 모든 그룹에 같은 상태가 보임
create table public.statuses (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  activity    text not null default 'rest'
              check (activity in ('study', 'work', 'sleep', 'walk', 'rest')),
  memo        text check (memo is null or char_length(memo) <= 30),
  started_at  timestamptz not null default now(),  -- 이 상태를 시작한 시각 ("2시간째")
  updated_at  timestamptz not null default now()
);

-- 찌르기·응원·간식 (캐릭터끼리 상호작용)
create table public.pokes (
  id          bigint generated always as identity primary key,
  from_user   uuid not null references public.profiles(id) on delete cascade,
  to_user     uuid not null references public.profiles(id) on delete cascade,
  group_id    uuid not null references public.groups(id) on delete cascade,
  kind        text not null default 'poke' check (kind in ('poke', 'cheer', 'snack')),
  created_at  timestamptz not null default now(),
  check (from_user <> to_user)
);
create index pokes_to_user_idx on public.pokes (to_user, created_at desc);

-- ---------------------------------------------------------------------
-- 2. 상태가 바뀔 때만 started_at 을 새로 찍는 트리거
--    (메모만 바꾸면 "2시간째"가 유지됨)
-- ---------------------------------------------------------------------
create function public.touch_status() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.started_at := now();
  elsif new.activity is distinct from old.activity then
    new.started_at := now();
  else
    new.started_at := old.started_at;
  end if;
  return new;
end $$;

create trigger statuses_touch
before insert or update on public.statuses
for each row execute function public.touch_status();

-- ---------------------------------------------------------------------
-- 3. 권한 확인용 함수 (RLS 안에서 재귀 없이 쓰기 위해 security definer)
-- ---------------------------------------------------------------------
create function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members where group_id = g and user_id = auth.uid()
  );
$$;

create function public.shares_group(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from group_members a
    join group_members b on a.group_id = b.group_id
    where a.user_id = auth.uid() and b.user_id = other
  );
$$;

-- ---------------------------------------------------------------------
-- 4. Row Level Security — 같은 그룹 친구끼리만 서로 보임
-- ---------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;
alter table public.statuses      enable row level security;
alter table public.pokes         enable row level security;

-- profiles
create policy "프로필: 나와 같은 그룹 친구만 조회" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_group(id));
create policy "프로필: 내 것만 생성" on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy "프로필: 내 것만 수정" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- groups (생성·가입은 아래 RPC로만)
create policy "그룹: 멤버만 조회" on public.groups
  for select to authenticated using (public.is_member(id));

-- group_members
create policy "멤버: 같은 그룹 멤버 목록 조회" on public.group_members
  for select to authenticated using (public.is_member(group_id));
create policy "멤버: 스스로 나가기" on public.group_members
  for delete to authenticated using (user_id = auth.uid());

-- statuses
create policy "상태: 나와 같은 그룹 친구만 조회" on public.statuses
  for select to authenticated
  using (user_id = auth.uid() or public.shares_group(user_id));
create policy "상태: 내 것만 생성" on public.statuses
  for insert to authenticated with check (user_id = auth.uid());
create policy "상태: 내 것만 수정" on public.statuses
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- pokes
create policy "찌르기: 보낸 것·받은 것만 조회" on public.pokes
  for select to authenticated
  using (to_user = auth.uid() or from_user = auth.uid());
create policy "찌르기: 같은 그룹 친구에게만 보내기" on public.pokes
  for insert to authenticated
  with check (
    from_user = auth.uid()
    and public.is_member(group_id)
    and exists (select 1 from public.group_members m
                where m.group_id = pokes.group_id and m.user_id = pokes.to_user)
  );

-- ---------------------------------------------------------------------
-- 5. RPC — 그룹 만들기 / 초대 코드로 가입 (최대 10명)
-- ---------------------------------------------------------------------
create function public.create_group(p_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'profile_required';
  end if;
  insert into groups (name, created_by) values (trim(p_name), auth.uid()) returning * into g;
  insert into group_members (group_id, user_id) values (g.id, auth.uid());
  return g;
end $$;

create function public.join_group(p_code text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups; n int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'profile_required';
  end if;
  select * into g from groups where invite_code = upper(trim(p_code)) for update;
  if not found then raise exception 'invalid_code'; end if;
  if exists (select 1 from group_members where group_id = g.id and user_id = auth.uid()) then
    return g;  -- 이미 가입됨
  end if;
  select count(*) into n from group_members where group_id = g.id;
  if n >= 10 then raise exception 'group_full'; end if;
  insert into group_members (group_id, user_id) values (g.id, auth.uid());
  return g;
end $$;

revoke execute on function public.create_group(text) from public, anon;
revoke execute on function public.join_group(text)   from public, anon;
grant  execute on function public.create_group(text) to authenticated;
grant  execute on function public.join_group(text)   to authenticated;

-- ---------------------------------------------------------------------
-- 6. 실시간(Realtime) — 상태·찌르기·멤버 변경을 앱이 바로 받도록
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table public.statuses, public.pokes, public.group_members;
