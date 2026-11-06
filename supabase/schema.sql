-- Saturn Mailchat: Supabase PostgreSQL schema
-- Run this file in Supabase SQL Editor. Never disable RLS in production.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null default 'Saturn user',
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'گفتگوی تازه',
  is_group boolean not null default false,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  attachment_path text,
  attachment_type text,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  constraint message_has_content check (length(trim(body)) > 0 or attachment_path is not null)
);

create index if not exists messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);
create index if not exists conversation_members_user_idx
  on public.conversation_members(user_id);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_path text not null,
  caption text not null default '',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  price_minor bigint not null check (price_minor >= 0),
  currency text not null default 'IRR',
  image_path text,
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null default 1 check (quantity > 0),
  status text not null default 'pending' check (status in ('pending','paid','cancelled','fulfilled','refunded')),
  created_at timestamptz not null default now()
);

-- Automatically create a profile for each newly registered auth user.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name',''), 'Saturn user'),
    nullif(new.raw_user_meta_data ->> 'username','')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_conversation_member(target_conversation uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = target_conversation
      and cm.user_id = (select auth.uid())
  );
$$;

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.stories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;

-- Profiles: authenticated users can discover public profile fields; only owner edits.
drop policy if exists "Profiles are readable by authenticated users" on public.profiles;
create policy "Profiles are readable by authenticated users" on public.profiles
  for select to authenticated using (true);
drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Conversations: only members can read; creator inserts; membership controls access.
drop policy if exists "Members read conversations" on public.conversations;
create policy "Members read conversations" on public.conversations
  for select to authenticated using (public.is_conversation_member(id));
drop policy if exists "Authenticated users create conversations" on public.conversations;
create policy "Authenticated users create conversations" on public.conversations
  for insert to authenticated with check (created_by = (select auth.uid()));
drop policy if exists "Conversation owner updates" on public.conversations;
create policy "Conversation owner updates" on public.conversations
  for update to authenticated using (
    exists (select 1 from public.conversation_members cm
      where cm.conversation_id = id and cm.user_id = (select auth.uid())
      and cm.role in ('owner','admin'))
  ) with check (public.is_conversation_member(id));

-- Members can see their own membership and the member list of their conversations.
drop policy if exists "Members see member lists" on public.conversation_members;
create policy "Members see member lists" on public.conversation_members
  for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "Conversation creator adds members" on public.conversation_members;
create policy "Conversation creator adds members" on public.conversation_members
  for insert to authenticated with check (
    exists (select 1 from public.conversations c
      where c.id = conversation_id and c.created_by = (select auth.uid()))
    or exists (select 1 from public.conversation_members cm
      where cm.conversation_id = conversation_id and cm.user_id = (select auth.uid())
      and cm.role in ('owner','admin'))
  );
drop policy if exists "Users leave conversations" on public.conversation_members;
create policy "Users leave conversations" on public.conversation_members
  for delete to authenticated using (
    user_id = (select auth.uid())
    or exists (select 1 from public.conversation_members cm
      where cm.conversation_id = conversation_id and cm.user_id = (select auth.uid())
      and cm.role in ('owner','admin'))
  );

-- Messages: members read; sender creates; sender edits/deletes own messages.
drop policy if exists "Members read messages" on public.messages;
create policy "Members read messages" on public.messages
  for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "Members send messages as themselves" on public.messages;
create policy "Members send messages as themselves" on public.messages
  for insert to authenticated with check (
    sender_id = (select auth.uid()) and public.is_conversation_member(conversation_id)
  );
drop policy if exists "Senders update own messages" on public.messages;
create policy "Senders update own messages" on public.messages
  for update to authenticated using (sender_id = (select auth.uid()))
  with check (sender_id = (select auth.uid()) and public.is_conversation_member(conversation_id));
drop policy if exists "Senders delete own messages" on public.messages;
create policy "Senders delete own messages" on public.messages
  for delete to authenticated using (sender_id = (select auth.uid()));

-- Stories: signed-in users may view active stories; owners manage their own.
drop policy if exists "Read active stories" on public.stories;
create policy "Read active stories" on public.stories
  for select to authenticated using (expires_at > now());
drop policy if exists "Create own stories" on public.stories;
create policy "Create own stories" on public.stories
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "Manage own stories" on public.stories;
create policy "Manage own stories" on public.stories
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists "Delete own stories" on public.stories;
create policy "Delete own stories" on public.stories
  for delete to authenticated using (user_id = (select auth.uid()));

-- Marketplace: published products are visible; sellers manage their own listings.
drop policy if exists "Read published products" on public.products;
create policy "Read published products" on public.products
  for select to authenticated using (is_published or seller_id = (select auth.uid()));
drop policy if exists "Sellers create products" on public.products;
create policy "Sellers create products" on public.products
  for insert to authenticated with check (seller_id = (select auth.uid()));
drop policy if exists "Sellers update products" on public.products;
create policy "Sellers update products" on public.products
  for update to authenticated using (seller_id = (select auth.uid()))
  with check (seller_id = (select auth.uid()));
drop policy if exists "Sellers delete products" on public.products;
create policy "Sellers delete products" on public.products
  for delete to authenticated using (seller_id = (select auth.uid()));

-- Orders: buyers see/create their own orders. Payment status must be changed by a trusted server.
drop policy if exists "Buyers read own orders" on public.orders;
create policy "Buyers read own orders" on public.orders
  for select to authenticated using (buyer_id = (select auth.uid()));
drop policy if exists "Buyers create own orders" on public.orders;
create policy "Buyers create own orders" on public.orders
  for insert to authenticated with check (buyer_id = (select auth.uid()) and status = 'pending');

-- Private bucket for user media. Keep files private and use signed URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('saturn-media', 'saturn-media', false, 52428800,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','audio/mpeg','audio/ogg','audio/webm','application/pdf'])
on conflict (id) do nothing;

drop policy if exists "Authenticated users upload own media" on storage.objects;
create policy "Authenticated users upload own media" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'saturn-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "Users read own media" on storage.objects;
create policy "Users read own media or shared message attachments" on storage.objects
  for select to authenticated using (
    bucket_id = 'saturn-media'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.messages m
        where m.attachment_path = name
          and public.is_conversation_member(m.conversation_id)
      )
    )
  );
drop policy if exists "Users delete own media" on storage.objects;
create policy "Users delete own media" on storage.objects
  for delete to authenticated using (
    bucket_id = 'saturn-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Enable Realtime for messages (safe to run repeatedly).
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
