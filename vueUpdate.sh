#!/bin/bash
projectName='ctgcdn_web'
vueSourceCodePath='/opt/vueSourceCode'
packageName='dist'
nginxHtmlPath='/usr/local/nginx1.16/html'
gitPath='git@118.190.65.73:cdn_cds/ctgcdn_web.git'

time=$(date "+%Y%m%d%H%M%S")

check_pid(){
  PID=`ps -ef|grep 'nginx -c /etc/nginx/nginx.conf' |grep -v grep | awk '{print $2}'`
}

init_project(){
	isPackage= false
	if [ ! -d $vueSourceCodePath ]; then
		mkdir -p $vueSourceCodePath
	fi
	if [ ! -d $nginxHtmlPath ]; then
		mkdir -p $nginxHtmlPath
	fi
	if [ ! -d $vueSourceCodePath/$projectName ]; then
		echo '项目源代码文件夹不存在'
		cd $vueSourceCodePath
		echo '正在下载项目源代码'
		git clone $gitPath
		echo '项目源代码下载完成'
		isPackage=true
	else
		echo '找到项目源代码'
	fi
}

start_project(){
  check_pid
  [[ ! -z ${PID} ]] && echo -e "项目 正在运行 !" && exit 1
  nginx -c /etc/nginx/nginx.conf
  check_pid
  echo "项目运行PID：${PID}"
}

stop_porject(){
	check_pid
	[[ -z ${PID} ]] && echo -e "项目 未运行 !" && exit 1
	nginx -s stop
}

restart_project(){
	check_pid
	[[ -z ${PID} ]] && echo -e "项目 未运行 !"  && nginx -c /etc/nginx/nginx.conf && check_pid && echo "项目运行PID：${PID}" && exit 1
	nginx -s reload
	check_pid
	echo "项目运行PID：${PID}"
}

update_project()
{
	init_project
	if [ ! -d $vueSourceCodePath/$projectName ]; then
		echo '项目代码文件夹未下载成功，请检查原因'
	else
		cd $vueSourceCodePath/$projectName
		git pull
		npm run build
		if [ $? -eq 0 ]; then
			mv $nginxHtmlPath/$packageName $nginxHtmlPath/$packageName-$time
			mv $vueSourceCodePath/$projectName/$packageName $nginxHtmlPath/
			restart_project
		else
			echo '项目打包失败！'
		fi
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

