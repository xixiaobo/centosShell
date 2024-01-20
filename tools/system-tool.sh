#!/bin/bash
readonly SCRIPT_PATH=$(
  { cd "$(dirname "${BASH_SOURCE[0]}")" || {
    echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"
    exit 1
  }; }
  pwd
)
readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
readonly SCRIPT_PID=$$

readonly RUN_TIME=$(date "+%Y%m%d%H%M%S")
readonly CRONTAB_PATH="/etc/crontab"
###   全局通用方法
function log() {
  local options
  local msg
  while [[ $# -gt 0 ]]; do
        key="$1"
        if [[ $key == "-"* ]]; then
          options="$key"
        else
          # shellcheck disable=SC2034
          msg="$key"
        fi
        shift
    done
  eval "echo ${options} \"\${msg}\" >&2"
}
function help_fun() {
  cat  <<EOF >&2

usage: ${SCRIPT_NAME} [options...]
Options:
  -m  --menu        命令行形式执行菜单中的功能
  -s  --show-menu   显示菜单选项
  -w  --window      使用窗口交互模式
  -h  --help        查看命令使用方式

EOF
}
function prompt_input() {
  local prompt_message=$1
  local error_message=$2
  local default_value=$3
  local input
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    read -p "$prompt_message" -r input
    if [[ -z $input ]]; then
      if [[ -n $default_value ]]; then
          echo "$default_value"
          return 0
      else
        log  "${error_message:-"输入不能为空，请重新输入。"}"
      fi
    else
      echo "$input"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  log  "连续 3 次输入错误，退出脚本。"
  return 1
}
function format_port(){
  local port_hex="$1"
  echo "$((16#${port_hex}))"
}
function format_ip() {
  local ip_hex="$1"
  case ${#ip_hex} in
    8)
      echo "$((16#${ip_hex:6:2})).$((16#${ip_hex:4:2})).$((16#${ip_hex:2:2})).$((16#${ip_hex:0:2}))"
      return 0
    ;;
    32)
      if [[ "$ip_hex" == "00000000000000000000000000000000" ]]; then
          # 忽略 0.0.0.0
          echo "::"
          return 0
      fi
      if [[ "$ip_hex" == "00000000000000000000000001000000" ]]; then
          # 忽略 0.0.0.0
          echo "::1"
          return 0
      fi
      local ipv6_prefix="0000000000000000FFFF0000"
      if [[ "$ip_hex" == "${ipv6_prefix}"* ]]; then
          local ipv4_part=${ip_hex#"$ipv6_prefix"}
          # 忽略 0.0.0.0
          echo "::ffff:$(format_ip "${ipv4_part}")"
          return 0
      fi
      local ip_address=""
      for ((i=0; i < ${#ip_hex}; i+=4)); do
        local index="${ip_hex:$i:4}"
        if [ "${index}" == "0000" ]; then
          index="0"
        fi
        ip_address+="${index}:"
      done
      if [[ ${#ip_address} -gt 0 ]]; then
        echo "${ip_address:0:${#ip_address}-1}"
      fi
      return 0
    ;;
    *)
      echo "未知:${ip_hex}"
      return 0
      ;;
  esac
}

function compilation_parsing_value() {
    local txt=$1
    escape_slash_text="${txt//\\/\\\\}"
    escape_double_quotation_marks_text=${escape_slash_text//\"/\\\"}
    escape_dollar_sign_text=${escape_double_quotation_marks_text//\\\$/\\\\$}
    compile_text_to_value=$(eval "echo ${escape_dollar_sign_text}")
    escape_slash_value="${compile_text_to_value//\\/\\\\}"
    escape_double_quotation_marks_value=${escape_slash_value//\"/\\\"}
    escape_dollar_sign_value=${escape_double_quotation_marks_value//\\\$/\\\\$}
    echo "${escape_dollar_sign_value}"
}

###   功能方法

function release_linux_memory() {
  log "开始清理linux内存缓存..."
  sync
  echo 1 > /proc/sys/vm/drop_caches
  echo 2 > /proc/sys/vm/drop_caches
  echo 3 > /proc/sys/vm/drop_caches
  log "清理linux内存缓存完成"
}


function show_all_schedule_task() {
  local
  log -e "=======自定义定时任务列表======\n"
  if [ -r ${CRONTAB_PATH} ] && [ -w ${CRONTAB_PATH} ]; then
    grep -E "echo '.*\s+custom-task'" ${CRONTAB_PATH} | awk "match(\$0, /(.*) root bash -c \"echo '(.*)custom-task';(.*);echo 'run complete' \" >> (.+) 2>&1/, m) {gsub(/\\\\\"/, \"\\\"\", m[3]);printf \"任务名称: %s \n\t定时cron: %s \n\t运行命令: %s \n\t运行日志: %s\n\n\",m[2],m[1],m[3],m[4]}"
 else
    log "无法读写${CRONTAB_PATH}文件,无法进行定时任务开启操作"
  fi
}

function add_schedule_task() {
  local task_name
  local task_cmd
  local task_cron
  if [[ "$1" == "cmd" ]]; then
      task_name=$2
      task_cmd=$3
      task_cron=$4
      if [[ -z ${task_name} || -z ${task_cmd} || -z ${task_cron} ]]; then
          log "新增自定义定时任务命令参数有误， 必须为 ${SCRIPT_NAME} -m 3  [任务名称] [任务运行cmd] [任务定时cron表达式] [可选运行日志路径]"
          return 1
      fi
      local task_run_log
      if [[ -z $5 ]]; then
          task_run_log=/dev/null
      else
          task_run_log=$5
      fi
  else
    task_name=$(prompt_input "请输入自定义定时任务名称: " "任务名称不能为空") || return 1
    task_cmd=$(prompt_input "请输入要定时运行的命令: " "命令不能为空") || return 1
    task_run_log=$(prompt_input "请输入定时任务执行日志记录地址(默认为：/dev/null): " "" "/dev/null") || return 1
    task_cron=$(prompt_input "请输入自定义定时任务的cron表达式: ") || return 1
  fi
  IFS=" " read -r -a task_crons <<< "$task_cron"
  if [[ ! ${#task_crons[@]} -eq 5 ]]; then
      log "传入的cron表达式有误，请检查后再试"
      return 0
  fi
  local cron_task_name="${task_name} custom-task"
  local cron_task_run
  cron_task_run="$(compilation_parsing_value "${task_cmd}")"
  if [ -r ${CRONTAB_PATH} ] && [ -w ${CRONTAB_PATH} ]; then
    if grep -q "echo '${cron_task_name}'" ${CRONTAB_PATH}; then
      log "定时任务 task_name 已存在，不需要进行定时任务开启操作"
      return 0
    else
      log "写入定时任务${cron_task_name}:${RUN_TIME}"
      echo "${task_cron} root bash -c \"echo '${cron_task_name}';${cron_task_run} ;echo 'run complete' \" >> ${task_run_log} 2>&1" >>${CRONTAB_PATH} &&
       log "定时任务 ${cron_task_name} 开启成功" && return 0
      log "定时任务 ${cron_task_name} 开启失败"
    fi
  else
    log "无法读写${CRONTAB_PATH}文件,无法进行定时任务开启操作"
  fi
}

function delete_schedule_task() {
  local task_name
  if [[ "$1" == "cmd" ]]; then
    task_name=$2
    if [[ -z ${task_name} ]]; then
        log "删除自定义定时任务命令参数有误， 必须为 ${SCRIPT_NAME} -m 4  [任务名称]"
        return 1
    fi
  else
    task_name=$(prompt_input "请输入自定义定时任务名称: " "任务名称不能为空") || return 1
  fi
  local cron_task_name="${task_name} custom-task"
  if [ -r ${CRONTAB_PATH} ] && [ -w ${CRONTAB_PATH} ]; then
    if grep -q "echo '${cron_task_name}'" ${CRONTAB_PATH}; then
      sed -i "/${cron_task_name//\//\\/}/d" ${CRONTAB_PATH} &&
       log "定时任务 ${cron_task_name} 已关闭" && return 0
      log "定时任务 ${cron_task_name} 关闭失败"
    else
      log "定时任务 ${cron_task_name} 不存在，无法进行定时任务关闭操作"
      return 0
    fi
  else
    log "无法读写${CRONTAB_PATH}文件,无法进行定时任务关闭操作"
  fi
}

function clear_log(){
  local log_file
  local log_file_max_size
  local log_backs
  if [[ "$1" == "cmd" ]]; then
      log_file=$2
      if [[ -z ${log_file} ]]; then
          log "清理日志参数有误， 必须为 ${SCRIPT_NAME} -v 5 [文件路径] [文件大小限制，默认: 10，单位: M] [备份数量，为0时不备份，默认 0]"
          return 1
      fi
      log_file_max_size=$3
      if ! [[ -n $log_file_max_size && $log_file_max_size =~ ^[0-9]*(\.[0-9]+)?$ ]]; then
        log_file_max_size=10
      fi
      log_backs=$4
      if ! [[ -n $log_backs && $log_backs =~ ^[0-9]+$ ]]; then
        log_backs=0
      fi
  else
    log_file=$(prompt_input "请输入待清理的日志文件路径: " "日志的文件路径不能为空") || return 1
    log_file_max_size=$(prompt_input "请输入日志文件的大小限制，单位 M（默认: 10）: " "" "10") || return 1
    if ! [[ -n $log_file_max_size && $log_file_max_size =~ ^[0-9]*(\.[0-9]+)?$ ]]; then
      log "输入的日志文件大小限制异常，使用默认值 10"
      log_file_max_size=10
    fi
    log_backs=$(prompt_input "请输入日志文件的备份数量: " "" "0") || return 1
    if ! [[ -n $log_backs && $log_backs =~ ^[0-9]+$ ]]; then
      log "输入的日志文件的备份数量异常，使用默认值 0"
      log_backs=0
    fi
  fi
  local maxsize
  maxsize=$(awk "BEGIN { printf \"%.0f\", ${log_file_max_size} * 1024 * 1024 }")
  if  [[ -r "${log_file}" && ${maxsize} -ge 0 ]]; then
    local file_size
    # shellcheck disable=SC2012
    file_size="$(ls -l "${log_file}" | awk '{ print $5 }')"
    if [ "${file_size}" -gt "${maxsize}" ]; then
      if [[ "$log_backs" -gt 0 ]]; then
        local directory
        if command -v realpath &> /dev/null; then
          directory=$(realpath -m "$(dirname "${log_file}")")
        else
          directory="$(dirname "${log_file}")"
        fi
        if [ ! -d "${directory}/old-run-log" ]; then
         mkdir -p "${directory}/old-run-log"
        fi
        local count
        # shellcheck disable=SC2012
        count=$(ls -l "${directory}/old-run-log"/* 2>/dev/null | wc -l)
        if [ "${count}" -ge "$log_backs" ]; then
           # shellcheck disable=SC2012
           ls -lt "${directory}/old-run-log" | tail -n+$((log_backs+1)) | awk '{print $9}' | xargs -I {}  bash -c "echo \"clear back-up log: ${directory}/old-run-log/{}\"; rm \"${directory}/old-run-log/{}\""
        fi
        local backUpLogPath="${directory}/old-run-log/${RUN_TIME}.log"
        cp "${log_file}" "${directory}/old-run-log/${RUN_TIME}.log"
        if command -v tar > /dev/null 2>&1; then
         if tar -zcf "${directory}/old-run-log/${RUN_TIME}.tar.gz" -C "${directory}/old-run-log" "${RUN_TIME}.log"; then
           rm -rf "${directory}/old-run-log/${RUN_TIME}.log"
           backUpLogPath="${directory}/old-run-log/${RUN_TIME}.tar.gz"
         fi
        fi
        echo "back-up log: ${backUpLogPath}"
      fi
      echo "清空 ${log_file} 文件内容"
      cat /dev/null > "${log_file}"
    else
      echo "日志文件 ${log_file} 的大小 小于配置的 ${log_file_max_size} M 无需清理"
    fi
  else
    echo "日志文件 ${log_file} 不存在, 或配置文件的大小限制为0不限制日志大小,不做清理处理"
  fi
}


function show_all_tcp_info() {
  local split_fields
  local host
  local port
  # 定义每列的最大宽度
  local max_proto_width=4
  local max_address_width=22
  local max_uid_width=10
  local max_pid_width=6
  local max_program_name_width=20
  printf "%-*s  %-*s  %-*s  %-*s %-*s\n" \
        "$max_proto_width" "Proto" \
        "$max_address_width" "Local Address" \
        "$max_uid_width" "Uid" \
        "$max_pid_width" "Pid" \
        "$max_program_name_width" "Program name" >&2
  while read -r line; do
    IFS=" " read -r -a split_fields <<< "$line"
    proto="${split_fields[0]}"
    if [[ "${split_fields[1]}" == "local_address" ]]; then
        continue
    fi
    host="$(format_ip "${split_fields[1]}")"
    port="$(format_port "${split_fields[2]}")"
    socket="${split_fields[3]}"
    printf "%-*s  %-*s  %-*s  %-*s  %-*s\n" \
            "$max_proto_width" "${proto}" \
            "$max_address_width" "${host}:${port}" \
            "$max_uid_width" "${socket}" \
            "$max_pid_width" "${split_fields[4]}" \
            "$max_program_name_width" "$(awk '/^Name:/ { printf "%s", $2 }' "/proc/${split_fields[4]}/status")" >&2
  done < <(awk 'NR>1{
              proto = gensub(".*/", "", "g", FILENAME);
              split($2, fields, ":");
              host = fields[1];
              port = fields[2];
              uid = $10;
              if (!seen[port]) {
                  printf "%s %s %s %s\n", proto, host, port, uid;
                  seen[port] = 1;
              }
              }'  "/proc/net/tcp" "/proc/net/tcp6" | grep -v local_address |
              awk '{
                cmd = "ls -l /proc/*/fd/* 2>/dev/null | grep \"socket:\\[" $4 "\\]\"|awk  -F\"/\" \"{printf \\\"%s\\\",\\$(NF-2) }\" ";
                cmd | getline pid;
                close(cmd);
                printf "%s %s %s %s %s\n", $1, $2, $3, $4, pid;}')
}
function show_all_udp_info() {
  local split_fields
  local host
  local port
  # 定义每列的最大宽度
  local max_proto_width=4
  local max_address_width=22
  local max_uid_width=10
  local max_pid_width=6
  local max_program_name_width=20
  printf "%-*s  %-*s  %-*s  %-*s  %-*s\n" \
        "$max_proto_width" "Proto" \
        "$max_address_width" "Local Address" \
        "$max_uid_width" "Uid" \
        "$max_pid_width" "Pid" \
        "$max_program_name_width" "Program name" >&2
  while read -r line; do
    IFS=" " read -r -a split_fields <<< "$line"
    proto="${split_fields[0]}"
    if [[ "${split_fields[1]}" == "local_address" ]]; then
        continue
    fi
    host="$(format_ip "${split_fields[1]}")"
    port="$(format_port "${split_fields[2]}")"
    socket="${split_fields[3]}"
    printf "%-*s  %-*s  %-*s  %-*s  %-*s\n" \
            "$max_proto_width" "${proto}" \
            "$max_address_width" "${host}:${port}" \
            "$max_uid_width" "${socket}" \
            "$max_pid_width" "${split_fields[4]}" \
            "$max_program_name_width" "$(awk '/^Name:/ { printf "%s", $2 }' "/proc/${split_fields[4]}/status")" >&2
  done < <(awk 'NR>1{
              proto = gensub(".*/", "", "g", FILENAME);
              split($2, fields, ":");
              host = fields[1];
              port = fields[2];
              uid = $10;
              if (!seen[port]) {
                  printf "%s %s %s %s\n", proto, host, port, uid;
                  seen[port] = 1;
              }
              }'  "/proc/net/udp" "/proc/net/udp6" | grep -v local_address |
              awk '{
                cmd = "ls -l /proc/*/fd/* 2>/dev/null | grep \"socket:\\[" $4 "\\]\"|awk  -F\"/\" \"{printf \\\"%s\\\",\\$(NF-2) }\" ";
                cmd | getline pid;
                close(cmd);
                printf "%s %s %s %s %s\n", $1, $2, $3, $4, pid;}')
}

function show_process_occupying_deleted_files() {
  local file_descriptor
  local file_path
  local max_pid_width=6
  local max_file_descriptor_width=15
  local max_file_path_width=22
  printf "%-*s  %-*s  %-*s\n" \
          "$max_pid_width" "PID" \
          "$max_file_descriptor_width" "File Descriptor" \
          "$max_file_path_width" "File Path" >&2
  while read -r line; do
        IFS=" " read -r -a split_fields <<< "$line"
        file_descriptor="${split_fields[1]}"
        file_path="${split_fields[2]}"
        printf "%-*s  %-*s  %-*s\n" \
                "$max_pid_width" "${split_fields[0]}" \
                "$max_file_descriptor_width" "${file_descriptor}" \
                "$max_file_path_width" "${file_path}" >&2
      done < <(
      # shellcheck disable=SC2010
      ls -l /proc/*/fd/* 2>/dev/null |
                grep "(deleted)" |
                awk "match(\$0, /.* \/proc\/(.*)\/fd\/(.*) -> (.*)\(deleted\)/, m) {printf \"%s %s %s\n\",m[1],m[2],m[3]}")
}

function show_file_occupy_process() {
  local file_path
  if [[ "$1" == "cmd" ]]; then
    file_path=$2
    if [[ -z ${file_path} ]]; then
        log "查看文件占用进程命令参数有误， 必须为 ${SCRIPT_NAME} -m 9  [文件地址]"
        return 1
    fi
  else
    file_path=$(prompt_input "请输入自定义定时任务名称: " "任务名称不能为空") || return 1
  fi
  if [[ ! -f ${file_path} ]]; then
      log "传入的文件地址有误，文件不存在"
      return 0
  fi
  local real_file_path
  local file_name
  real_file_path="$(readlink -f "${file_path}")"
  file_name="$(basename "${real_file_path}")"
  log "文件 ${file_path} 进程占用情况如下: "
  local real_occupy_file_path
  local max_pid_width=6
  local max_file_descriptor_width=15
  printf "\t%-*s  %-*s\n" \
          "$max_pid_width" "PID" \
          "$max_file_descriptor_width" "File Descriptor"  >&2
  while read -r line; do
    IFS=" " read -r -a split_fields <<< "$line"
    real_occupy_file_path="$(readlink -f "/proc/${split_fields[0]}/fd/${split_fields[1]}")"
    if [[ "${real_occupy_file_path}" == "${real_file_path}" ]]; then
      printf "\t%-*s  %-*s\n" \
              "$max_pid_width" "${split_fields[0]}" \
              "$max_file_descriptor_width" "${split_fields[1]}" >&2
    fi
  done < <(
  # shellcheck disable=SC2010
  ls -l /proc/*/fd/* 2>/dev/null |
            grep "/${file_name}" |
            awk "match(\$0, /.* \/proc\/(.*)\/fd\/(.*) -> (.*)/, m) {printf \"%s %s\n\",m[1],m[2]}")
  log -e "\n"
}



function show_process_info() {
    local process_id
    if [[ "$1" == "cmd" ]]; then
      process_id=$2
      if [[ -z ${process_id} ]]; then
          log "查看进程相关信息命令参数有误， 必须为 ${SCRIPT_NAME} -m 10  [进程id]"
          return 1
      fi
    else
      local choice_msg
      local pids
      while true; do
          log  ""
          log  "请选择指定进程方式: "
          log  "1. 通过进程名称获取"
          log  "2. 通过端口获取称获取"
          log  "3. 直接指定进程id"
          local choice
          choice=$(prompt_input "请输入选项数字（0-3）: ") || return 1
          case $choice in
            1)
              local processName
              processName=$(prompt_input "请输入进程名称或关键字: ") || return 1
              pids=$(grep -lE "${processName}" /proc/[0-9]*/cmdline 2>/dev/null | xargs -I {} ls -l {} 2>/dev/null   | awk -F'/' '{print $(NF-1)}' |grep -v "${SCRIPT_PID}")
              choice_msg="进程名称或关键字:${processName}"
              break
              ;;
            2)
              local processPort
              local hex_process_port
              processPort=$(prompt_input "请输入端口: ") || return 1
              hex_process_port=$(printf "%04X" "${processPort}")
              choice_msg="进程端口:${processPort}"
              local uid
              uid="$()"
              if [[ -z ${uid} ]]; then
                  break
              fi
              # shellcheck disable=SC2010
              pids=$(grep ":${hex_process_port} " "/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6"| head -n 1 |awk '{print  $11}'| xargs -I {} bash -c "ls -l /proc/*/fd/* 2>/dev/null | grep \"socket:\[{}\]\" | awk -F'/' '{print \$(NF-2)}'")
              break
              ;;
            3)
              break
              ;;
            *)
              log  "无效的选项，请重新输入。"
              ;;
          esac
        done
      if [[ -n ${choice_msg} ]]; then
        if [[ -z ${pids} ]]; then
          log  "根据 ${choice_msg} 没有找到进程"
          return 0
        fi
        log  "根据 ${choice_msg} 获取到以下进程id"
        for pid in ${pids}; do
          if test -r "/proc/${pid}/cmdline"; then
            log -e "pid: ${pid}\t-\t$(tr -s '\0' ' ' < "/proc/${pid}/cmdline")\n"
          else
            log -e "pid: ${pid}\t-\t无法找到进程详情文件\n"
          fi
        done
        process_id=$(prompt_input "请输入上面要查询的pid: ") || return 1
        local found=false
        for pid in ${pids}; do
            if [[ "${pid}" == "${process_id}" ]]; then
                found=true
                break
            fi
        done
        if ! ${found}; then
            echo "要查询的值不在列表中无法进行详情查询"
            return 0
        fi
      else
        process_id=$(prompt_input "请输入要查询的pid: ") || return 1
        if [[ ! -r "/proc/${process_id}/cmdline" ]]; then
          log -e "pid: ${process_id}\t-\t无法找到进程详情文件\n"
          return 0
        fi
      fi
    fi

    local process_comm process_parent_pid process_utime process_stime process_priority process_num_threads
    local process_starttime process_processor process_rt_priority
    if [[ -f "/proc/${process_id}/stat" ]]; then
      IFS=" " read -r _ process_comm _ process_parent_pid _ _ _ _ _ _ _ \
                    _ _ process_utime process_stime _ _ process_priority _ process_num_threads _ \
                    process_starttime _ _ _ _ _ _ _ _ _ \
                    _ _ _ _ _ _ _ process_processor process_rt_priority \
                    _ _ _ _ < "/proc/${process_id}/stat"
    fi
    # 获取系统的总CPU时间，并计算cpu利用率
    local total_cpu
    total_cpu=$(< /proc/stat head -n 1 |awk '{printf "%d",$2+$3+$4+$5+$6+$7+$8}')
    local total_time=$((process_utime + process_stime))
    local cpu_usage
    cpu_usage=$(awk -v total_cpu="$total_cpu" -v total_time="$total_time" 'BEGIN { printf "%.2f", 100 * total_time / total_cpu }')
    local user_hz
    user_hz=$(getconf CLK_TCK)
    declare -A status_data;
    while IFS=":" read -r key value; do
        key=$(echo "$key" | awk '{$1=$1;print}')
        value=$(echo "$value" | awk '{$1=$1;print}')
        status_data["${key}"]="${value}"
    done < "/proc/${process_id}/status" ;


    declare -A io_data;
    while IFS=":" read -r key value; do
        key=$(echo "$key" | awk '{$1=$1;print}')
        value=$(echo "$value" | awk '{$1=$1;print}')
        io_data["${key}"]="${value}"
    done < "/proc/${process_id}/io" ;


    local max_key_width=10
    local max_value_width=22
    local total_memory
    total_memory=$(grep -w "MemTotal" "/proc/meminfo" | awk '{ print $2 }')

    local memory_usage
    memory_usage="$(awk -v vm_rss="${status_data["VmRSS"]}" -v total_memory="$total_memory" 'BEGIN {printf "%.2f", (vm_rss / total_memory) * 100}')"

    # 获取进程所属用户的名称
    local user username
    user=$(echo "${status_data["Uid"]}"| awk '{ printf "%s", $2 }')
    username=$(getent passwd "$user" | cut -d ':' -f 1)

    # 获取进程所属组的名称
    local group group_name
    group=$(echo "${status_data["Gid"]}"| awk '{ printf "%s", $2 }')
    group_name=$(getent group "$group" | cut -d ':' -f 1)

    local system_up_time
    system_up_time="$(grep btime /proc/stat | awk '{print $2}')"

    printf "\t%-*s %-*s\n" "$max_key_width" "进程ID                     :" "$max_value_width" "${process_id}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程命令名称               :" "$max_value_width" "${process_comm}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程状态                   :" "$max_value_width" "${status_data["State"]}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程启动时间               :" "$max_value_width" "$(awk -v system_up_time="${system_up_time}" -v starttime="$process_starttime" '{printf "%.0f\n",system_up_time+starttime/100}' | xargs -I {} date -d "1970-1-1 UTC {} seconds")" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程运行时长(秒)           :" "$max_value_width" "$(awk -v starttime="$process_starttime" -v user_hz="$user_hz" 'BEGIN {printf "%.2f", (starttime / user_hz) * 100}')" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "父进程ID                   :" "$max_value_width" "${process_parent_pid}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程所属用户               :" "$max_value_width" "${username}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程所属分组               :" "$max_value_width" "${group_name}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程工作目录               :" "$max_value_width" "$(readlink -f "/proc/${process_id}/cwd")" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程命令行                 :" "$max_value_width" "$(tr -s '\0' ' ' < "/proc/${process_id}/cmdline")" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程优先级                 :" "$max_value_width" "${process_priority}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程实时优先级             :" "$max_value_width" "${process_rt_priority}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程打开的文件描述符的数量 :" "$max_value_width" "${status_data["FDSize"]}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程使用CPU编号            :" "$max_value_width" "${process_processor}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程线程数                 :" "$max_value_width" "${process_num_threads}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程虚拟内存大小           :" "$max_value_width" "${status_data["VmSize"]}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程常驻内存大小           :" "$max_value_width" "${status_data["VmRSS"]}" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程内存利用率             :" "$max_value_width" "${memory_usage} %" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程cpu利用率              :" "$max_value_width" "${cpu_usage} %" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程磁盘读取字节数         :" "$max_value_width" "${io_data["read_bytes"]} %" >&2
    printf "\t%-*s %-*s\n" "$max_key_width" "进程磁盘写入字节数         :" "$max_value_width" "${io_data["write_bytes"]} %" >&2


    ## 分析进程占用文件和端口
    local file_list=()
    local socket_uid_list=""
    while read -r line; do
      IFS=" " read -r -a split_fields <<< "$line"
      file_descriptor="${split_fields[0]}"
      link_path="${split_fields[1]}"
      case $link_path in
        socket:[*)
          if [[ $link_path =~ \[([0-9]+)\] ]]; then
            if [[ -z ${socket_uid_list} ]]; then
                socket_uid_list+="${BASH_REMATCH[1]}"
            else
                socket_uid_list+=",${BASH_REMATCH[1]}"
            fi
          fi
          ;;
        pipe:[*|anon_inode:*) break ;;
        *)
          real_occupy_file_path="$(readlink -f "/proc/${process_id}/fd/${file_descriptor}")"
          file_list+=("${file_descriptor} ${real_occupy_file_path}")
          ;;
      esac
    done < <(
    # shellcheck disable=SC2012
    ls -l "/proc/${process_id}/fd"/* 2>/dev/null | awk "match(\$0, /.* \/proc\/.*\/fd\/(.*) -> (.*)/, m) {printf \"%s %s\n\",m[1],m[2]}")

    if [[ -z ${socket_uid_list} ]]; then
      log -e "\n进程 ${process_id} 没有占用网络端口\n"
    else
      log -e "\n进程 ${process_id} 占用网络端口情况如下:"
      local max_proto_width=4
      local max_address_width=22
      printf "\t%-*s  %-*s\n" \
            "$max_proto_width" "Proto" \
            "$max_address_width" "Local Address" >&2
      while read -r line; do
          IFS=" " read -r -a split_fields <<< "$line"
          proto="${split_fields[0]}"
          if [[ "${split_fields[1]}" == "local_address" ]]; then
              continue
          fi
          host="$(format_ip "${split_fields[1]}")"
          port="$(format_port "${split_fields[2]}")"
          printf "\t%-*s  %-*s\n" \
                  "$max_proto_width" "${proto}" \
                  "$max_address_width" "${host}:${port}"  >&2
      done < <(awk -v uid_list="${socket_uid_list}" '
                 BEGIN {
                   FS=" "
                   split(uid_list, uidArr, ",")
                   for (i in uidArr) {
                     uidSet[uidArr[i]] = 1
                   }
                 }
                 NR>1 && $10 in uidSet {
                   proto = gensub(".*/", "", "g", FILENAME);
                   split($2, fields, ":")
                   host = fields[1]
                   port = fields[2]
                    if (!seen[port]) {
                        printf "%s %s %s\n",proto, host, port;
                        seen[port] = 1;
                    }
                 }
               ' "/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6" )
    fi
    if [[ ${#file_list} -gt 0 ]]; then
      log -e "\n进程 ${process_id} 占用文件情况如下:"
      local max_file_descriptor_width=16
      local max_file_path_width=22
      printf "\t%-*s  %-*s\n" \
              "$max_file_descriptor_width" "File Descriptor" \
              "$max_file_path_width" "File Path" >&2
      for file in "${file_list[@]}"; do
        IFS=" " read -r -a split_fields <<< "$file"
        printf "\t%-*s  %-*s\n" \
              "$max_file_descriptor_width" "${split_fields[0]}" \
              "$max_file_path_width" "${split_fields[1]}" >&2
      done
    else
      log -e "\n进程 ${process_id} 没有占用文件\n"
    fi

}


function show_menu() {
    log  "=========$(uname -o) 系统工具============="
    log  " 1. 清除内存缓存"
    log  " 2. 查看所有自定义定时任务"
    log  " 3. 新增自定义定时任务"
    log  " 4. 删除自定义定时任务"
    log  " 5. 清理日志根据限制大小"
    log  " 6. 查看所有占用tcp端口"
    log  " 7. 查看所有占用udp端口"
    log  " 8. 查看所有已删除任占用文件"
    log  " 9. 查看文件占用进程"
    log  "10. 查看进程相关信息"
    log  " 0. 退出查询工具"
    log  "=============================="
}

function choice_menu() {
  local choice=$1
  shift
  case $choice in
    0)
      log  "退出 $(uname -o) 系统工具..."
      return 1
      ;;
    1)
      release_linux_memory
      ;;
    2)
      log -e "$(show_all_schedule_task)"
      ;;
    3)
      add_schedule_task "$@"
      ;;
    4)
      delete_schedule_task "$@"
      ;;
    5)
      clear_log "$@"
      ;;
    6)
      show_all_tcp_info
      ;;
    7)
      show_all_udp_info
      ;;
    8)
      show_process_occupying_deleted_files
      ;;
    9)
      show_file_occupy_process "$@"
      ;;
    10)
      show_process_info "$@"
      ;;
    *)
      log  "ERROR: 无效的选择。"
      return 0
      ;;
  esac
}

