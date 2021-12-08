#!/bin/bash
##### shell脚本所在目录 #####
shellPath=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)

##### shell脚本名称 #####
shellName=$(basename $BASH_SOURCE)

##### shell脚本所在目录的上级目录 #####
dname=`dirname "$shellPath"`

## 项目名称 ##
projectName='test'
## 项目版本 ##
projectVersion='1.0.0-SNAPSHOT'

## 项目git地址 ##
gitPath='https://username:password@git@ip:project.git'
#gitPath='https://username:password@ip:project'
## 项目git分支 默认 master##
gitBranch='1.0.0-SNAPSHOT'

## 项目运行地址，默认脚本所在地址 ##
projectPath=$shellPath
## 项目源代码路径， 默认将在项目运行目录下创建 source 存储 ##
javaSourceCodePath=$projectPath/source
## 项目jar包，默认项目名称加版本号 ##
projectJar=$projectName-$projectVersion'.jar'
## 项目运行日志，默认项目运行地址下+zxfx ##
runLogPath=${projectPath}/zxfx

## 项目进程查询内容，默认项目地址加项目jar包 ##
processMonitoring=$projectPath/$projectJar

## 项目运行命令，默认 java -jar 加 分配内存 加 项目运行地址 加 项目jar包 ##
startCmd="java -Xms10m -Xmx200m -jar $projectPath/$projectJar"

## 项目运行类型 nohup（后台运行并写入日志）， daemon（前台运行并写入日志），no（直接运行也不写入日志）##
startType="nohup"

## 项目停止命令，根据进程id kill ##
stopCmd="ps -ef|grep '${processMonitoring}' |grep -v grep | awk '{print \$2}' |xargs kill -kill"

## 项目重启命令，默认先停止运行在启动，默认值 no ##
restartCmd='no'



echo 
echo -e "\033[34m ### 欢迎使用 ${shellName} 脚本,本次运行的相关项目为: ${projectName} ### \033[0m"
echo 


time=$(date "+%Y%m%d%H%M%S")

check_pid(){
  sleep 3
  PID=`ps -ef|grep "$processMonitoring" |grep -v grep | awk '{print $2}'`
}

start_project(){
	check_pid
	[[ ! -z ${PID} ]] && echo -e "启动项目：\033[33m 项目 正在运行 !进程PID为 ${PID} \033[0m" && exit 1
	aw="${*:2}"
	echo
	echo -e "\033[44;37m ======================================== \n || startCmd: ${startCmd} ${aw[*]} \n ======================================== \033[0m"
	echo
	if test -r "${runLogPath}.log" 
	then
		if [ ! -d ${projectPath}/old-run-log ]; then
			mkdir -p ${projectPath}/old-run-log
		fi
		mv "${runLogPath}.log" "${projectPath}/old-run-log/${time}.log"
	fi
	if [[ "$startType" == "nohup" ]];then
		echo -e "\033[32m 运行模式：后台运行 \033[0m"
		eval "nohup  $startCmd ${aw[*]} >> ${runLogPath}.log  2>&1 &"
	elif [[ "$startType" == "daemon" ]];then
		echo -e "\033[32m 运行模式：前台运行 \033[0m"
		eval "$startCmd ${aw[*]} >> ${runLogPath}.log  2>&1"
	elif [[ "$startType" == "no" ]];then
		echo -e "\033[32m 运行模式：直接运行 \033[0m"
		eval "$startCmd ${aw[*]}"
	else
		echo -e "\033[31m 未知运行类型 \033[0m"
	fi
	
	echo -e "\033[44;37m ======================================== \n || log flie: ${runLogPath}.log \n ======================================== \033[0m"
	echo
	check_pid
	if [ -z ${PID} ]
	then
		echo -e "启动项目：\033[32m 项目运行失败，没有找到进程 \033[0m"
	else
		echo -e "启动项目：\033[32m 项目运行成功 PID：${PID} \033[0m" 
	fi  
}

stop_porject(){
	check_pid
	if [ -z ${PID} ]
	then
		echo -e "\n停止运行： \033[33m 项目 未运行 !\n \033[0m" 
	else
		eval "$stopCmd ${aw[*]}"
		check_pid
		if [ -z ${PID} ]
		then
			echo -e "\n停止运行：\033[32m 项目 退出成功 !\n \033[0m"
		else
			echo -e "\n停止运行：\033[31m 项目 退出失败 ! 项目运行PID：${PID}\n \033[0m"  && exit 1
		fi  
	fi  
}

restart_project(){
	if [[ "$restartCmd" == "no" ]];then
		stop_porject
		start_project $*
	else
		eval "$restartCmd ${aw[*]}"
	fi
}

update_project()
{
	init_project
	git pull
	mvn clean
	mvn package
	if [ $? -eq 0 ]; then
		if test -r "${projectPath}/${projectJar}" 
		then
			if [ ! -d $projectPath/old-jar ]; then
				mkdir -p $projectPath/old-jar
			fi
			mv $projectPath/$projectJar $projectPath/old-jar/${projectJar%.*}-$time.jar
		fi
		mv $javaSourceCodePath/$projectName/target/$projectJar $projectPath
		echo '项目更新成功！'
	else
		echo '项目打包失败！'
	fi
}

init_project()
{
	if [ ! -d $javaSourceCodePath ]; then
		mkdir -p $javaSourceCodePath
	fi
	if [ ! -d $projectPath ]; then
		mkdir -p $projectPath
	fi
	if [ ! -d $javaSourceCodePath/$projectName ]; then
		echo '项目源代码文件夹不存在'
		cd $javaSourceCodePath
		echo '正在下载项目源代码'
		git clone $gitPath	
	fi
	if [ ! -d $javaSourceCodePath/$projectName ]; then
		echo '项目代码文件夹未下载成功，请检查原因'
		exit 1
	else
		cd $javaSourceCodePath/$projectName
		### 检查切换分支 start ####
		isHead=`git rev-parse --abbrev-ref HEAD | grep "${gitBranch}$"`
		if [ -z "${isHead}" ]
		then
			hasLocalBranch=`git branch |grep "${gitBranch}$"`
			if [ -z "${hasLocalBranch}" ]
			then
				hasRangeBranch=`git branch -r |grep "${gitBranch}$"`		
				if [ -z "${hasRangeBranch}" ]
				then
					echo "远程没有这个分支请检查"
					exit 1
				else
					git checkout -b ${gitBranch} origin/${gitBranch}
				fi 
			else
				git checkout ${gitBranch}
			fi 
		fi 
		### 检查切换分支 end ####
	fi
}

case "$1" in

 start)
        start_project $*
 ;;

 stop)
        stop_porject
 ;;

 status)
        echo
		echo -e "\033[44;37m ========================================\n || ps grep : ${processMonitoring} \n ======================================== \033[0m"
		echo
		check_pid
		if [ -z ${PID} ]
		then
			echo -e "\033[31m \n项目 未运行 !\n \033[0m"
		else
			echo -e "\033[32m \n项目 正在运行 ! 项目运行PID：${PID}\n \033[0m"
		fi
 ;;

 restart)
        restart_project $*
 ;;

 update)
        update_project $*
 ;;

 init)
        init_project
 ;;

 *)
   echo -e "\033[33m Usage: $shellName  {start|stop|restart|status|update|init} \033[0m"
 ;;

esac
