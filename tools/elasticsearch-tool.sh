#!/bin/bash
readonly SCRIPT_PATH=$(
  { cd "$(dirname "${BASH_SOURCE[0]}")" || {
    echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"
    exit 1
  }; }
  pwd
)
readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

function log() {
  local options
  local msg
  while [[ $# -gt 0 ]]; do
        key="$1"
        if [[ $key == "-"* ]]; then
          options="$key"
        else
          msg="\"$key\""
        fi
        shift
    done
  eval "echo ${options} ${msg} >&2"
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
        log "${error_message:-"输入不能为空，请重新输入。"}"
      fi
    else
      echo "$input"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  log "连续 3 次输入错误，退出脚本。"
  return 1
}
function validate_datetime() {
  local input=$1
  if [[ ${#input} -eq 14 ]]; then
    datetime="${input:0:4}-${input:4:2}-${input:6:2} ${input:8:2}:${input:10:2}:${input:12:2}"
    date +%s -d "$datetime" 2>/dev/null
    return $?
  else
    return 1
  fi
}

function prompt_input_time() {
  local prompt_message=$1
  local error_message=$2
  local input
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    read -p "$prompt_message" -r input
    if [[ -z "$input" ]] ; then
      log "${error_message:-"时间为空或格式异常，请重新输入。"}"
    else
      if ! validate_datetime "$input"; then
        log "${error_message:-"时间为空或格式异常，请重新输入。"}"
      else
        return 0
      fi
    fi
    attempt=$((attempt + 1))
  done
  log "连续 3 次输入错误，退出脚本。"
  return 1
}


function join_with_comma() {
  local array=("$@")
  local result=""
  for element in "${array[@]}"; do
    if [[ -n $result ]]; then
      result+=",$element"
    else
      result+="$element"
    fi
  done
  echo "$result"
}

function add_term_query() {
  local name=$1
  local values
  values=$(prompt_input "请输入 $name 的值（多个值请用分号 ';' 分隔）: ") || return 1
  echo "{\"terms\": {\"$name\": [\"${values//;/\",\"}\"]}}"
}

function add_wildcard_query() {
  local name=$1
  local value
  value=$(prompt_input "请输入模糊匹配的值: ") || return 1
  echo "{\"wildcard\": {\"$name\": {\"wildcard\": \"$value\"}}}"
}

function add_range_query() {
  local name=$1
  local time_value
  while true; do
    log "请选择查询时间方式："
    log "1. 大于指定时间"
    log "2. 小于指定时间"
    log "3. 指定时间范围"
    local choice
    local gte_value
    local lte_value
    choice=$(prompt_input "请选择查询时间方式 请输入选项数字（1-3）: ") || return 1
    case $choice in
      1)
        gte_value=$(prompt_input_time "请输入大于指定时间的值: ") || return 1
        time_value="{\"gte\": $gte_value, \"format\": \"epoch_second\"}"
        break
        ;;
      2)
        lte_value=$(prompt_input_time "请输入小于指定时间的值: ") || return 1
        time_value="{\"lte\": $lte_value, \"format\": \"epoch_second\"}"
        break
        ;;
      3)
        gte_value=$(prompt_input_time "请输入时间范围的开始值: ") || return 1
        lte_value=$(prompt_input_time "请输入时间范围的结束值: ") || return 1
        time_value="{\"gte\": $gte_value, \"lte\": $lte_value, \"format\": \"epoch_second\"}"
        break
        ;;
      *)
        log "无效的选项，请重新输入。"
        ;;
    esac
  done

  echo "{\"range\": {\"$name\": $time_value}}"
}

function generate_query_sub() {
  local query
  while true; do
    log ""
    log "请选择数据查询的类型："
    log "1. 文本精确查询（可以多字段分号 ';' 分割）"
    log "2. 文本模糊查询"
    log "3. 时间查询"
    local choice
    choice=$(prompt_input "请选择数据查询的类型 请输入选项数字（1-3）: ") || return 1
    name=$(prompt_input "请输入字段名称: ") || return 1
    case $choice in
      1)
        query="$(add_term_query "${name}")" || return 1
        break
        ;;
      2)
        query="$(add_wildcard_query "${name}")" || return 1
        break
        ;;
      3)
        query="$(add_range_query "${name}")" || return 1
        break
        ;;
      *)
        log "无效的选项，请重新输入。"
        ;;
    esac
  done

  echo "$query"
}


