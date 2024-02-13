select tracefile from v$process where addr = (
 -- select paddr from v$session where sid = 163
 select paddr from v$session where sid = sys_context('userenv','sid')
)
/
