#!/bin/bash
########################################################################################
##  此脚本为项目进程管理脚本，禁止随意修改变动，如需修改请联系项目负责人
##  脚本核心读取的配置文件有： init_xxx.txt - 初始化命令文件，shell脚本格式编写
##                         config/*.conf - 所有工作进程配置文件
##  配置描述：
##     init_xxx.txt：
##        1、可以在所有工作进程前执行文本内的所有命令，进行统一处理
##        2、可以统一配置全局环境变量，注意配置的环境变量只在脚本运行中生效，不会影响的服务器以及连接会话
##        3、可以通过设置 config_dir 变量去指定所有项目配置文件的存放位置
##        4、可以通过设置 log_directory 变量去指定全局项目默认运行日志的存放位置
##        5、可以通过设置 clear_log_file_cron 变量去指定全局项目默认定时清理项目运行日志任务的cron表达式
##    config/*.conf：
##        1、所有项目配置的开头必须是  [work:${workName}]  其中 ${workName} 是项目的名称
##        2、所有配置都是 ${key]=${value} 的格式，value前后不要出现空格、制表符、双引号或单引号
##        3、以下为项目的配置项：
##                 runCmd           - 核心配置，必须配置的参数，用于启动项目的shell命令
##                 directory        - 项目工作目录，在执行命令前会进入到指定目录后执行，如果没有配置就会在项目的运行日志目录直接执行
##                 priority         - 项目启动优先级，数值越大优先级越高，默认为0
##                 user             - 项目操作命令运行用户，默认为root用户
##                 processCheckType - 查询项目进程的方法类型，默认值为 name，可选 port
##                 processName      - 查询项目进程的名称，默认是启动shell命令，如果 daemon 配置为 off 则默认是项目名称
##                 processPort      - 查询项目进程的端口，如果 processCheckType 配置为 port 则必须指定端口
##                 daemon           - 启动shell命令是否后台静默运行，默认是 on 开启状态，注意如果配置成 off 关闭状态，请确保启动命令不会阻塞进程，否则可能会导致脚本卡在当前项目操作无法进行后续操作
##                 startsecs        - 检查项目是否启动获取pid前等待秒数，默认是3s
##                 logFile          - 指定运行日志路径,默认是 ${log_directory}/${workName}/run.log
##                 logFileMaxSize   - 指定运行日志文件记录大小限制，单位为Mb，默认值为：10，如果超过限制大小就会清空日志文件，开启备份会在备份后清空，设置为0，则不限制大小
##                 logBacks         - 备份保留运行日志个数，默认为0，当大于0的时候开启备份
##                 stopCmd          - 项目停止命令，如果不设置默认通过pid进行kill操作
##                 restartCmd       - 项目重启命令，如果不设置默认先进行项目停止操作再进行项目启动操作
########################################################################################

#### 脚本初始化 BEGIN ####
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
readonly SCRIPT_PARENT_PATH=$(dirname "$SCRIPT_PATH")
readonly ARCH=$(uname -m)

