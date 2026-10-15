#!/bin/bash
# 12 جلسة بتحجز في نفس اللحظة عند نفس الحلاق/اليوم/الفترة بأرقام مختلفة + 6 جلسات بتحاول تحجز لنفس العميل
for i in $(seq 1 12); do
  ph=$(printf "0100001%04d" $i)
  su postgres -c "psql -q -d salon_test -c \"select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',false); set role authenticated; select admin_book_ticket('ع$i','$ph','00000000-0000-0000-0000-0000000000b1'::uuid,current_date+1,'morning',array[1]::bigint[])\"" >/dev/null 2>>conc_err.txt &
done
for i in $(seq 1 6); do
  su postgres -c "psql -q -d salon_test -c \"select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',false); set role authenticated; select admin_book_ticket('نفس','01000099999','00000000-0000-0000-0000-0000000000b2'::uuid,current_date+1,'morning',array[1]::bigint[])\"" >/dev/null 2>>conc_err.txt &
done
wait
