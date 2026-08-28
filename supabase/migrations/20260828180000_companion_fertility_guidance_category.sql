-- #108 keeps fertility communication independently classifiable from ordinary
-- phase guidance. The history row stores only notification metadata; no cycle
-- dates/ranges beyond the opaque guidance id, raw health fields or rendered copy.

alter table lifemate.women_companion_guidance_history
  drop constraint if exists ck_companion_guidance_category;

alter table lifemate.women_companion_guidance_history
  add constraint ck_companion_guidance_category
  check (category in ('general','phase','mood','energy','fertility'));
