

find /mnt/zips/tmp/pythian | grep -e '\.trc$'                            | xargs grep -E 'value="' | grep -E '202[0123]' | cut -f1 -d: | sort -u | tee tracefiles-with-date-bind-values.log
find /mnt/pythian-laptop/users/jaredstill/Documents  | grep -e '\.trc$'  | xargs grep -E 'value="' | grep -E '202[0123]' | cut -f1 -d: | sort -u | tee -a tracefiles-with-date-bind-values.log