cd "${SCRIPT_PATH}" || { echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"; exit 1; }

if test -r "${SCRIPT_PATH}/init_${SCRIPT_NAME%\.*}.txt"; then
  # 读取文件内容
  file_content=$(cat "${SCRIPT_PATH}/init_${SCRIPT_NAME%\.*}.txt")
  # 执行文件中的Shell命令
  eval "$file_content"
else
  echo -e "\033[33m 请注，没有检测到配置初始化文件 init_${SCRIPT_NAME%\.*}.txt \033[0m"
fi
if [[ -z "${clear_log_file_cron}" ]]; then
    clear_log_file_cron="0 1 * * *"
fi

if [[ -z "${log_directory}" ]]; then
    log_directory="${SCRIPT_PARENT_PATH}/logs"
fi

if [[ -z "${config_dir}" ]]; then
  config_dir="${SCRIPT_PATH}/config/"
fi
mkdir -p "${config_dir}"
#### 脚本初始化 END ####

#### 脚本方法定义 BEGIN ####
# Function to read configuration files
function log_error() {
  if [[ -n "$1" ]]; then
      echo "${SCRIPT_NAME}: $1"  >&2
  fi
  echo "${SCRIPT_NAME}: 命令相关详情，请使用 '${SCRIPT_NAME} help' 查看"  >&2
  exit 1
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
generate_readonly_template() {
    cat > "$1" <<EOF
# 只读配置模板，work:项目名称
[work:projectName]
# 核心配置，必须配置的参数，用于启动项目的shell命令
runCmd=echo "project run"
# 项目工作目录，在执行命令前会进入到指定目录后执行，如果没有配置就会在项目的运行日志目录直接执行
# directory=
# 项目启动优先级，数值越大优先级越高，默认为0
# priority=0
# 项目操作命令运行用户，默认为root用户
# user=root
# 查询项目进程的方法类型，默认值为 name，可选 port
# processCheckType=name
# 查询项目进程的名称，默认是启动shell命令，如果 daemon 配置为 off 则默认是项目名称
# processName=
# 查询项目进程的端口，如果 processCheckType 配置为 port 则必须指定端口
# processPort=
# 启动shell命令是否后台静默运行，默认是 on 开启状态
# daemon=on
# 检查项目是否启动获取pid前等待秒数，默认是3s
# startsecs=3
# 指定运行日志路径,默认是: ${log_directory}/项目名称/run.log
# logFile=
# 指定运行日志文件记录大小限制，单位为Mb，默认值为：10，如果超过限制大小就会清空日志文件，开启备份会在备份后清空，设置为0，则不限制大小
# logFileMaxSize=10
# 备份保留运行日志个数，默认为0，当大于0的时候开启备份
# logBacks=0
# 项目停止命令，如果不设置默认通过pid进行kill操作
# stopCmd=
# 项目重启命令，如果不设置默认先进行项目停止操作再进行项目启动操作
# restartCmd=
EOF
}

sort_work_by_priority() {
  local works=()
  for key in "${!config[@]}"; do
     if [[ $key =~ ^([^|]+)\|configPath$ ]]; then
         work="${BASH_REMATCH[1]}"
         priority="$(get_config_value "${work}" "priority" "0")"
         if ! [[ -n $priority && "$priority" =~ ^[0-9]+$ ]]; then
            priority="0"
         fi
         works+=("$priority|${work}")
     fi
  done
  if [ ${#works[@]} -gt 0 ]; then
    IFS=$'\n'
    while read -r line; do works_sorted+=("$line"); done < <(sort -t'|' -rnk1 <<<"${works[*]}")
    unset IFS
  fi

}



# Function to read a single configuration file
read_config_file() {
  local file="$1"
  local section=""
  local key=""
  local txt=""
  while IFS= read -r line; do
      if [[ "$line" =~ ^\s*# ]]; then
          continue
      fi
      if [[ "$line" =~ ^\[work:(.*)\]$ ]]; then
          section="${BASH_REMATCH[1]}"
          if [[ "${config["$section|configPath"]}" ]]; then
             echo -e "\033[31m 项目 ${section} 配置出现多个配置，请在以下配置文件中检查配置！ \033[0m" >&2
             echo -e "\033[31m \t\t - 1: ${config["$section|configPath"]} \033[0m" >&2
             echo -e "\033[31m \t\t - 2: ${file} \033[0m" >&2
             exit 1
          fi
          config["$section|configPath"]="$file"
      elif [[ "$line" =~ (.*)=(.*) ]]; then
        if [ -n "${section}" ]; then
          IFS="=" read -r key txt <<< "$line"
          config["$section|$key"]="$(compilation_parsing_value "${txt}")"
        fi
      fi
  done < "$file"
}


read_config_files() {
  if [[ ! -f "${config_dir}readonly.conf.template" ]]; then
    generate_readonly_template "${config_dir}readonly.conf.template"
    chmod 444 "${config_dir}readonly.conf.template"
  fi
  for file in "$config_dir"*.conf; do
      if [[ -f "$file" ]]; then
          read_config_file "$file"
      fi
  done
  sort_work_by_priority
}


# Function to get configuration value
get_config_value() {
  local work="$1"
  local key="$2"
  local default_value="$3"
  local config_key="$work|$key"
  local value="${config[$config_key]}"

  if [[ -n "$value" ]]; then
      echo "$value"
  else
      if [[ -n "$default_value" ]]; then
          echo "$default_value"
      fi
  fi
}
get_work_process_name() {
  local work="$1"
  local process_name
  process_name="$(get_config_value "${work}" "processName")"
  if [[ -z "$process_name" ]]; then
      local daemon
      daemon="$(get_config_value "${work}" "daemon" "on")"
      if [[ "$daemon" == "on" ]]; then
          process_name="$(get_config_value "${work}" "runCmd")"
      else
          process_name="${work}"
      fi
  fi
  echo "${process_name}"
}
sleep_by_startsecs() {
  local work="$1"
  local startsecs
  startsecs="$(get_config_value "${work}" "startsecs" "3")"
  if ! [[ -n $startsecs && "$startsecs" =~ ^[0-9]+$ ]]; then
    startsecs="3"
  fi
  sleep ${startsecs}
}

clear_log(){
  local work="$1"
  local work_log_file
  work_log_file="$(get_config_value "${work}" "logFile" "${log_directory}/${work}/run.log")"
  local work_log_directory
  if command -v realpath &> /dev/null; then
      work_log_directory=$(realpath -m "$(dirname "${work_log_file}")")
    else
      work_log_directory="$(dirname "${work_log_file}")"
    fi
  local work_log_max_size
  work_log_max_size="$(get_config_value "${work}" "logFileMaxSize" "10")"
  mkdir -p "$work_log_directory"
  if ! [[ -n $work_log_max_size && $work_log_max_size =~ ^[0-9]*(\.[0-9]+)?$ ]]; then
    # 如果不是大于或等于0的数字，则默认赋值为10
    work_log_max_size=10
  fi
  local maxsize
  maxsize=$(awk "BEGIN { printf \"%.0f\", ${work_log_max_size} * 1024 * 1024 }")
  if [[ -r "${work_log_file}" && ${maxsize} -ge 0 ]]; then
    local file_size
    # shellcheck disable=SC2012
    file_size="$(ls -l "${work_log_file}" | awk '{ print $5 }')"
    if [ "${file_size}" -gt "${maxsize}" ]; then
      local work_log_backs
      work_log_backs="$(get_config_value "${work}" "logBacks" "0")"
      if ! [[ -n $work_log_backs && $work_log_backs =~ ^[0-9]+$ ]]; then
        work_log_backs=0
      fi
      if [[ "$work_log_backs" -gt "0" ]]; then
        if [ ! -d "${work_log_directory}/old-run-log" ]; then
          mkdir -p "${work_log_directory}/old-run-log"
        fi
        local count
        # shellcheck disable=SC2012
        count=$(ls -l "${work_log_directory}/old-run-log"/* 2>/dev/null | wc -l)
        if [ "${count}" -ge "$work_log_backs" ]; then
          # shellcheck disable=SC2012
          ls -lt "${work_log_directory}/old-run-log" | tail -n+$((work_log_backs+1)) | awk '{print $9}' | xargs -I {} bash -c "echo \"clear ${work} back-up log: ${work_log_directory}/old-run-log/{}\"; rm \"${work_log_directory}/old-run-log/{}\""
        fi
        local backUpLogPath="${work_log_directory}/old-run-log/${RUN_TIME}.log"
        cp "${work_log_file}" "${work_log_directory}/old-run-log/${RUN_TIME}.log"
        if command -v tar > /dev/null 2>&1; then
          if tar -zcf "${work_log_directory}/old-run-log/${RUN_TIME}.tar.gz" -C "${work_log_directory}/old-run-log" "${RUN_TIME}.log"; then
            rm -rf "${work_log_directory}/old-run-log/${RUN_TIME}.log"
            backUpLogPath="${work_log_directory}/old-run-log/${RUN_TIME}.tar.gz"
          fi
        fi
        echo "${work} back-up log: ${backUpLogPath}"
      fi
      echo "清空 项目 ${work} 的 ${work_log_file} 文件内容"
      cat /dev/null > "${work_log_file}"
    else
      echo "项目 ${work} 的日志文件 ${work_log_file} 的大小 小于配置的 ${work_log_max_size} M 无需清理"
    fi
  else
    echo "项目 ${work} 的 日志文件 ${work_log_file} 不存在, 或配置 logFileMaxSize 为0不限制日志大小,不做清理处理"
  fi
}

enable_schedule_task() {
  local shellFilePath=${SCRIPT_PATH}/${SCRIPT_NAME}
  local taskName="${SCRIPT_NAME}-clear-log task"
  if [ -r /etc/crontab ] && [ -w /etc/crontab ]; then
    if grep -q "${taskName}" /etc/crontab; then
      echo "定时任务 ${taskName} 已存在，不需要进行定时任务开启操作"
    else
      IFS=" " read -r -a clear_log_file_crons <<< "$clear_log_file_cron"
      if [[ ! ${#clear_log_file_crons[@]} -eq 5 ]]; then
          echo "全局配置中的clear_log_file_cron表达式有误，使用默认配置"
          clear_log_file_cron="0 1 * * *"
      fi
      echo "写入定时任务${taskName}:${RUN_TIME}"
      echo "${clear_log_file_cron} root bash -c \"echo '${taskName}';${shellFilePath} clear-log\" >> ${log_directory}/${SCRIPT_NAME%\.*}-clear-log-crontab.log 2>&1" >>/etc/crontab && echo "定时任务 ${taskName} 开启成功"
    fi
  else
    echo "无法读写/etc/crontab文件,无法进行定时任务开启操作"
  fi
}

disable_schedule_task() {
  local taskName="${SCRIPT_NAME}-clear-log task"
  if [ -r /etc/crontab ] && [ -w /etc/crontab ]; then
    if grep -q "${taskName}" /etc/crontab; then
      sed -i "/${taskName//\//\\/}/d" /etc/crontab &&
      echo -e "\033[31m 定时任务 ${taskName} 已关闭 \033[0m"
    else
      echo "定时任务 ${taskName} 不存在，无法进行定时任务关闭操作"
    fi
  else
    echo "无法读写/etc/crontab文件,无法进行定时任务关闭操作"
  fi
}


check_pid() {
  local work="$1"
   [[ -z ${work} ]] && { echo -e "\033[32m 查询项目进程id 不能传递为空的项目名称 \033[0m" ; return; }
  local startsecs
  local processCheckType
  processCheckType="$(get_config_value "${work}" "processCheckType" "name")"
  local pid
  if [[ "${processCheckType}" == "name" ]]; then
    local processName
    processName="$(get_work_process_name "${work}")"
    [[ -z ${processName} ]] && { echo -e "\033[32m 查询项目进程id 项目 ${work} 的进程名称获取为空 无法进行进程检测  \033[0m" ; return; }
    pid=$(grep -lE "${processName}" /proc/[0-9]*/cmdline 2>/dev/null | xargs -I {} ls -l {} 2>/dev/null   | awk -F'/' '{print $(NF-1)}'|grep -v "${SCRIPT_PID}")
    echo "${pid}"
  else
    local processPort
    processPort="$(get_config_value "${work}" "processPort")"
    if [[ -n "${processPort}" ]]; then
      if command -v netstat >/dev/null 2>&1; then
        pid=$(netstat -nlp | grep ":$processPort " | awk '{print $7}' | sed 's/[^0-9]//g')
      else
        local hex_process_port
        hex_process_port=$(printf "%04X" "${processPort}")
        local uid
        uid="$(grep ":${hex_process_port} " "/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6"| head -n 1 |awk '{print  $11}')"
        if [[ -n ${uid} ]]; then
          # shellcheck disable=SC2010
          pid=$(ls -l /proc/*/fd/* 2>/dev/null | grep "socket:\[$uid\]" | awk -F'/' '{print $(NF-2)}')
        fi
      fi
      echo "${pid}"
    else
      echo -e "\033[31m 项目 ${work} 配置进程检测类型是端口监测，但是配置配置 processPort 无法进行进程检测 \033[0m" >&2
    fi
  fi
}
start_project() {
  local work="$1"
  [[ -z ${work} ]] && { echo -e "\033[32m 启动项目 不能传递为空的项目名称 \033[0m" ; return; }
  local PID
  PID="$(check_pid "${work}")"
  [[ -n ${PID} ]] && { echo -e "启动项目：\033[33m ${work} 正在运行 !进程PID为 ${PID} \033[0m" ; return; }
  local start_cmd
  local user
  local work_log_file
  local work_log_directory
  start_cmd="$(get_config_value "${work}" "runCmd")"
  user="$(get_config_value "${work}" "user" "root")"
  work_log_file="$(get_config_value "${work}" "logFile" "${log_directory}/${work}/run.log")"
  if command -v realpath &> /dev/null; then
    work_log_directory=$(realpath -m "$(dirname "${work_log_file}")")
  else
    work_log_directory="$(dirname "${work_log_file}")"
  fi
  mkdir -p "$work_log_directory"
  clear_log "${work}"
  local work_directory
  work_directory="$(get_config_value "${work}" "directory" "${work_log_directory}")"
  if [[ -n "$work_directory" ]]; then
     cd "$work_directory" || { echo -e "\033[31m ${work} 没有找到工作目录: $work_directory \033[0m"; return; }
  fi
  local daemon
  daemon="$(get_config_value "${work}" "daemon" "on")"
  if [[ "$daemon" == "on" ]]; then
      local eval_cmd="nohup bash -c \"${start_cmd}\" >> ${work_log_file}  2>&1 &"
  else
      local eval_cmd="bash -c \"${start_cmd}\" >> ${work_log_file}  2>&1"
  fi
  echo " ${RUN_TIME} - ${user} - 执行启动命令: ${eval_cmd} " >> "${work_log_file}"  2>&1
  if [[ "$user" != "root" ]]; then
    chmod o+w -R "$work_log_directory"
  fi
  if [[ "$user" == "root" ]]; then
    eval "${eval_cmd}"
  else
    eval "su $user -c '${eval_cmd}'"
  fi
  sleep_by_startsecs "${work}"
  PID="$(check_pid "${work}")"
  if [ -z "${PID}" ]; then
    echo -e "启动项目：\033[32m ${work} 运行失败，没有找到进程 \033[0m"
  else
    echo -e "启动项目：\033[32m ${work} 运行成功 PID：${PID} \033[0m"
  fi
  cd "${SCRIPT_PATH}" || { echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"; return; }
}

stop_project() {
  local work="$1"
  [[ -z ${work} ]] && { echo -e "\033[32m 停止项目 不能传递为空的项目名称 \033[0m" ; return; }
  local PID
  PID="$(check_pid "${work}")"
  if [ -z "${PID}" ]; then
    echo -e "\n停止运行： \033[33m ${work} 未运行 !\n \033[0m"
  else
    local stop_cmd
    local user
    local work_log_file
    local work_log_directory
    stop_cmd="$(get_config_value "${work}" "stopCmd")"
    user="$(get_config_value "${work}" "user" "root")"
    work_log_file="$(get_config_value "${work}" "logFile" "${log_directory}/${work}/run.log")"
    if command -v realpath &> /dev/null; then
        work_log_directory=$(realpath -m "$(dirname "${work_log_file}")")
      else
        work_log_directory="$(dirname "${work_log_file}")"
      fi
    mkdir -p "$work_log_directory"
    if [[ -z "$stop_cmd" ]]; then
      cd "${SCRIPT_PATH}" || { echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"; return; }
      for pid in ${PID}; do
        kill "$pid"
      done
      echo " ${RUN_TIME} - ${user} - 执行停止命令: 循环 kill pid ==== pids( ${PID} )" >> "${work_log_file}"  2>&1
    else
      local work_directory
      work_directory="$(get_config_value "${work}" "directory" "${work_log_directory}")"
      if [[ -n "$work_directory" ]]; then
        cd "$work_directory" || { echo -e "\033[31m ${work} 没有找到工作目录: $work_directory \033[0m"; return; }
      fi
      echo " ${RUN_TIME} - ${user} - 执行停止命令: ${stop_cmd} " >> "${work_log_file}"  2>&1
      if [[ "$user" == "root" ]]; then
        eval "$stop_cmd"
      else
        su "${user}" -c "$stop_cmd"
      fi
    fi
    sleep_by_startsecs "${work}"
    PID="$(check_pid "${work}")"
    if [ -z "${PID}" ]; then
      echo -e "\n停止运行：\033[32m ${work} 退出成功 !\n \033[0m"
    else
      echo -e "\n停止运行：\033[31m ${work} 退出失败 ! 运行PID：${PID} \n \033[0m" && return
    fi
  fi
}

restart_project() {
  local work="$1"
  [[ -z ${work} ]] && { echo -e "\033[32m 重启项目 不能传递为空的项目名称 \033[0m" ; return; }
  local restart_cmd
  local user
  restart_cmd="$(get_config_value "${work}" "restartCmd")"
  user="$(get_config_value "${work}" "user" "root")"
  if [[ -z "$restart_cmd" ]]; then
    stop_project "${work}"
    start_project "${work}"
  else
    local PID
    PID="$(check_pid "${work}")"
    if [ -z "${PID}" ]; then
      start_project "${work}"
    else
      local work_log_file
      local work_log_directory
      work_log_file="$(get_config_value "${work}" "logFile" "${log_directory}/${work}/run.log")"
      if command -v realpath &> /dev/null; then
          work_log_directory=$(realpath -m "$(dirname "${work_log_file}")")
        else
          work_log_directory="$(dirname "${work_log_file}")"
        fi
      mkdir -p "$work_log_directory"
      local work_directory
      work_directory="$(get_config_value "${work}" "directory" "${work_log_directory}")"
      if [[ -n "$work_directory" ]]; then
        cd "$work_directory" || { echo -e "\033[31m ${work} 没有找到工作目录: $work_directory \033[0m"; return; }
      fi
      if [[ "$user" == "root" ]]; then
        eval "$restart_cmd"
      else
        su "${user}" -c "$restart_cmd"
      fi
    fi
    sleep_by_startsecs "${work}"
    PID="$(check_pid "${work}")"
    if [ -z "${PID}" ]; then
      echo -e "重启项目：\033[32m ${work} 重启失败，没有找到进程 \033[0m"
    else
      echo -e "重启项目：\033[32m ${work} 重启成功 PID：${PID} \033[0m"
    fi
  fi
}

status_project() {
  local work="$1"
  [[ -z ${work} ]] && { echo -e "\033[32m 查看项目状态 不能传递为空的项目名称 \033[0m" ; return; }
  local PID
  PID="$(check_pid "${work}")"
  if [ -z "${PID}" ]; then
    echo -e "\033[31m \n 项目：${work} 优先级：$(get_config_value "${work}" "priority" "0") 未运行 ! 配置文件地址：$(get_config_value "${work}" "configPath" "未找到")\n \033[0m"
  else
    echo -e "\033[32m \n 项目：${work} 优先级：$(get_config_value "${work}" "priority" "0") 正在运行 ! 项目运行PID：${PID}\n \033[0m"
  fi
}

config_help_fun() {
  echo "当前系统架构:${ARCH}"
  cat <<EOF
此脚本为项目进程管理脚本，禁止随意修改变动，如需修改请联系项目负责人 
脚本核心读取的配置文件有： init_${SCRIPT_NAME%\.*}.txt - 初始化命令文件，shell脚本格式编写 
                       config/*.conf - 所有工作进程配置文件 
配置描述： 
   init_${SCRIPT_NAME%\.*}.txt： 
      1、可以在所有工作进程前执行文本内的所有命令，进行统一处理 
      2、可以统一配置全局环境变量，注意配置的环境变量只在脚本运行中生效，不会影响的服务器以及连接会话 
      3、可以通过设置 config_dir 变量去指定所有项目配置文件的存放位置 
      4、可以通过设置 log_directory 变量去指定全局项目默认运行日志的存放位置
      5、可以通过设置 clear_log_file_cron 变量去指定全局项目默认定时清理项目运行日志任务的cron表达式
  config/*.conf： 
      1、所有项目配置的开头必须是  [work:\${workName}]  其中 \${workName} 是项目的名称 
      2、所有配置都是 \${key]=\${value} 的格式，value前后不要出现空格、制表符、双引号或单引号 
      3、以下为项目的配置项： 
               runCmd           - 核心配置，必须配置的参数，用于启动项目的shell命令 
               directory        - 项目工作目录，在执行命令前会进入到指定目录后执行，如果没有配置就会在项目的运行日志目录直接执行 
               priority         - 项目启动优先级，数值越大优先级越高，默认为0 
               user             - 项目操作命令运行用户，默认为root用户 
               processCheckType - 查询项目进程的方法类型，默认值为 name，可选 port 
               processName      - 查询项目进程的名称，默认是启动shell命令，如果 daemon 配置为 off 则默认是项目名称 
               processPort      - 查询项目进程的端口，如果 processCheckType 配置为 port 则必须指定端口 
               daemon           - 启动shell命令是否后台静默运行，默认是 on 开启状态，注意如果配置成 off 关闭状态，请确保启动命令不会阻塞进程，否则可能会导致脚本卡在当前项目操作无法进行后续操作 
               startsecs        - 检查项目是否启动获取pid前等待秒数，默认是3s
               logFile          - 指定运行日志路径,默认是 ${log_directory}/\${workName}/run.log
               logFileMaxSiz    - 指定运行日志文件记录大小限制，单位为Mb，默认值为：10，如果超过限制大小就会清空日志文件，开启备份会在备份后清空，设置为0，则不限制大小
               logBacks         - 备份保留运行日志个数，默认为0，当大于0的时候开启备份
               stopCmd          - 项目停止命令，如果不设置默认通过pid进行kill操作 
               restartCmd       - 项目重启命令，如果不设置默认先进行项目停止操作再进行项目启动操作
EOF
}



# Function to execute command
execute_command() {
    local work="$1"
    local action="$2"
    if [ "$action" = "start" ]; then
        start_project "${work}"
    elif [ "$action" = "stop" ]; then
        stop_project "${work}"
    elif [ "$action" = "status" ]; then
        status_project "${work}"
    elif [ "$action" = "restart" ]; then
        restart_project "${work}"
    else
        echo -e "\033[31m ${work} 错误的操作: $action \033[0m"
    fi
}

function help_fun() {
  cat  <<EOF >&2

usage: ${SCRIPT_NAME} <action_options> [work_options...]
action_options:
  start           启动项目，默认按照优先级启动所有项目，也可以指定项目名称启动项目
  stop            停止项目，默认按照优先级停止所有项目，也可以指定项目名称停止项目
  status          查看项目状态，默认查看所有项目状态，也可以指定项目名称查看项目状态
  restart         重启项目，默认按照优先级重启所有项目，也可以指定项目名称重启项目
  log             查看指定项目运行日志
  clear-log       清理项目运行日志，默认清理所有项目运行日志以及定时清理任务运行日志，也可以指定项目名称清理项目运行日志
  clear-log-cron  定时清理项目运行日志任务，通过参数 enable 开启和 disable 关闭
  help            查看命令使用方式
  config-help     查看项目配置文件编写说明
EOF
  if [ ${#works_sorted[@]} -gt 0 ]; then
    echo "work_options:"
    for item in "${works_sorted[@]}"; do
       work="${item#*|}"
       echo "  - $work "
    done
  else
    echo "没有在配置目录 ${config_dir} 中找到项目配置"
  fi
}
#### 脚本方法定义 END ####

#### 脚本主体运行 BEGIN ####
# Main script logic
declare -A config
works_sorted=()
read_config_files

action="$1"
case "$action" in
  start|stop|status|restart)
    if [[ "$2" ]]; then
       work="$2"
       config_key="$work|configPath"
       if [[ "${config[$config_key]}" ]]; then
            execute_command "${work}" "$action"
       else
           echo "Invalid work. Please specify a valid work."
           exit 1
       fi
    else
      if [ ${#works_sorted[@]} -gt 0 ]; then
        for item in "${works_sorted[@]}"; do
          work="${item#*|}"
          execute_command "${work}" "$action"
        done
      else
          echo "没有在配置目录 ${config_dir} 中找到项目配置"
      fi
    fi
    ;;
  log)
    if [[ "$2" ]]; then
      work="$2"
      [[ -z ${work} ]] && { echo -e "\033[32m 不能传递为空的项目名称 \033[0m" ; return; }
      work_log_file="$(get_config_value "${work}" "logFile" "${log_directory}/${work}/run.log")"
      if [[ -f "${work_log_file}" ]]; then
          echo "\n使用命令: tail -f ${work_log_file}\n\n"
          tail -30f "${work_log_file}"
      else
        log_error "项目 ${work} 的运行日志 ${work_log_file} 不存在，请检查项目状态。"
      fi
    else
      log_error "选项 $action ：需要指定项目名称参数"
    fi
    ;;
  clear-log)
    if [[ "$2" ]]; then
       work="$2"
       [[ -z ${work} ]] && { echo -e "\033[32m 不能传递为空的项目名称 \033[0m" ; return; }
       config_key="$work|configPath"
       if [[ "${config[$config_key]}" ]]; then
         clear_log "${work}"
       else
         echo "Invalid work. Please specify a valid work."
         exit 1
       fi
    else
      if [ ${#works_sorted[@]} -gt 0 ]; then
        for item in "${works_sorted[@]}"; do
          work="${item#*|}"
          clear_log "${work}"
        done
      else
          echo "没有在配置目录 ${config_dir} 中找到项目配置"
      fi
     if [[ -f "${log_directory}/${SCRIPT_NAME%\.*}-crontab.log" ]]; then
         # shellcheck disable=SC2012
         file_size="$(ls -l -f "${log_directory}/${SCRIPT_NAME%\.*}-clear-log-crontab.log" | awk '{ print $5 }')"
         maxsize=$(1000000)
         if [ "${file_size}" -gt "${maxsize}" ]; then
             cat /dev/null > "${log_directory}/${SCRIPT_NAME%\.*}-clear-log-crontab.log"
         fi
     fi
    fi
    ;;
  clear-log-cron)
    if [[ "$2" ]]; then
      work="$2"
      case "$work" in
        enable)
          enable_schedule_task
         ;;
        disable)
          disable_schedule_task
          ;;
        *)
          log_error "选项 $action ：参数不存在，参数 enable 开启和 disable 关闭"
          ;;
      esac
    else
      log_error "选项 $action ：需要指定参数，参数 enable 开启和 disable 关闭"
    fi
    ;;
  help)
    help_fun
    ;;
  config-help)
    config_help_fun
    ;;
  *)
    log_error ""
    ;;
esac

echo "脚本运行完成"
#### 脚本主体运行 END ####