#!/bin/bash

set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

session_id=${1}

step="testing_${session_id}"

init_log ${step}

sql_dir=${PWD}/${session_id}

schema_name=tpch

function generate_queries()
{
	#going from 1 base to 0 base
	tpch_id=$((session_id))
	tpch_query_name="query_${tpch_id}.sql"
	query_id=100
	
	for p in $(seq 1 22); do
		query_id=$((query_id+1))
		q=$(printf %02d ${query_id})
		template_filename=query${p}.tpl
		start_position=""
		end_position=""
		query_number=$(grep begin $sql_dir/$tpch_query_name | head -n"$order" | tail -n1 | awk -F ' ' '{print $2}' | awk -F 'q' '{print $2}')
		start_position=$(grep -n "begin q""$query_number" $sql_dir/$tpch_query_name | awk -F ':' '{print $1}')
		end_position=$(grep -n "end q""$query_number" $sql_dir/$tpch_query_name | awk -F ':' '{print $1}')
		
		#for pos in $(grep -n ${template_filename} ${sql_dir}/${tpch_query_name} | awk -F ':' '{print $1}'); do
		#	if [ "${start_position}" == "" ]; then
		#		start_position=${pos}
		#	else
		#		end_position=${pos}
		#	fi
		#done

		#get the query number (the order of query execution) generated by dsqgen
		#file_id=$(sed -n ${start_position},${start_position}p ${sql_dir}/${tpch_query_name} | awk -F ' ' '{print $4}')
		#file_id=$((file_id+100))
		#filename=${file_id}.${BENCH_ROLE}.${q}.sql
		filename=${query_id}.${BENCH_ROLE}.${query_number}.sql
		#add explain analyze 
		echo "print \"set role ${BENCH_ROLE};\\n:EXPLAIN_ANALYZE\\n\" > ${sql_dir}/${filename}"
		printf "set role ${BENCH_ROLE};\nset search_path=$schema_name,public;\n:EXPLAIN_ANALYZE\n" > ${sql_dir}/${filename}

		echo "sed -n ${start_position},${end_position}p ${sql_dir}/${tpch_query_name} >> ${sql_dir}/${filename}"
		sed -n ${start_position},${end_position}p ${sql_dir}/${tpch_query_name} >> ${sql_dir}/${filename}
		query_id=$((query_id + 1))
		echo "Completed: ${sql_dir}/${filename}"
	done
	echo "rm -f ${sql_dir}/query_*.sql"
	rm -f ${sql_dir}/${tpch_query_name}
}

if [ "${RUN_QGEN}" = "true" ]; then
  generate_queries
fi

tuples="0"
for i in ${sql_dir}/*.sql; do
	start_log
	id=${i}
	schema_name=${session_id}
	table_name=$(basename ${i} | awk -F '.' '{print $3}')

	if [ "${EXPLAIN_ANALYZE}" == "false" ]; then
		log_time "psql -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="" -f ${i} | wc -l"
		tuples=$(psql -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="" -f ${i} | wc -l; exit ${PIPESTATUS[0]})
		tuples=$((tuples - 1))
	else
		myfilename=$(basename ${i})
		mylogfile="${TPC_DS_DIR}/log/${session_id}.${myfilename}.multi.explain_analyze.log"
		log_time "psql -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE=\"EXPLAIN ANALYZE\" -f ${i}"
		psql -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="EXPLAIN ANALYZE" -f ${i} > ${mylogfile}
		tuples="0"
	fi
		
	#remove the extra line that \timing adds
	print_log ${tuples}
done

end_step ${step}
