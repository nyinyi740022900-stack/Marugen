-- Lets admins hide a Variety or Guide from customers without deleting it —
-- same "active" pattern as public.services (see 0021).
--
-- Admins already see every row regardless of "active" via the existing
-- "Admins can manage ..." policies (for all → includes select), so only
-- the public/anon-facing select policy needs to be narrowed to active rows.

alter table public.varieties
  add column if not exists active boolean not null default true;

drop policy if exists "Anyone can view varieties" on public.varieties;
create policy "Anyone can view active varieties"
  on public.varieties for select using (active = true);

alter table public.knowledge_articles
  add column if not exists active boolean not null default true;

drop policy if exists "Anyone can view articles" on public.knowledge_articles;
create policy "Anyone can view active articles"
  on public.knowledge_articles for select using (active = true);
