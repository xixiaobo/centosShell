#!/bin/bash

projectName='projectName'
projectVersion='0.0.1-SNAPSHOT'
javaSourceCodePath='/opt/javaSourceCode/'
gitPath='git@jar.git'
logName='zxfx.log'

pwdPath = `pwd`

projectPath=$pwdPath'/'$projectName
projectJar=$projectName-$projectVersion'.jar'

time=$(date "+%Y%m%d%H%M%S")

check_pid(){
  PID=`ps -ef|grep "$projectPath/$projectJar" |grep -v grep | awk '{print $2}'`
}

start_project(){
  check_pid
  [[ ! -z ${PID} ]] && echo -e "项目 正在运行 !" && exit 1
  init_project
  if test -r "${logName}" 
	then
		mv "${logName}" "${logName}-${time}"
	fi
  nohup java -Xms$javaXms -Xmx$javaXmx -jar $projectPath/$projectJar  >$projectPath/$logName 2>&1 &
  check_pid
  echo "项目运行PID：${PID}"
}

stop_porject(){
	check_pid
	[[ -z ${PID} ]] && echo -e "项目 未运行 !" && exit 1
	ps -ef|grep "$projectPath/$projectJar" |grep -v grep | awk '{print $2}' |xargs kill -kill
}
restart_project(){
	check_pid
	[[ ! -z ${PID} ]] && ps -ef|grep "$projectPath/$projectJar" |grep -v grep | awk '{print $2}' |xargs kill -kill 
	init_project
	if test -r "${logName}" 
	then
		mv "${logName}" "${logName}-${time}"
	fi
	nohup java -Xms$javaXms -Xmx$javaXmx -jar $projectPath/$projectJar  >> $projectPath/$logName  2>&1 &
	check_pid
	echo "项目运行PID：${PID}"
}
update_project()
{
	init_project
	if [ ! -d $javaSourceCodePath/$projectName ]; then
		echo '项目代码文件夹未下载成功，请检查原因'
	else
		cd $javaSourceCodePath/$projectName
		git pull
		mvn package
		if [ $? -eq 0 ]; then
			mv $projectPath/$projectJar $projectPath/${projectJar%.*}-$time.jar
			mv $javaSourceCodePath/$projectName/target/$projectJar $projectPath
			restart_project
		else
			echo '项目打包失败！'
		fi
	fi
}
init_project(){
	isPackage= false
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
		echo '项目源代码下载完成，正在打包'
		mvn package
		if [ $? -eq 0 ]; then
			mv $projectPath/$projectJar $projectPath/${projectJar%.*}-$time.jar
			mv $javaSourceCodePath/$projectName/target/$projectJar $projectPath
			echo '项目打包结束'
		else
			echo '项目打包失败！'
		fi
		isPackage=true
	else
		echo '找到项目源代码'
	fi
}

case "$1" in

 start)
        start_project
 ;;

 stop)
        stop_porject
 ;;

 status)
        check_pid
        [[ ! -z ${PID} ]] && echo -e "项目 正在运行 !" && exit 1
        [[ -z ${PID} ]] && echo -e "项目 未运行 !" && exit 1
 ;;

 restart)
        restart_project
 ;;

 update)
        update_project
 ;;

 *)
   echo "Usage: $0 {start|stop|restart|status|update}"
 ;;

esac