function window_menu() {
  log -en "\033[1;1H"
  log -en "\033[2J"
  log -en "\033[1;1H"
  show_menu
  local choice
  choice=$(prompt_input "请选择功能（输入菜单编号）: " "输入为空，请按照菜单编号输入！") || return 1
  choice_menu "${choice}" "window" || return 1
  log -ne "\n继续请输入任意字符或直接回车，退出请按0或esc: "
  # shellcheck disable=SC2162
  read -n 1 key
  # 判断用户按键
  if [[ "$key" == $'\e' || "$key" == "0" ]]; then
    echo -e "\n"
    return 1
  else
    return 0
  fi
}

function window() {
  log  "欢迎使用 ${SCRIPT_NAME} 脚本工具"
  while true; do
    if ! window_menu ; then
      break
    fi
    sleep 1
  done
}

if [[ $# -gt 0 && -n "$1" ]]; then
  key="$1"
  case $key in
    -m|--menu)
      choice=$2
        if [[ -z ${choice} ]]; then
            log "使用命令模式下必须传递要执行的方法菜单编号"
            exit 1
        fi
        shift
        shift
        choice_menu "${choice}" "cmd" "$@" || exit 1
        exit 0
      ;;
    -s|--show-menu)
      show_menu
      exit 0
      ;;
    -w|--window)
      window
      exit 0
      ;;
    -h|--help)
        help_fun
        exit 0
        ;;
    *)
      log "${SCRIPT_NAME}: 命令相关详情，请使用 '${SCRIPT_NAME} --help' 查看"
      exit 0
      ;;
  esac
else
  window
fi