function generate_query(){
  local must=()
  local mustNot=()
  local should=()

  while true; do
    log ""
    log "请选择要查询条件的类型："
    log "1. must-匹配包含条件的数据"
    log "2. mustNot-匹配不包含条件的数据"
    log "3. should-或者可以匹配包含条件的数据"
    log "0. 完成查询条件添加"
    local choice
    choice=$(prompt_input "请输入选项数字（0-3）: ") || return 1
    case $choice in
      0)
        break
        ;;
      1)
        must+=("$(generate_query_sub)") || return 1
        ;;
      2)
        mustNot+=("$(generate_query_sub)") || return 1
        ;;
      3)
        should+=("$(generate_query_sub)") || return 1
        ;;
      *)
        log "无效的选项，请重新输入。"
        ;;
    esac
  done
  local bool_array=()
  if [ ${#must[@]} -gt 0 ]; then
      bool_array+=("\"must\":[$(join_with_comma "${must[@]}")]")
  fi
  if [ ${#mustNot[@]} -gt 0 ]; then
      bool_array+=("\"mustNot\":[$(join_with_comma "${mustNot[@]}")]")
  fi
  if [ ${#should[@]} -gt 0 ]; then
      bool_array+=("\"should\":[$(join_with_comma "${should[@]}")]")
  fi
  if [ ${#bool_array[@]} -gt 0 ]; then
      echo "\"bool\":{$(join_with_comma "${bool_array[@]}")}"
  fi
}

function generate_source() {
  while true; do
    log ""
    log "请选择限制方式："
    log "1. excludes-屏蔽部分字段"
    log "2. includes-只返回部分字段"
    log "0. 取消限制"
    local choice
    local values=""
    choice=$(prompt_input "请输入选项数字（0-3）: ") || return 1
    case $choice in
      0)
        break
        ;;
      1)
        values=$(prompt_input "请输入要屏蔽的字段名称（多个值请用分号 ';' 分隔）: ") || return 1
        echo "\"excludes\": [\"${values//;/\",\"}\"]"
        break
        ;;
      2)
        values=$(prompt_input "请输入只返回的字段名称（多个值请用分号 ';' 分隔）: ") || return 1
        echo "\"includes\": [\"${values//;/\",\"}\"]"
        break
        ;;
      *)
        log "无效的选项，请重新输入。"
        ;;
    esac
  done
}
function generate_sort() {
  local sort=()
  while true; do
    log ""
    log "请选择排序方式："
    log "1. desc-降序"
    log "2. asc-升序"
    log "0. 结束添加排序条件"
    local choice
    local values=""
    local order=""
    choice=$(prompt_input "请输入选项数字（0-3）: ") || return 1
    case $choice in
      0)
        break
        ;;
      1)
        values=$(prompt_input "请输入要降序排序的字段名称（多个值请用分号 ';' 分隔）: ") || return 1
        order="desc"
        ;;
      2)
        values=$(prompt_input "请输入要升序排序的字段名称（多个值请用分号 ';' 分隔）: ") || return 1
        order="asc"
        ;;
      *)
        log "无效的选项，请重新输入。"
        continue
        ;;
    esac
    if [[ -n ${values} ]]; then
      oldIFS=$IFS
      IFS=";"
      for field in $values; do
         sort+=("{\"${field}\": {\"order\": \"${order}\"}}")
      done
      IFS=$oldIFS
    fi
  done
  if [ ${#sort[@]} -gt 0 ]; then
      join_with_comma "${sort[@]}"
  fi
}
function view_all_indexes() {
    declare -A values
    eval "declare -A values=${1#*=}"
    if [[ -z ${values["host"]} ]]; then
        log "没有配置es 请求主机地址请检查"
        exit 1
    fi
    local request_str
    if [[ -z "${values["username"]}" ]]; then
      request_str=$( bash "${SCRIPT_PATH}/request.sh" -dict "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动" )
    else
      request_str=$(bash "${SCRIPT_PATH}/request.sh" -dict -u "${values["username"]}:${values["password"]}" "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动")
    fi
    if [[ -z ${request_str} ]]; then
      return 0
    fi
    declare -A request
    eval "declare -A request=${request_str}"
    if [[ ${request["status_code"]} =~ ^(200|20[0-9])$ ]]; then
      log -e "\n当前 ES 查询所有索引获取结果为: "
      log "$(echo -e "${request["data"]}" | awk '{print $3}')"
    else
      log "ES 查询失败，请检查 ES 连接配置，以下为查询返回结果:"
      log -e "${request["data"]}"
    fi
}

function query_time_range_data() {
  declare -A values
  eval "declare -A values=${1#*=}"
  local index
  index=$(prompt_input "请输入要查询的索引: " "输入为空，请正确输入索引名称！") || return 1
  local indices_response_str
  if [[ -z "${values["username"]}" ]]; then
    indices_response_str=$( bash "${SCRIPT_PATH}/request.sh" -dict "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动" )
  else
    indices_response_str=$(bash "${SCRIPT_PATH}/request.sh" -dict -u "${values["username"]}:${values["password"]}" "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动")
  fi
  if [[ -z ${indices_response_str} ]]; then
      return 0
  fi
  declare -A indices_response
  eval "declare -A indices_response=${indices_response_str}"
  if [[ ${indices_response["status_code"]} =~ ^(200|20[0-9])$ ]]; then
    if ! echo -e "${indices_response["data"]}" | awk '{print $3}' | grep "^${index}" > /dev/null 2>&1; then
      log "ES 中没有找到索引 ${index},请重新确认"
      return 0
    fi
  else
    log "ES 查询失败，请检查 ES 连接配置，以下为查询返回结果:"
    log -e "${indices_response["data"]}"
    return 0
  fi
  local es_select_data=()
  local select_size
  select_size=$(prompt_input "请输入要查询数据的长度（默认:1000）: " "" "1000") || return 1
  if ! [[ $select_size =~ ^[0-9]+$ && $select_size -ge 0 ]]; then
    log "输入的数据的长度不是数字或小于0，将按照默认值查询"
    select_size=1000
  fi
  es_select_data+=("\"size\":${select_size}")
  local add_query
  add_query=$(prompt_input "是否要添加查询条件,选择 Y/N (默认为 N): " "" "N") || return 1
  if [[ "${add_query}" == "Y" || "${add_query}" == "y" || "${add_query}" == "YES" || "${add_query}" == "yes" ]]; then
    local select_query
    select_query=$(generate_query) || return 1
    if [[ -n ${select_query} ]]; then
      es_select_data+=("\"query\":{${select_query}}")
    fi
  fi

  local restrict_return
  restrict_return=$(prompt_input "是否要限制返回结果条目,选择 Y/N (默认为 N): " "" "N") || return 1
  if [[ "${restrict_return}" == "Y" || "${restrict_return}" == "y" || "${restrict_return}" == "YES" || "${restrict_return}" == "yes" ]]; then
    local select_source
    select_source=$(generate_source)  || return 1
    if [[ -n ${select_source} ]]; then
      es_select_data+=("\"_source\":[${select_source}]")
    fi
  fi
  local use_sort
  use_sort=$(prompt_input "是否要进行结果排序查询,选择 Y/N (默认为 N): " "" "N") || return 1
  if [[ "${use_sort}" == "Y" || "${use_sort}" == "y" || "${use_sort}" == "YES" || "${use_sort}" == "yes" ]]; then
    local select_sort
    select_sort=$(generate_sort)  || return 1
    if [[ -n ${select_sort} ]]; then
      es_select_data+=("\"sort\":[${select_sort}]")
    fi
  fi
  local es_select_data_str
  es_select_data_str="$(join_with_comma "${es_select_data[@]}")"

  local select_response_str
  if [[ -z "${values["username"]}" ]]; then
    select_response_str=$( bash "${SCRIPT_PATH}/request.sh" -dict -d "${es_select_data_str}" "http://${values["host"]}:${values["port"]}/${index}*/_search" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动" )
  else
    select_response_str=$(bash "${SCRIPT_PATH}/request.sh" -dict -u "${values["username"]}:${values["password"]}" -d "${es_select_data_str}" "http://${values["host"]}:${values["port"]}/${index}*/_search" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动")
  fi
  if [[ -z ${select_response_str} ]]; then
    return 0
  fi
  declare -A select_response
  eval "declare -A select_response=${select_response_str}"
  log "ES 查询接口请求结果:"
  log -e "${select_response["data"]}"
}

function custom_query_index() {
  declare -A values
  eval "declare -A values=${1#*=}"
  local index
  index=$(prompt_input "请输入要查询的索引: " "输入为空，请正确输入索引名称！") || return 1
  local indices_response_str
  if [[ -z "${values["username"]}" ]]; then
    indices_response_str=$( bash "${SCRIPT_PATH}/request.sh" -dict "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动" )
  else
    indices_response_str=$(bash "${SCRIPT_PATH}/request.sh" -dict -u "${values["username"]}:${values["password"]}" "http://${values["host"]}:${values["port"]}/_cat/indices" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动")
  fi
  if [[ -z ${indices_response_str} ]]; then
    return 0
  fi
  declare -A indices_response
  eval "declare -A indices_response=${indices_response_str}"
  if [[ ${indices_response["status_code"]} =~ ^(200|20[0-9])$ ]]; then
    if ! echo -e "${indices_response["data"]}" | awk '{print $3}' | grep "^${index}" > /dev/null 2>&1; then
      log "ES 中没有找到索引 ${index},请重新确认"
      return 0
    fi
  else
    log "ES 查询失败，请检查 ES 连接配置，以下为查询返回结果:"
    log -e "${indices_response["data"]}"
    return 0
  fi


  local es_select_data_str
  local vi_tool
  vi_tool=$(prompt_input "请输入用使用的编辑软件（默认是vi）: " "" "vi") || return 1
  # 创建一个临时文件
  local tmp_file
  tmp_file=$(mktemp)
  # 打开vi编辑器进行文本编辑
  eval "${vi_tool} \"${tmp_file}\""
  # 从临时文件中读取文本并赋值给变量
  es_select_data_str=$(cat "$tmp_file") || return 1
  # 删除临时文件
  rm "$tmp_file"
  if [[ -z ${es_select_data_str} ]]; then
    log "输入内容为空无法进行请求"
    return 0
  fi
  log "请求的json字符串为:"
  log -e "${es_select_data_str}"
  local select_response_str
  if [[ -z "${values["username"]}" ]]; then
    select_response_str=$( bash "${SCRIPT_PATH}/request.sh" -dict -d "${es_select_data_str}" "http://${values["host"]}:${values["port"]}/${index}*/_search" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动" )
  else
    select_response_str=$(bash "${SCRIPT_PATH}/request.sh" -dict -u "${values["username"]}:${values["password"]}" -d "${es_select_data_str}" "http://${values["host"]}:${values["port"]}/${index}*/_search" 2>/dev/null || log "请求ES API异常，请检查ES服务是否启动")
  fi
  if [[ -z ${select_response_str} ]]; then
    return 0
  fi
  declare -A select_response
  eval "declare -A select_response=${select_response_str}"
  log "ES 查询接口请求结果:"
  log -e "${select_response["data"]}"

}

function menu() {
  local es_config_str="$1"
  log -ne "\033[1;1H"
  log -ne "\033[2J"
  log -ne "\033[1;1H"
  log "=========ES 查询工具============="
  log "1. 查看所有索引名称"
  log "2. 查询索引时间范围数据"
  log "3. 自定义查询索引数据"
  log "0. 退出查询工具"
  log "=============================="
  local choice
  choice=$(prompt_input "请选择功能（输入菜单编号）: " "输入为空，请按照菜单编号输入！") || return 1

  case $choice in
    0)
      log "退出查询工具..."
      return 1
      ;;
    1)
      view_all_indexes "${es_config_str}"
      ;;
    2)
      query_time_range_data "${es_config_str}"
      ;;
    3)
      custom_query_index "${es_config_str}"
      ;;
    *)
      log "无效的选择。"
      return 0
      ;;
  esac
  log -ne "继续请输入任意字符或直接回车，退出请按0或esc: "
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

main(){
  log "欢迎使用 ${SCRIPT_NAME} 脚本工具"
  log "本工具用于查询es数据"
  declare -A es_config
  local use_secure
  es_config["host"]=$(prompt_input "输入要连接的es主机地址(默认为 127.0.0.1): " "" "127.0.0.1") || return 1
  es_config["port"]=$(prompt_input "输入要连接的es的端口(默认为 9200): " "" "9200") || return 1
  use_secure=$(prompt_input "请确认es是否设置了账号密码,选择 Y/N (默认为 N): " "" "N") || return 1
  if [[ "${use_secure}" == "Y" || "${use_secure}" == "y" || "${use_secure}" == "YES" || "${use_secure}" == "yes" ]]; then
    es_config["username"]=$(prompt_input "输入要连接的es的用户名: " "es设置了账号密码，用户名不能为空") || return 1
    es_config["password"]=$(prompt_input "输入要连接的es的密码: " "es设置了账号密码，密码不能为空") || return 1
  fi
  local es_config_str
  es_config_str=$(declare -p es_config)

  while true; do
    if ! menu "${es_config_str}"; then
      break
    fi
    sleep 1
  done
}

main
