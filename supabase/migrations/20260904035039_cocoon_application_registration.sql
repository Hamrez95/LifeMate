-- CocoonMate is a first-class LifeMate application.
-- Registration does not enroll accounts, create pregnancy state, grant consent,
-- or issue commercial entitlement.

insert into ecosystem.applications(code, display_name, status)
values ('cocoonmate','CocoonMate','Active')
on conflict(code) do update set display_name=excluded.display_name;
