#!/bin/bash
readonly SCRIPT_PATH=$(
  { cd "$(dirname "${BASH_SOURCE[0]}")" || {
    echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"
    exit 1
  }; }
  pwd
)
readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

function log_error() {
  if [[ -n "$1" ]]; then
      echo "${SCRIPT_NAME}: $1"  >&2
  fi
  echo "${SCRIPT_NAME}: 命令相关详情，请使用 '${SCRIPT_NAME} --help' 查看"  >&2
  exit 1
}
function help_fun() {
  cat <<EOF >&2

usage: ${SCRIPT_NAME} [options...] <url>
Options:
  -c  --cookie  要传递到服务器的自定义cookie
  -d  --data    HTTP POST请求body数据
  -D  --debug   打印请求命令
  -h  --help    查看命令使用方式
  -H  --header  要传递到服务器的自定义标头
  -i  --include 输出结果包含response header
  -I  -–head    只显示信息头
  -v  --verbose 显示所有信息，包括request header、request body、response header、response body
  -u  --user    要传递账号密码，eg: username:password
  -X  --request 指定请求方式，可选有 GET、POST等

EOF
}
function parsing_parameters() {
  declare -A result
  local method="GET"
  result["debug"]=false
  result["include"]=false
  result["head"]=false
  result["verbose"]=false
  result["dict"]=false
  local headers=()
  while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
          -X|--request|-H|--header|-d|--data|-c|--cookie|-u|--user)
              if [[ -z "$2" ]]; then
                log_error "选项 $1 ：需要参数"
              fi
              ;;
      esac
      if [[ $key =~ ^(http[s]?)://([^/]+)(/.*)?$ ]]; then
        result["url"]="$key"
        local scheme="${BASH_REMATCH[1]}"
        result["host"]="${BASH_REMATCH[2]}"
        result["path"]="${BASH_REMATCH[3]}"
        if [[ "${scheme}" == "http" ]]; then
            result["port"]="80"
        elif [[ "${scheme}" == "https" ]]; then
            log_error "工具不支持https请求"
            exit 0
        fi
        # 判断是否包含端口号
        if [[ ${result["host"]} =~ ^(.*):([0-9]+)$ ]]; then
            result["host"]="${BASH_REMATCH[1]}"
            result["port"]="${BASH_REMATCH[2]}"
        fi
      fi
      case $key in
          -X|--request)
              method="$2"
              shift
              ;;
          -H|--header)
              headers+=("$2")
              shift
              ;;
          -d|--data)
              data="$2"
              shift
              ;;
          -c|--cookie)
              cookie="$2"
              shift
              ;;
          -u|--user)
              user_info="$2"
              shift
              ;;
          -i|--include)
              result["include"]=true
              ;;
          -I|-–head)
              result["head"]=true
              ;;
          -v|--verbose)
              result["verbose"]=true
              ;;
          -D|--debug)
              result["debug"]=true
              ;;
          -dict)
              result["dict"]=true
              ;;
          -h|--help)
              help_fun
              exit 0
              ;;
          *)
              ;;
      esac
      shift
  done
  local tcp_request_msg
  tcp_request_msg="${method} ${result["path"]} HTTP/1.1\r\n"
  if [[ ! "${headers[*]}" =~ ^Host:/.*$ || ! "${headers[*]}" =~ ^host:/.*$ ]]; then
     tcp_request_msg+="Host: ${result["host"]}\r\n"
  fi
  if [[ ! "${headers[*]}" =~ ^Accept:/.*$ || ! "${headers[*]}" =~ ^accept:/.*$ ]]; then
     tcp_request_msg+="Accept: */*\r\n"
  fi
  if [[ ! "${headers[*]}" =~ ^Connection:/.*$ || ! "${headers[*]}" =~ ^connection:/.*$ ]]; then
     tcp_request_msg+="Connection:close\r\n"
  fi
  for header in "${headers[@]}"; do
      tcp_request_msg+="${header}\r\n"
  done
  if [[ -n $user_info ]]; then
    if [[ ! "${headers[*]}" =~ ^nAuthorization:/.*$ ]]; then
      tcp_request_msg+="Authorization: Basic $(echo -n "${user_info}" | base64)\r\n"
    fi
  fi
  if [[ -n $data ]]; then
    if [[ ! "${headers[*]}" =~ ^Content-Type:/.*$ ]]; then
      tcp_request_msg+="Content-Type: application/json\r\n"
    fi
    tcp_request_msg+="Content-Length: ${#data}\r\n"
  fi
  if [[ -n $cookie ]]; then
      tcp_request_msg+="Cookie: ${cookie}\r\n"
  fi
  tcp_request_msg+="\r\n"
  tcp_request_msg+="${data}"
  result["tcp_request_msg"]=${tcp_request_msg}
  declare -p result
}
function tcp_request(){
  declare -A values
  local values_sting
  values_sting="$(parsing_parameters "$@")"
  if [[ -z "$values_sting" ]]; then
      exit 1
  fi
  eval "declare -A values=${values_sting#*=}"
  if [[ -z "${values["url"]}" ]]; then
      log_error "没有找到请求地址！"
  fi
  if [[ -z ${values["host"]} ]]; then
      log_error "请求地址解析异常请检查！"
  fi
  # Create TCP connection
  if ! exec 3<>"/dev/tcp/${values["host"]}/${values["port"]}" 2>/dev/null; then
    log_error "Failed to establish TCP connection"
    return 1
  fi
  if ${values["debug"]} ; then
    echo -e "\n" >&2
    echo "tcp request: echo -en \"${values["tcp_request_msg"]}\" >&3" >&2
    echo -e "\n" >&2
  fi
  # Send HTTP POST request
  if ! echo -en "${values["tcp_request_msg"]}" >&3 2>/dev/null; then
    exec 3>&-
    log_error "Failed to send HTTP request"
    return 1
  fi
  if ${values["verbose"]} && ! ${values["dict"]} ; then
    echo -e "\n------------request BEGIN-----------------"
    echo -e "request url: ${values["url"]}"
    echo -e "request:"
    echo -e "${values["tcp_request_msg"]}"
    echo -e "------------request END-------------------\n"
  fi

  if ! ${values["dict"]}; then
    if  ${values["verbose"]} || ${values["include"]} ; then
      echo -e "\n------------response header BEGIN-----------------\n"
    fi
  fi
  declare -A dict_result
  local status_code
  while IFS= read -r line ; do
    if ! ${values["dict"]}; then
      if  ${values["verbose"]} || ${values["include"]} || ${values["head"]} ; then
         echo -e "$line"
      fi
    else
      if [[ -z ${status_code} && $(echo "$line" | tr -d '\r\n') =~ HTTP/1\.1\ ([0-9]{3}) ]]; then
        status_code=${BASH_REMATCH[1]}
        dict_result["status_code"]="${status_code}"
        dict_result["data"]=""
      fi
    fi
    [[ "${line}" == $'\r' ]] && break
  done <&3
  if ! ${values["dict"]}; then
    if  ${values["verbose"]} || ${values["include"]}  ; then
      echo -e "\n------------response header END-----------------\n"
      echo -e "\n------------response body BEGIN-----------------\n"
    fi
  fi
  if ! ${values["head"]} ; then
  nul='\0'
  while IFS= read -d '' -r x || { nul=""; [ -n "$x" ]; }; do
    if ! ${values["dict"]}; then
      printf "%s${nul}" "${x}"
    else
      dict_result["data"]+=$(printf "%s${nul}" "${x}")
    fi
  done <&3
  fi
  if ! ${values["dict"]}; then
    if ${values["verbose"]} || ${values["include"]} ; then
      echo -e "\n------------response body END-----------------\n"
    fi
    echo -e "\n"
  else
    local result_str
    result_str=$(declare -p dict_result)
    echo "${result_str#*=}"
  fi
  exec 3>&-
}

tcp_request "$@"

