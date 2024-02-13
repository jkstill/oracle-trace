
Trace all sessions for scott that are running sqlplus, for 15 minutes

The tracefile identifier is set to the first 20 characters of the program logged in

trace-session.sh -u SCOTT -c sqlplus -s 900
