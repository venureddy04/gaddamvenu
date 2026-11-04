-- =====================================================================================
-- 03_admin_seed.sql  (run LAST, after 01 and 02).  Safe to run again at any time.
--   Admin login   : gaddamvenur@gmail.com
--   Admin password: GaddamVenu@2026
--   Admin name    : Gaddam Venu
-- The old admin (old-admin-removed@example.invalid) is removed. Running this file again resets the
-- admin password to the value below. To change the login or password, edit the two values
-- here and run this file again. The password is stored only as a bcrypt hash.
-- =====================================================================================
delete from admins where username <> 'gaddamvenur@gmail.com';

insert into admins(username, name, password_hash)
values ('gaddamvenur@gmail.com', 'Gaddam Venu', extensions.crypt('GaddamVenu@2026', extensions.gen_salt('bf', 8)))
on conflict (username) do update set password_hash = excluded.password_hash, name = excluded.name;

delete from sessions where role = 'admin';      -- everybody has to log in again

notify pgrst, 'reload schema';
