-- Legacy AppUser bootstrap trigger maintains the FREE baseline entitlements.
-- The Edge role needs only this commerce write surface; other commerce tables
-- remain read-only for application runtime.
grant insert, update on commerce.entitlements to lifemate_edge_runtime;
