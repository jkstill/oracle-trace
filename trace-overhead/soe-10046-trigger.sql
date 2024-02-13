
-- soe-10046-trigger.sql
-- cause a trace for troubleshooting

create or replace trigger soe_10046_trg 
after logon on database 
declare
	v_sid integer;
	v_serial integer;
	v_username varchar2(30);
	v_machine varchar2(50);
begin

	select user into v_username from dual;

	-- put username of your choice here
	-- do not use SYS, as the audsid is 0 and will return
	-- multiple rows in the query for machine

	if v_username in ('SOE') then

		select distinct lower(machine) into v_machine
		from  v$session s
		where userenv('SESSIONID') = s.audsid;

		--dbms_output.put_line('MACHINE: ' || v_machine);
		if true
		--if (
			--v_machine like 'kr%' 
			--or v_machine like 'ordevdb01%'
			--or v_machine like 'rsyscimdev%'
			--or v_machine like 'rsysdevdb%'
		--)
		then
			select s.sid, s.serial#
			into  v_sid, v_serial
			from v$session s
			where userenv('SESSIONID') = s.audsid;

			declare
				i_level pls_integer := 12;
			begin

				execute immediate 'alter session set tracefile_identifier =' || '''' || 'SOE_LVL_' || to_char(i_level) || '''';

				sys.dbms_system.set_ev(v_sid, v_serial, 10046, 12, '');
				--sys.dbms_system.set_ev(v_sid, v_serial, 10046, 8, '');
			exception
			when others then
				null;
			end;
		end if;
	end if;
	
end;
/

show errors trigger soe_10046_trg 

