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
readonly SCRIPT_PARENT_PATH=$(dirname "$SCRIPT_PATH")
##### shell脚本读取的配置文件路径 #####
if [[ -f "${SCRIPT_PATH}/config/${SCRIPT_NAME%\.*}.conf" ]]; then
  readonly CONFIG_FILE="${SCRIPT_PATH}/config/${SCRIPT_NAME%\.*}.conf"
else
  readonly CONFIG_FILE="${SCRIPT_PATH}/${SCRIPT_NAME%\.*}.conf"
fi

cd "${SCRIPT_PATH}" || { echo -e "\033[31m 无法进入指定脚本目录: ${SCRIPT_PATH} \033[0m"; exit 1; }

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

function read_config_file() {
  local file="$1"
  if [[ ! -r "${file}" ]]; then
      echo "运行脚本异常: 配置文件 ${file} 不存在或无法读取"
      exit 1
  fi
  while IFS= read -r line; do
    if [[ "$line" =~ ^\s*# ]]; then
        continue
    fi
    if [[ "$line" =~ (.*)=(.*) ]]; then
      IFS="=" read -r key txt <<< "$line"
      value="$(compilation_parsing_value "${txt}")"
      eval "${key}=\"${value}\""
    fi
  done < "$file"
  if [[ -z "${jarName}" ]]; then
      echo "项目配置文件没有配置 jar包名称，无法运行脚本"
      exit 1
  fi

  enableAgentManage=${enableAgentManage:-false}
  if ${enableAgentManage}; then
    echo "Agent ssss"
    if test -z "${agentControlCenter}"; then
      if [ -r "${SCRIPT_PATH}/config/application.yml" ]; then
        ymlPath=${SCRIPT_PATH}/config/application.yml
      elif [ -r "${SCRIPT_PATH}/application.yml" ]; then
        ymlPath=${SCRIPT_PATH}/application.yml
      elif [ -r "${SCRIPT_PATH}/src/main/resources/config/application.yml" ]; then
        ymlPath=${SCRIPT_PATH}/src/main/resources/config/application.yml
      else
        echo "not find yml file"
      fi

      if [ -n "${ymlPath}" ]; then
        create_variables "${ymlPath}"
      fi
      collection_udp_ip=${collection_udp_ip:-"127.0.0.1"}
      agentControlCenter="${collection_udp_ip}:8766"
    fi
    checkVersionApi=${checkVersionApi:-"api/agent-manage/agent-last-version"}
    downloadAgentScriptApi=${downloadAgentScriptApi:-"api/agent-manage/agent-script-download"}
    downloadAgentScriptConfigApi=${downloadAgentScriptConfigApi:-"api/agent-manage/agent-script-config-download"}
    downloadAgentApi=${downloadAgentApi:-"api/agent-manage/agent-download"}
    downloadAgentDefaultConfigApi=${downloadAgentDefaultConfigApi:-"api/agent-manage/agent-default-yml-download"}
    downloadJavaApi=${downloadJavaApi:-"api/agent-manage/java-download"}
  fi

  javaPath=${javaPath:-"java"}
  javaUseVersion=${javaUseVersion:-"1.8"}
  jarPath=${jarPath:-${SCRIPT_PATH}}
  javaOptions=${javaOptions:-"-server -Xms128m -Xmx256m"}
  startsecs=${startsecs:-3}
  if ! [[ -n $startsecs && $startsecs =~ ^[0-9]+$ ]]; then
    startsecs=3
  fi
  processCheckType=${processCheckType:-"name"}
  processName=${processName:-${jarName}}
  projectName=${projectName:-${SCRIPT_NAME%\.*}}
  runLogFilePath=${runLogFilePath:-${SCRIPT_PATH}}
  runLogFileName=${runLogFileName:-${projectName}}
  runLogFileMaxSize=${runLogFileMaxSize:-"10"}
  if ! [[ -n $runLogFileMaxSize && $runLogFileMaxSize =~ ^[0-9]*(\.[0-9]+)?$ ]]; then
    runLogFileMaxSize=10
  fi
  runLogBacks=${runLogBacks:-"0"}
  if ! [[ -n $runLogBacks && $runLogBacks =~ ^[0-9]+$ ]]; then
    runLogBacks=0
  fi
  mkdir -p "${runLogFilePath}"
  ## 项目运行日志，默认项目运行地址下+ets-client ##
  readonly runLogPath=${runLogFilePath}/${runLogFileName%\.*}
  projectKeepAliveCron=${projectKeepAliveCron:-"*/5 * * * *"}
  IFS=" " read -r -a project_keep_alive_crons <<< "$projectKeepAliveCron"
  if [[ ! ${#project_keep_alive_crons[@]} -eq 5 ]]; then
      echo "配置的projectKeepAliveCron表达式有误，使用默认配置"
      projectKeepAliveCron="*/5 * * * *"
  fi
  clearLogFileCron=${clearLogFileCron:-"0 1 * * *"}
  IFS=" " read -r -a clear_log_file_crons <<< "$clearLogFileCron"
  if [[ ! ${#clear_log_file_crons[@]} -eq 5 ]]; then
      echo "配置的clearLogFileCron表达式有误，使用默认配置"
      clearLogFileCron="0 1 * * *"
  fi
  enableGit=false
  if  [[ -n "${gitPath}" && -n "${gitBranch}" ]]; then
    if command -v git >/dev/null 2>&1; then
      if command -v mvn >/dev/null 2>&1; then
        javaSourceCodePath="${jarPath}/.source"
        enableGit=true
      else
        echo -e "\033[31m 当前环境没有找到mvn命令, 项目 ${projectName} 无法使用mvn进行打包  \033[0m" >&2
      fi
    else
      echo -e "\033[31m 当前环境没有找到git命令, 项目 ${projectName} 无法使用git进行更新  \033[0m" >&2
    fi
  fi

}

function check_pid() {
  if [[ "${processCheckType}" == "name" ]]; then
    PID=$(grep -lE "${processName}" /proc/[0-9]*/cmdline 2>/dev/null | xargs ls -l 2>/dev/null   | awk -F'/' '{print $(NF-1)}' |grep -v "${SCRIPT_PID}")
  else
    if [[ -n "${processPort}" ]]; then
      if command -v netstat >/dev/null 2>&1; then
        PID=$(netstat -nlp | grep ":$processPort" | awk '{print $7}' | sed 's/[^0-9]//g')
      else
        local hex_process_port
        hex_process_port=$(printf "%04X" "${processPort}")
        local uid
        uid="$(grep ":${hex_process_port} " "/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6"| head -n 1 |awk '{print  $11}')"
        if [[ -n ${uid} ]]; then
          # shellcheck disable=SC2010
          PID=$(ls -l /proc/*/fd/* 2>/dev/null | grep "socket:\[$uid\]" | awk -F'/' '{print $(NF-2)}')
        fi

      fi
    else
      echo -e "\033[31m 项目 ${projectName} 配置进程检测类型是端口监测，但是配置配置 processPort 无法进行进程检测 \033[0m" >&2
    fi
  fi
}

function tcp_request(){
  local url
  local fileName
  local HOST
  local PATH
  local PORT
  while [[ $# -gt 0 ]]; do
      key="$1"
      if [[ $key =~ ^(http[s]?)://([^/]+)(/.*)?$ ]]; then
        url="$key"
        local scheme="${BASH_REMATCH[1]}"
        HOST="${BASH_REMATCH[2]}"
        PATH="${BASH_REMATCH[3]}"
        if [[ "${scheme}" == "http" ]]; then
            PORT="80"
        elif [[ "${scheme}" == "https" ]]; then
            return 1
        fi
        # 判断是否包含端口号
        if [[ ${HOST} =~ ^(.*):([0-9]+)$ ]]; then
            HOST="${BASH_REMATCH[1]}"
            PORT="${BASH_REMATCH[2]}"
        fi
      fi
      case $key in
          -o|--output-document)
              fileName="$2"
              shift
              ;;
          *)
              ;;
      esac
      shift
  done
  if [[ -n "$url" ]]; then
    # Create TCP connection
    if ! exec 3<>"/dev/tcp/${HOST}/${PORT}"; then
     log_error "Failed to establish TCP connection"
     return 1
    fi
    # Send HTTP POST request
    if ! echo -en "GET ${DOC} HTTP/1.1\r\nHost: ${HOST}\r\nConnection:close\r\n\r\n" >&3; then
     exec 3>&-
     log_error "Failed to send HTTP request"
     return 1
    fi
    local status=true
    local status_code
    while IFS= read -r line ; do
      if [[ -z ${status_code} && $(echo "$line" | tr -d '\r\n') =~ HTTP/1\.1\ ([0-9]{3}) ]]; then
        status_code=${BASH_REMATCH[1]}
        if ! [[ ${BASH_REMATCH[1]} =~ ^(200|20[0-9])$ ]]; then
          status=false
          echo "${url} 请求失败,请求返回状态为 $(echo "$line" | tr -d '\r\n')"
          return 1
        fi
      fi
      [[ "${line}" == $'\r' ]] && break
    done <&3
    nul='\0'
    while IFS= read -d '' -r x || { nul=""; [ -n "$x" ]; }; do
      if [[ -n "${fileName}" ]]; then
        if ${status}; then
            printf "%s${nul}" "${x}" >> "${fileName}"
        fi
      else
        printf "%s${nul}" "${x}"
      fi
    done <&3
    exec 3>&-
  fi
}


function create_request_variables() {
  # check if curl is installed
  if command -v curl >/dev/null 2>&1; then
    http_cmd="curl -sS"
    download_cmd="curl -o"
  # check if wget is installed
  elif command -v wget >/dev/null 2>&1; then
    http_cmd="wget -qO-"
    download_cmd="wget -o"
  fi
}
function parse_yaml() {
  local yaml_file=$1
  local prefix=$2
  local s
  local w
  local fs
  s='[[:space:]]*'
  w='[a-zA-Z0-9_.-]*'
  fs="$(echo @ | tr @ '\034')"
  (
    sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/\s*$//g;' \
      -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
      -e "s|^\(${s}\)\(${w}\)${s}:${s}\"\(.*\)\"${s}\$|\1${fs}\2${fs}\3|p" \
      -e "s|^\(${s}\)\(${w}\)${s}[:-]${s}\(.*\)${s}\$|\1${fs}\2${fs}\3|p" |
      awk -F"${fs}" '{
            indent = length($1)/2;
            if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            v_name[indent] = $2;
            for (i in v_name) {if (i > indent) {delete v_name[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(v_name[i])("_")}
                    printf("%s%s%s%s=\"%s\"\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |
      sed -e 's/_=/+=/g' \
        -e '/\..*=/s|\.|_|' \
        -e '/\-.*=/s|\-|_|'
  ) <"$yaml_file"
}
function create_variables() {
  oldPath=$(pwd)
  cd "${SCRIPT_PATH}" || {
    echo "Failed to get script directory"
    exit 1
  }
  tempYmlFile=.application${RUN_TIME}.yml
  parse_yaml "$1" >"${tempYmlFile}"
  # shellcheck disable=SC2162
  while read line || [[ -n ${line} ]]; do
    # shellcheck disable=SC2001
    line_key="$(echo "${line%%=*}" | sed 's/\ //g')"
    line_key=${line_key//-/_}
    line_value="$(echo "${line#*=}" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g')"
    if [ ${#line_value} -ge 2 ]; then
      if echo "${line_key}" | grep -Eq "collection_log_files"; then
        :
      else
        eval "${line_key}=\"${line_value}\""
      fi
    fi
  done <"${tempYmlFile}"
  rm -rf "${tempYmlFile}"
  cd "${oldPath}" || {
    echo "Failed to get script directory"
    exit 1
  }
}
function download_java() {
  create_request_variables
  echo "starting download java."
  if [[ -n "${download_cmd}" ]]; then
    if ! $download_cmd "download-java-${RUN_TIME}.tar" "http://${agentControlCenter}/${downloadJavaApi}?osType=linux&arch=$(uname -m)"; then
      echo "Error: Failed to download the latest Java archive."
      exit 1
    fi
  else
    if ! tcp_request -0 "download-java-${RUN_TIME}.tar" "http://${agentControlCenter}/${downloadJavaApi}?osType=linux&arch=$(uname -m)"; then
      echo "Error: Failed to download the latest Java archive."
      exit 1
    fi
  fi

  if ! tar -xvf "download-java-${RUN_TIME}.tar" -C "${SCRIPT_PARENT_PATH}" >/dev/null; then
    echo "Error: Failed to extract the Java archive."
    exit 1
  fi
  if test -r "download-java-${RUN_TIME}.tar"; then
    rm -rf "download-java-${RUN_TIME}.tar"
  fi
  javaPath="${SCRIPT_PARENT_PATH}/java/bin/java"
}

function export_java() {
  javaPath=$(realpath -m  "$(which "${javaPath}")")
  javaHome=$(dirname "$(dirname "${javaPath}")")
  export JAVA_HOME="${javaHome}"
  export PATH=$JAVA_HOME/bin:$PATH
}

function check_java() {
  # shellcheck disable=SC2001
  java_check_version="$(echo "${javaUseVersion}" | sed 's/\([0-9]*\.[0-9]*\)\..*/\1/')"
  if command -v "${javaPath}" > /dev/null; then
    java_version=$($javaPath -version 2>&1 | awk -F '"' '/version/ {print $2}' | sed 's/\([0-9]*\.[0-9]*\)\..*/\1/')
    if [[ "$java_version" == "${java_check_version}" ]]; then
      return 0 # 返回成功
    fi
  fi
  # 如果java命令不存在或者版本不是1.8，则重新设置javaPath变量
  javaPath="${SCRIPT_PARENT_PATH}/java/bin/java"
  # 再次检查java命令是否存在并获取版本号
  if command -v "${javaPath}" > /dev/null; then
    java_version=$($javaPath -version 2>&1 | awk -F '"' '/version/ {print $2}' | sed 's/\([0-9]*\.[0-9]*\)\..*/\1/')
    if [[ "$java_version" == "${java_check_version}" ]]; then
      return 0 # 返回成功
    fi
  fi
  if ${enableAgentManage}; then
    download_java
  else
    echo "当前环境下找不到java，请检查配置" >&2
    exit 1
  fi
}

function log_project() {
  if test -r "${runLogPath}.log"; then
    tail -30f "${runLogPath}.log"
  else
    echo "没有找到日志文件 ${runLogPath}.log"
    exit 1
  fi
}

function clear_log(){
  local maxsize
  maxsize=$(awk "BEGIN { printf \"%.0f\", ${runLogFileMaxSize} * 1024 * 1024 }")
  if  [[ -r "${runLogPath}.log" && ${maxsize} -ge 0 ]]; then
    local file_size
    # shellcheck disable=SC2012
    file_size="$(ls -l "${runLogPath}.log" | awk '{ print $5 }')"
    if [ "${file_size}" -gt "${maxsize}" ]; then
      if [[ "$runLogBacks" -gt 0 ]]; then
        if [ ! -d "${runLogFilePath}/old-run-log" ]; then
         mkdir -p "${runLogFilePath}/old-run-log"
        fi
        local count
        # shellcheck disable=SC2012
        count=$(ls -l "${runLogFilePath}/old-run-log"/* 2>/dev/null | wc -l)
        if [ "${count}" -ge "$runLogBacks" ]; then
           # shellcheck disable=SC2012
           ls -lt "${runLogFilePath}/old-run-log" | tail -n+$((runLogBacks+1)) | awk '{print $9}' | xargs -I {} bash -c "echo \"clear back-up log: ${runLogFilePath}/old-run-log/{}\"; rm \"${runLogFilePath}/old-run-log/{}\""
        fi
        local backUpLogPath="${runLogFilePath}/old-run-log/${RUN_TIME}.log"
        cp "${runLogPath}.log" "${runLogFilePath}/old-run-log/${RUN_TIME}.log"
        if command -v tar > /dev/null 2>&1; then
         if tar -zcf "${runLogFilePath}/old-run-log/${RUN_TIME}.tar.gz" -C "${runLogFilePath}/old-run-log" "${RUN_TIME}.log"; then
           rm -rf "${runLogFilePath}/old-run-log/${RUN_TIME}.log"
           backUpLogPath="${runLogFilePath}/old-run-log/${RUN_TIME}.tar.gz"
         fi
        fi
        echo "back-up log: ${backUpLogPath}"
      fi
      echo "清空 ${runLogPath}.log 文件内容"
      cat /dev/null > "${runLogPath}.log"
    else
      echo "日志文件 ${runLogPath}.log 的大小 小于配置的 ${runLogFileMaxSize} M 无需清理"
    fi
  else
    echo "日志文件 ${runLogPath}.log 不存在, 或配置runLogFileMaxSize为0不限制日志大小,不做清理处理"
  fi
}

function start_project() {
  check_pid
  [[ -n ${PID} ]] && echo -e "启动项目:\033[33m 项目 正在运行 !进程PID为 ${PID} \033[0m" && exit 0
  check_java
  export_java
  if [[ ! -f "${jarPath}/${jarName}" ]]; then
      echo -e "\033[31m 没有找到指定运行的jar包: ${jarPath}/${jarName} \033[0m"
      exit 1
  fi
  startCmd="${javaPath} -jar ${javaOptions} ${jarPath}/${jarName}"
  echo
  echo -e "\033[44;37m ======================================== \n || startCmd: ${startCmd} \n || log file: ${runLogPath}.log \n ======================================== \033[0m"
  echo
  cd "${jarPath}" || {
    echo "Failed to get script directory"
    exit 1
  }
  clear_log
  eval "nohup bash -c \"${startCmd}\" >> ${runLogPath}.log  2>&1 &"
  sleep ${startsecs}
  check_pid
  if [ -z "${PID}" ]; then
    echo -e "启动项目:\033[31m 项目运行失败，没有找到进程 \033[0m"
  else
    echo -e "启动项目:\033[32m 项目运行成功 PID:${PID} \033[0m"
  fi
}

function stop_project() {
  check_pid
  if [ -z "${PID}" ]; then
    echo -e "\n停止运行: \033[33m 项目 未运行 !\n \033[0m"
  else
    cd "${jarPath}" || {
      echo "Failed to get script directory"
      exit 1
    }
    for pid in ${PID}; do
      kill -kill "$pid"
    done
    sleep ${startsecs}
    check_pid
    if [ -z "${PID}" ]; then
      echo -e "\n停止运行:\033[32m 项目 退出成功 !\n \033[0m"
    else
      echo -e "\n停止运行:\033[31m 项目 退出失败 ! 项目运行PID:${PID}\n \033[0m" && exit 1
    fi
  fi
}

function status_project() {
  echo
  echo -e "\033[44;37m ========================================\n || ps grep : ${jarName} \n ======================================== \033[0m"
  echo
  check_pid
  if [ -z "${PID}" ]; then
    echo -e "\033[31m \n项目 未运行 !\n \033[0m"
  else
    echo -e "\033[32m \n项目 正在运行 ! 项目运行PID:${PID}\n \033[0m"
  fi
  exit 0
}

function restart_project() {
  stop_project
  start_project
}


function update_project() {
  if ${enableAgentManage}; then
    create_request_variables
      if [[ -n "${http_cmd}" ]]; then
        if ! expected_response=$($http_cmd "http://${agentControlCenter}/${checkVersionApi}"); then
          echo "Error: Failed to get latest version."
          exit 1
        fi
      else
        if ! expected_response=$(tcp_request "http://${agentControlCenter}/${checkVersionApi}"); then
          echo "Error: Failed to get latest version."
          exit 1
        fi
      fi
      if [ "${expected_response:0:8}" == "version=" ] ;then
        latest_version=${expected_response:8}
      else
        echo "Error: Failed to get latest version."
        exit 1
      fi

      if [ -r $"version" ]; then
        current_version=$(cat version)
      else
        current_version=-1
      fi

      if [ ${current_version} == -1 ] || [ "$latest_version" != "$current_version" ]; then
        # download the latest jar file and check if the download was successful
        if [[ -n "${download_cmd}" ]]; then
          if ! $download_cmd "download-${RUN_TIME}.jar" "http://${agentControlCenter}/${downloadAgentApi}"; then
            echo "Error: Failed to download latest jar file.update error"
            exit 1
          fi
        else
          if ! tcp_request -0 "download-${RUN_TIME}.jar" "http://${agentControlCenter}/${downloadAgentApi}"; then
            echo "Error: Failed to download latest jar file.update error"
            exit 1
          fi
        fi
        if ! command -v unzip &>/dev/null; then
          echo "无法找到 unzip 命令，跳过检查jar包"
        else
          tmp_dir=$(mktemp -d)
          # 解压 jar 包到临时目录
          if unzip "download-${RUN_TIME}.jar" -d "$tmp_dir" >/dev/null; then
            # 检查解压后的目录中是否包含必要的类文件和配置文件
            if [ -f "$tmp_dir/META-INF/MANIFEST.MF" ]; then
              echo "下载的文件可以正常运行"
              rm -rf "$tmp_dir"
            else
              echo "下载的文件缺少必要的类文件或配置文件，更新失败"
              rm -rf "$tmp_dir"
              exit 1
            fi
          else
            echo "文下载的文件解压失败，更新失败"
            rm -rf "$tmp_dir"
            exit 1
          fi
        fi
        if test -r "${jarName}"; then
          if [ ! -d "old-jar" ]; then
            mkdir old-jar
          fi
          mv "${jarName}" "old-jar/${jarName%.jar}_old_${RUN_TIME}.jar"
        fi
        # replace the old jar file with the new one
        mv "download-${RUN_TIME}.jar" "${jarName}"
        echo "Successfully updated to version $latest_version."
        if [ ! -r "config/application.yml" ]; then
          mkdir config

          if [[ -n "${download_cmd}" ]]; then
            $download_cmd config/application.yml "http://${agentControlCenter}/${downloadAgentDefaultConfigApi}"
          else
            tcp_request -0 config/application.yml "http://${agentControlCenter}/${downloadAgentDefaultConfigApi}"
          fi
        fi
      else
        echo "Already up-to-date with the latest version."
      fi
  elif ${enableGit}; then
      git_init_project
      git pull
      mvn clean
      mvn package
      if [ $? -eq 0 ]; then
        if test -r "${jarPath}/${jarName}"
        then
          if [ ! -d "${jarPath}/old-jar" ]; then
            mkdir -p "${jarPath}/old-jar"
          fi
          mv "${jarPath}/${jarName}" "${jarPath}/old-jar/${jarName%.*}-${RUN_TIME}.jar"
        fi
        if [[ -z "${mvnPackageTarget}" ]]; then
            mvnPackageTarget="target/${jarName%.*}*.jar"
        fi
        mv "${javaSourceCodePath}/${gitProjectName}/${mvnPackageTarget}" "${jarPath}/${jarName}"
        echo '项目更新成功！请执行命令重启'
      else
        echo '项目打包失败！'
      fi
  else
    help_fun
  fi

  exit 0
}
git_init_project()
{
  check_java
  export_java
	if [ ! -d "${javaSourceCodePath}" ]; then
		mkdir -p "${javaSourceCodePath}"
	fi
  if [[ -z "${gitProjectName}" ]]; then
      gitProjectName=${jarName%.*}
  fi
	if [ ! -d "${javaSourceCodePath}/${gitProjectName}" ]; then
		echo '项目源代码文件夹不存在'
		cd "${javaSourceCodePath}" || {
        echo -e "\033[31m 无法进入指定目录: ${javaSourceCodePath} \033[0m"
        exit 1
      }
		echo '正在下载项目源代码'
		git clone "$gitPath"
	fi
	if [ ! -d "${javaSourceCodePath}/${gitProjectName}" ]; then
		echo '项目代码文件夹未下载成功，请检查原因'
		exit 1
	else
		cd "${javaSourceCodePath}/${gitProjectName}" || {
            echo -e "\033[31m 无法进入指定目录: ${javaSourceCodePath} \033[0m"
            exit 1
          }
		### 检查切换分支 start ####
		isHead=$(git rev-parse --abbrev-ref HEAD | grep "${gitBranch}$")
		if [ -z "${isHead}" ]
		then
			hasLocalBranch=$(git branch |grep "${gitBranch}$")
			if [ -z "${hasLocalBranch}" ]
			then
				hasRangeBranch=$(git branch -r |grep "${gitBranch}$")
				if [ -z "${hasRangeBranch}" ]
				then
					echo "远程没有这个分支请检查"
					exit 1
				else
					git checkout -b "${gitBranch} origin/${gitBranch}"
				fi
			else
				git checkout "${gitBranch}"
			fi
		fi
		### 检查切换分支 end ####
	fi
}

function enable_schedule_task() {
  shellFilePath=${SCRIPT_PATH}/${SCRIPT_NAME}
  local clearLogTaskName="${SCRIPT_NAME}-clear-log task"
  local projectTaskName="${SCRIPT_NAME} task"
  if [ -r /etc/crontab ] && [ -w /etc/crontab ]; then
    if grep -q "${clearLogTaskName}" /etc/crontab; then
      echo "定时任务 ${clearLogTaskName} 已存在，不需要进行定时任务开启操作"
    else
      echo "写入定时任务${clearLogTaskName}:${RUN_TIME}"
      echo "${clearLogFileCron} root bash -c \"echo '${clearLogTaskName}';${shellFilePath} clear-log\" >> ${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}-clear-log.log 2>&1" >>/etc/crontab && echo "定时任务 ${clearLogTaskName} 开启成功"
    fi
    if grep -q "${projectTaskName}" /etc/crontab; then
      echo "定时任务 ${projectTaskName} 已存在，不需要进行定时任务开启操作"
    else
      echo "写入定时任务${projectTaskName}:${RUN_TIME}"
      echo "${projectKeepAliveCron} root bash -c \"echo '${projectTaskName}';${shellFilePath} start\" >> ${SCRIPT_PATH}/crontab-${SCRIPT_NAME%\.*}.log 2>&1" >>/etc/crontab && echo "定时任务 ${projectTaskName} 开启成功"
    fi
  else
    echo "无法读写/etc/crontab文件,无法进行定时任务开启操作"
  fi
}

function disable_schedule_task() {
  local clearLogTaskName="${SCRIPT_NAME}-clear-log task"
  local projectTaskName="${SCRIPT_NAME} task"
  if [ -r /etc/crontab ] && [ -w /etc/crontab ]; then
    if grep -q "${clearLogTaskName}" /etc/crontab; then
      sed -i "/${clearLogTaskName//\//\\/}/d" /etc/crontab &&
      echo -e "\033[31m 定时任务 ${clearLogTaskName} 已关闭 \033[0m"
    else
      echo "定时任务 ${clearLogTaskName} 不存在，无法进行定时任务关闭操作"
    fi
    if grep -q "${projectTaskName}" /etc/crontab; then
      sed -i "/${projectTaskName//\//\\/}/d" /etc/crontab &&
      echo -e "\033[31m 定时任务 ${projectTaskName} 已关闭 \033[0m"
    else
      echo "定时任务 ${projectTaskName} 不存在，无法进行定时任务关闭操作"
    fi
  else
    echo "无法读写/etc/crontab文件,无法进行定时任务关闭操作"
  fi
  exit 0
}

function renew_script() {
  create_request_variables
  if ! $download_cmd "new_${SCRIPT_NAME}" "http://${agentControlCenter}/${downloadAgentScriptApi}?osType=linux";then
    echo "Error: Failed to download the latest agent Script."
    exit 1
  fi

  if [ ! -f "new_${SCRIPT_NAME}" ]; then
      echo "Error: Failed to download the latest agent Script,download file not found"
      exit 1
  fi

  # 检查文件的头部shebang标记
  if head -n 1 "new_${SCRIPT_NAME}" | grep -q "^#!.*sh"; then
      # 检查语法是否正确
      if bash -n "new_${SCRIPT_NAME}"; then
           mv "new_${SCRIPT_NAME}" "${SCRIPT_NAME}"
          chmod +x "${SCRIPT_NAME}"
      else
          rm -rf "new_${SCRIPT_NAME}"
          echo "Error: Failed to download the latest agent Script,Syntax error"
          exit 1
      fi
  else
      rm -rf "new_${SCRIPT_NAME}"
      echo "Error: Failed to download the latest agent Script,Not a shell script"
      exit 1
  fi

  if [ ! -r "${CONFIG_FILE}" ]; then
    if ! $download_cmd "${CONFIG_FILE}" "http://${agentControlCenter}/${downloadAgentScriptConfigApi}";then
      echo "Error: Failed to download the latest agent Script config file."
    fi
  fi
  echo "脚本更新完毕"
  exit 0
}


function undeploy() {
  echo "关闭定时任务"
  disable_schedule_task
  echo "停止程序"
  stop_project
  echo "删除所有文件"
  cd "${SCRIPT_PATH}" || {
    echo "Failed to get script directory"
    exit 1
  };
  mkdir del_old
  mv ./* ./del_old
  mv ./del_old/agentAction* ./
  rm -rf ./del_old
  echo "卸载完成"
  exit 0
}

function generate_conf_template() {
    cat > "${SCRIPT_PATH}/${SCRIPT_NAME%\.*}-${RUN_TIME}.conf" <<EOF
# 项目运行的java环境，默认使用本机 java环境,不符合版本则会在脚本的上级目录寻找java名称的java目录，以上均没有并且开启agent管理的情况下会下载java使用
javaPath=java
# 指定java的使用版本进行判断。默认是1.8
# javaUseVersion=1.8
# 项目jar包所在目录，默认为脚本所在目录
# jarPath=
# 项目jar包名称
jarName=run.jar
# 项目启动的jvm配置, 默认为 -server -Xms128m -Xmx256m
# javaOptions=-server -Xms128m -Xmx256m
# 检查项目是否启动获取pid前等待秒数，默认是3s
# startsecs=3
# 查询项目进程的方法类型，默认值为 name，可选 port
# processCheckType=name
# 查询项目进程的名称，默认是项目jar包名称
# processName=
# 查询项目进程的端口，如果 processCheckType 配置为 port 则必须指定端口
# processPort=
# 项目名称默认为脚本名称
# projectName=
# 项目运行输出日志文件所在目录，默认为脚本所在目录
# runLogFilePath=
# 项目运行输出日志文件名称，默认为项目名
# runLogFileName=
# 指定运行日志文件记录大小限制，单位为Mb，默认值为：10，如果超过限制大小就会清空日志文件，开启备份会在备份后清空，设置为0，则不限制大小
# runLogFileMaxSize=10
# 备份保留运行日志个数，默认为0，当大于0的时候开启备份
# runLogBacks=0
# 开启定时任务后，监测项目运行保活的cron，默认为 */5 * * * *
# projectKeepAliveCron=*/5 * * * *
# 开启定时任务后，定时检查清理备份日志的cron，默认为 0 1 * * *
# clearLogFileCron=0 1 * * *
# 开启 agent 控制,默认是 false
# enableAgentManage=false
# agent 控制中心地址
# agentControlCenter=127.0.0.1:8766
# agent 控制中心 获取agent版本的API
# checkVersionApi=api/agent-manage/agent-last-version
# agent 控制中心 获取agent控制脚本的API
# downloadAgentScriptApi=api/agent-manage/agent-script-download
# agent 控制中心 获取agent控制脚本配置文件的API
# downloadAgentScriptConfigApi=api/agent-manage/agent-script-config-download
# agent 控制中心 获取agent jar包的API
# downloadAgentApi=api/agent-manage/agent-download
# agent 控制中心 获取agent默认配置文件的API
#downloadAgentDefaultConfigApi=api/agent-manage/agent-default-yml-download
# agent 控制中心 获取agent默认配置文件的API
# downloadJavaApi=api/agent-manage/java-download
EOF
  echo "模板配置文件已创建完成: ${SCRIPT_PATH}/${SCRIPT_NAME%\.*}-${RUN_TIME}.conf "
}

function help_fun() {
  cat  <<EOF >&2

usage: ${SCRIPT_NAME} [options...]
Options:
  start           启动项目
  stop            停止项目
  status          查看项目状态
  restart         重启项目
  enable          启动项目监测保活操作以及定时日志清理备份
  disable         关闭项目监测保活操作以及定时日志清理备份
  log             查看项目运行日志
  clear-log       清理项目运行日志，只有日志大于 ${runLogFileMaxSize}M 时才会被清空
  create-conf     创建配置文件
  help            查看命令使用方式
  update          更新项目-只有项目开启agent管控中心管理或者配置了git相关时生效
  renewScript     更新运行脚本文件-只有项目开启agent管控中心管理是生效
  undeploy        卸载项目

EOF
}

echo
echo -e "\033[34m ### 欢迎使用 ${SCRIPT_NAME} 脚本, 运行时间为: ${RUN_TIME} ### \033[0m"
echo

action="$1"

case "$action" in
  help)
    help_fun
    exit 1
    ;;
  create-conf)
    generate_conf_template
    exit 1
    ;;
esac

read_config_file "${CONFIG_FILE}"

case "$action" in
  start)
    start_project
    ;;
  stop)
    stop_project
    ;;
  status)
    status_project
    ;;
  restart)
    restart_project
    ;;
  enable)
    enable_schedule_task
    ;;
  disable)
    disable_schedule_task
    ;;
  update)
    update_project
    ;;
  renewScript)
    if ${enableAgentManage}; then
      renew_script
    else
      help_fun
    fi
    ;;
  undeploy)
    undeploy
    ;;
  log)
    log_project
    ;;
  clear-log)
    clear_log
    if [[ -f "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}-clear-log.log" ]]; then
      # shellcheck disable=SC2012
      file_size="$(ls -l -f "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}-clear-log.log" | awk '{ print $5 }')"
      maxsize=$(500000)
      if [ "${file_size}" -gt "${maxsize}" ]; then
         cat /dev/null > "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}-clear-log.log"
      fi
    fi
    if [[ -f "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}.log" ]]; then
      # shellcheck disable=SC2012
      file_size="$(ls -l -f "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}.log" | awk '{ print $5 }')"
      maxsize=$(500000)
      if [ "${file_size}" -gt "${maxsize}" ]; then
         cat /dev/null > "${runLogFilePath}/crontab-${SCRIPT_NAME%\.*}.log"
      fi
    fi
    ;;
  *)
    echo "${action}"
    echo "${SCRIPT_NAME}: 命令相关详情，请使用 '${SCRIPT_NAME} help' 查看"  >&2
    exit 1
    ;;
esac
