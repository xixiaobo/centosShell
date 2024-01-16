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
  cat  <<EOF >&2

usage: ${SCRIPT_NAME} [options...] <url>
Options:
  -c  --cookie  要传递到服务器的自定义cookie
  -d  --data  HTTP POST请求body数据
  -D  --debug 打印请求命令
  -h  --help 查看命令使用方式
  -H  --header  要传递到服务器的自定义标头
  -u  --user    要传递账号密码，eg: username:password
  -o  --output-document  将下载文件内容传输到指定文件内
  -X  --request 指定请求方式，可选有 GET、POST等

EOF
}
function parsing_parameters() {
  declare -A result
  local method="GET"
  result["debug"]=false
  local headers=()
  while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
          -X|--request|-H|--header|-d|--data|-c|--cookie|-o|--output-document|-u|--user)
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
          -D|--debug)
              result["debug"]=true
              ;;
          -o|--output-document)
              result["filename"]="$2"
              shift
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
function create_file() {
  local filename
  if [[ "$2" ]]; then
    filename="$2"
  else
    filename="./$(basename "$1")"
  fi
  local directory
  if command -v realpath &> /dev/null; then
    directory=$(realpath -m "$(dirname "${filename}")")
  else
    directory="$(dirname "${filename}")"
  fi
  mkdir -p "${directory}"
  if [[ -f "${filename}" ]]; then
    if [[ ! -f "${filename}.0" ]]; then
      filename="$filename.0"
    else
      local max_number=-1
      base_filename="${filename}"
      for filename_new in "$base_filename".*; do
        if [[ "$filename_new" =~ ^$base_filename\.([0-9]+)$ ]]; then
          number="${BASH_REMATCH[1]}"
          if (( number > max_number )); then
            max_number=$number
          fi
        fi
      done
      next_number=$((max_number + 1))
      filename="$base_filename.$next_number"
    fi
  fi
  touch "$filename"
  echo "$filename"
}
function tcp_download() {
  declare -A values
  local result
  result="$(parsing_parameters "$@")"
  if [[ -z "$result" ]]; then
      exit 1
  fi
  eval "declare -A values=${result#*=}"
  local url
  url="${values["url"]}"
  if [[ -z "${url}" ]]; then
    log_error "没有找到请求地址！"
  fi
  if [[ -z ${values["host"]} ]]; then
    log_error "请求地址解析异常请检查！"
  fi
  local filename
  filename=$(create_file "${url}" "${values["filename"]}")
  echo "准备下载文件 $filename ..."
  if ! exec 3<>"/dev/tcp/${values["host"]}/${values["port"]}"; then
    log_error "Failed to establish TCP connection"
    return 1
  fi
  if ${values["debug"]} ; then
    echo -e "\n" >&2
    echo "tcp request: echo -en \"${values["tcp_request_msg"]}\" >&3" >&2
    echo -e "\n" >&2
  fi
  # Send HTTP POST request
  if ! echo -en "${values["tcp_request_msg"]}" >&3; then
    exec 3>&-
    log_error "Failed to send HTTP request"
    return 1
  fi
  local status=true
  local status_code
  while IFS= read -r line ; do
    if [[ -z ${status_code} && $(echo "$line" | tr -d '\r\n') =~ HTTP/1\.1\ ([0-9]{3}) ]]; then
      status_code=${BASH_REMATCH[1]}
      if [[ ${BASH_REMATCH[1]} =~ ^(200|20[0-9])$ ]]; then
        echo "下载请求成功,开始下载...."
      else
        echo "下载请求失败,以下为异常返回结果"
        status=false
      fi
    fi
    if ! ${status}; then
        echo -e "$line" >&2
    fi
    [[ "${line}" == $'\r' ]] && break
  done <&3
  nul='\0'
  while IFS= read -d '' -r x || { nul=""; [ -n "$x" ]; }; do
    if ${status}; then
        printf "%s${nul}" "${x}" >> "$filename"
    else
        printf "%s${nul}" "${x}" >&2
    fi
  done <&3
  exec 3>&-
  echo -e "\n文件下载结束!"
}

tcp_download "$@"