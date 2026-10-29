-- An optional complete box for ONE individually packed SKU. Multiple items
-- still require an actual packing decision, not arithmetic on item dimensions.
begin;
alter table public.products add column packed_dimensions jsonb
  check (packed_dimensions is null or (
    jsonb_typeof(packed_dimensions) = 'object'
    and packed_dimensions ?& array['length_cm','width_cm','height_cm']
    and jsonb_typeof(packed_dimensions->'length_cm') = 'number'
    and jsonb_typeof(packed_dimensions->'width_cm') = 'number'
    and jsonb_typeof(packed_dimensions->'height_cm') = 'number'
    and (packed_dimensions->>'length_cm')::numeric > 0
    and (packed_dimensions->>'width_cm')::numeric > 0
    and (packed_dimensions->>'height_cm')::numeric > 0
  ));
alter table public.product_variants add column packed_dimensions jsonb
  check (packed_dimensions is null or (
    jsonb_typeof(packed_dimensions) = 'object'
    and packed_dimensions ?& array['length_cm','width_cm','height_cm']
    and jsonb_typeof(packed_dimensions->'length_cm') = 'number'
    and jsonb_typeof(packed_dimensions->'width_cm') = 'number'
    and jsonb_typeof(packed_dimensions->'height_cm') = 'number'
    and (packed_dimensions->>'length_cm')::numeric > 0
    and (packed_dimensions->>'width_cm')::numeric > 0
    and (packed_dimensions->>'height_cm')::numeric > 0
  ));
commit;
