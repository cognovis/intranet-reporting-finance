-- upgrade-3.3.1.2.0-3.3.1.2.1.sql

SELECT acs_log__debug('/packages/intranet-reporting-finance/sql/postgresql/upgrade/upgrade-3.3.1.2.0-3.3.1.2.1.sql','');




---------------------------------------------------------
-- Finance - Project's Providers
--

create or replace function inline_0 ()
returns integer as '
declare
	-- Menu IDs
	v_menu			integer;
	v_main_menu 		integer;

	-- Groups
	v_employees		integer;
	v_accounting		integer;
	v_senman		integer;
	v_customers		integer;
	v_freelancers		integer;
	v_proman		integer;
	v_admins		integer;
	v_reg_users		integer;

	v_count			integer;
BEGIN
    select group_id into v_admins from groups where group_name = ''P/O Admins'';
    select group_id into v_senman from groups where group_name = ''Senior Managers'';
    select group_id into v_proman from groups where group_name = ''Project Managers'';
    select group_id into v_accounting from groups where group_name = ''Accounting'';
    select group_id into v_employees from groups where group_name = ''Employees'';

    select menu_id into v_main_menu from im_menus where label=''reporting-finance'';

    select count(*) into v_count from im_menus where label=''reporting-finance-projects-providers'';
    if v_count = 1 then return 0; end if;

    v_menu := im_menu__new (
	null,						-- p_menu_id
	''acs_object'',					-- object_type
	now(),						-- creation_date
	null,						-- creation_user
	null,						-- creation_ip
	null,						-- context_id
	''intranet-reporting-finance'',			-- package_name
	''reporting-finance-projects-providers'',	-- label
	''Finance Project Providers'',			-- name
	''/intranet-reporting-finance/finance-projects-providers'', -- url
	70,						-- sort_order
	v_main_menu,					-- parent_menu_id
	null						-- p_visible_tcl
    );

    PERFORM acs_permission__grant_permission(v_menu, v_admins, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_senman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_accounting, ''read'');

    return 0;
end;' language 'plpgsql';
select inline_0 ();
drop function inline_0 ();



