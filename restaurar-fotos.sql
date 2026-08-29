-- ============================================================
-- Zagonel Arenapolis - restaurar as fotos dos produtos
-- Os arquivos JA ESTAO no bucket produtos-imagens. O que se perdeu
-- foi o campo "imagemUrl" dentro do cadastro de cada produto.
-- O nome do arquivo e "<id-do-produto>-<horario>.jpg", entao da
-- para religar cada foto ao produto certo.
-- ============================================================


-- ------------------------------------------------------------
-- PASSO 1 - CONFERIR (so leitura, nao altera nada)
-- Mostra quantas fotos serao religadas e a quais produtos.
-- ------------------------------------------------------------
with fotos as (
  select
    left(name, length(name) - position('-' in reverse(name))) as produto_id,
    name
  from storage.objects
  where bucket_id = 'produtos-imagens'
    and name like '%-%'
),
mais_recente as (
  select distinct on (produto_id) produto_id, name
  from fotos
  order by produto_id, name desc      -- se houver varias fotos, usa a mais nova
)
select produto_id, name as arquivo
from mais_recente
order by produto_id;


-- ------------------------------------------------------------
-- PASSO 2 - RESTAURAR (este altera o banco)
-- Rode so depois de conferir o resultado do Passo 1.
-- ------------------------------------------------------------
with fotos as (
  select
    left(name, length(name) - position('-' in reverse(name))) as produto_id,
    'https://uztdenaepnplihsafmdp.supabase.co/storage/v1/object/public/produtos-imagens/' || name as url,
    name
  from storage.objects
  where bucket_id = 'produtos-imagens'
    and name like '%-%'
),
mais_recente as (
  select distinct on (produto_id) produto_id, url
  from fotos
  order by produto_id, name desc
),
novo as (
  select jsonb_agg(
           case
             when mr.url is null then p
             else p || jsonb_build_object('imagemUrl', mr.url)
           end
           order by ord
         ) as arr
  from estoque_kv k
  cross join lateral jsonb_array_elements(k.value::jsonb) with ordinality as t(p, ord)
  left join mais_recente mr on mr.produto_id = p ->> 'id'
  where k.key = 'produtos'
)
update estoque_kv
set value = (select arr::text from novo),
    updated_at = now()
where key = 'produtos'
  and (select arr from novo) is not null;


-- ------------------------------------------------------------
-- PASSO 3 - CONFERIR O RESULTADO (so leitura)
-- Deve mostrar o mesmo numero de fotos do Passo 1.
-- ------------------------------------------------------------
select
  jsonb_array_length(value::jsonb) as total_de_produtos,
  (select count(*)
     from jsonb_array_elements(value::jsonb) x
    where x ->> 'imagemUrl' is not null) as produtos_com_foto
from estoque_kv
where key = 'produtos';
