-- BANCO COMPLETO: cole tudo no Supabase > SQL Editor > New query > Run (uma vez só)

-- Cole tudo no Supabase > SQL Editor > Run

create table profiles(id uuid primary key references auth.users on delete cascade,
  name text, email text, role text default 'rev', status text default 'pending');
create table products(id bigint generated always as identity primary key,
  name text not null, cat text default 'Outros', emo text default '📦', img text default '',
  colors text default '', vars jsonb not null default '[]');
create table orders(id bigint generated always as identity primary key,
  user_id uuid references auth.users on delete set null, who text, items jsonb, total numeric,
  created_at timestamptz default now());

-- Novo cadastro: admin@admin.com vira admin; os demais ficam pendentes
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,name,email,role,status) values(new.id,
    coalesce(new.raw_user_meta_data->>'name',new.email), new.email,
    case when new.email='admin@admin.com' then 'admin' else 'rev' end,
    case when new.email='admin@admin.com' then 'active' else 'pending' end);
  return new;
end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

create function is_admin() returns boolean language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
create function is_active() returns boolean language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and status='active') $$;

-- Admin remove revendedor de vez (apaga o login)
create function admin_delete_user(uid uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'Apenas admin'; end if;
  delete from auth.users where id=uid and id<>auth.uid();
end $$;

alter table profiles enable row level security;
alter table products enable row level security;
alter table orders enable row level security;

create policy "perfil: ver o meu ou admin" on profiles for select using(id=auth.uid() or is_admin());
create policy "perfil: admin altera" on profiles for update using(is_admin());
create policy "produtos: ativos veem" on products for select using(is_active());
create policy "produtos: admin escreve" on products for all using(is_admin()) with check(is_admin());
create policy "pedidos: ver os meus ou admin" on orders for select using(user_id=auth.uid() or is_admin());
create policy "pedidos: ativo cria" on orders for insert with check(is_active() and user_id=auth.uid());

-- Fotos dos produtos
insert into storage.buckets(id,name,public) values('produtos','produtos',true);
create policy "fotos: leitura" on storage.objects for select using(bucket_id='produtos');
create policy "fotos: admin envia" on storage.objects for insert with check(bucket_id='produtos' and is_admin());
create policy "fotos: admin altera" on storage.objects for update using(bucket_id='produtos' and is_admin());
create policy "fotos: admin apaga" on storage.objects for delete using(bucket_id='produtos' and is_admin());

-- Produtos da tabela de revenda
insert into products(name,cat,emo,colors,vars) values
('Cama P','Camas','🐶','Rosa, Marrom, Azul, Vermelho, Amarelo','[{"n":"Normal","p":39},{"n":"Impermeável","p":41}]'),
('Cama M','Camas','🐶','Rosa, Marrom, Azul, Vermelho, Amarelo','[{"n":"Normal","p":48},{"n":"Impermeável","p":57}]'),
('Cama G','Camas','🐶','Rosa, Marrom, Azul, Vermelho, Amarelo','[{"n":"Normal","p":56},{"n":"Impermeável","p":66}]'),
('Cama Retangular 70x80','Camas','🛏️','Rosa, Marrom, Azul, Vermelho, Amarelo','[{"n":"Normal","p":66},{"n":"Impermeável","p":78}]'),
('Cama GG','Camas','🛏️','Rosa, Marrom, Azul, Vermelho, Amarelo','[{"n":"Normal","p":72},{"n":"Impermeável","p":88}]'),
('Cama Redonda','Camas','⭕','Bege, Rosa, Azul, Preto','[{"n":"Preço único","p":25.5}]'),
('Tapete de Ossinho','Tapetes & Edredons','🦴','Azul, Rosa, Amarelo, Marrom','[{"n":"P","p":10},{"n":"GG","p":14}]'),
('Edredom Pet','Tapetes & Edredons','🧣','Azul, Rosa, Marrom','[{"n":"P","p":23.5},{"n":"GG","p":36},{"n":"+ Tapete P","p":33},{"n":"+ Tapete GG","p":48}]'),
('Manta Microfibra','Tapetes & Edredons','🧶','Cinza, Azul, Preto, Rosa, Vermelho, Marrom','[{"n":"Única","p":10}]'),
('Colchão Impermeável','Colchões','🛌','Preto, Azul, Marrom, Rosa','[{"n":"50x60 (1 capa)","p":33},{"n":"50x60 (2 capas)","p":41},{"n":"65x95 (1 capa)","p":63},{"n":"65x95 (2 capas)","p":72},{"n":"70x1m (1 capa)","p":72},{"n":"70x1m (2 capas)","p":84}]'),
('Colchonete','Colchões','🟫','Rosa, Cinza, Preto, Vermelho, Azul, Marrom, Vinho','[{"n":"N5","p":27},{"n":"N4","p":21},{"n":"N3","p":16.8},{"n":"N1","p":11.5}]'),
('Toalha de Natal','Natal','🎄','Vermelho, Verde','[{"n":"4 lugares","p":16.5},{"n":"6 lugares","p":22.8},{"n":"8 lugares","p":27.5}]');

-- PRODUCAO E STATUS

-- Status e e-mail nos pedidos
alter table orders add column status text not null default 'novo' check (status in ('novo','producao','concluido'));
alter table orders add column email text;
update orders o set email=p.email from profiles p where p.id=o.user_id and o.email is null;

create function is_prod() returns boolean language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and role='prod' and status='active') $$;

-- producao@admin.com vira usuário de Produção automaticamente ao se cadastrar
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,name,email,role,status) values(new.id,
    coalesce(new.raw_user_meta_data->>'name',new.email), new.email,
    case new.email when 'admin@admin.com' then 'admin' when 'producao@admin.com' then 'prod' else 'rev' end,
    case when new.email in ('admin@admin.com','producao@admin.com') then 'active' else 'pending' end);
  return new;
end $$;

-- Pedidos: admin faz tudo; produção só vê; revendedor vê e cria os seus
drop policy "pedidos: ver os meus ou admin" on orders;
drop policy "pedidos: ativo cria" on orders;
create policy "pedidos: ver" on orders for select using(user_id=auth.uid() or is_admin() or is_prod());
create policy "pedidos: admin tudo" on orders for all using(is_admin()) with check(is_admin());
create policy "pedidos: revendedor cria" on orders for insert with check(is_active() and not is_prod() and user_id=auth.uid());

-- Produção não vê catálogo/preços
drop policy "produtos: ativos veem" on products;
create policy "produtos: revendedor e admin veem" on products for select using(is_active() and not is_prod());

-- Produção só pode mudar o status para 'producao' ou 'concluido'
create function set_order_status(pedido_id bigint, novo_status text) returns void language plpgsql security definer set search_path=public as $$
begin
  if is_admin() and novo_status in ('novo','producao','concluido') then
    update orders set status=novo_status where id=pedido_id;
  elsif is_prod() and novo_status in ('producao','concluido') then
    update orders set status=novo_status where id=pedido_id;
  else raise exception 'Sem permissão';
  end if;
end $$;

-- WHATSAPP

alter table profiles add column phone text;
alter table orders add column phone text;

-- Cadastro passa a guardar o WhatsApp
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,name,email,phone,role,status) values(new.id,
    coalesce(new.raw_user_meta_data->>'name',new.email), new.email,
    new.raw_user_meta_data->>'phone',
    case new.email when 'admin@admin.com' then 'admin' when 'producao@admin.com' then 'prod' else 'rev' end,
    case when new.email in ('admin@admin.com','producao@admin.com') then 'active' else 'pending' end);
  return new;
end $$;

-- OBSERVACAO
alter table orders add column note text;
