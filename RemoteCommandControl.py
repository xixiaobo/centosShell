#!/usr/bin/python
# -*- coding: utf-8 -*-
# coding:utf-8
from flask_cors import CORS
import sys
from flask import Flask, request, redirect
import json
import commands

app = Flask(__name__)
CORS(app)
reload(sys)

sys.setdefaultencoding('utf8')

allUserCommandsPath = {}

UserInfo ={
    "admin": "adminPassWord",
    "test": "testPassWord",
}

def get_post_data():
    """
    从请求中获取参数
    :return:
    """
    data = {}
    if request.content_type.startswith('application/json'):
        data = request.get_data()
        data = json.loads(data)
    else:
        for key, value in request.form.items():
            if key.endswith('[]'):
                data[key[:-2]] = request.form.getlist(key)
            else:
                data[key] = value

    return data


@app.route('/getAllUserCommandsPath', methods=['GET'])
def test():
    return allUserCommandsPath


@app.route('/remote-control/<userName>', methods=['POST'])
def register(userName):
    """
        path:userName连接用户名（必填）
        body:{
            passWord：连接用户密码（必填）,
            command: 执行命令
            path: 执行命令所在目录地址
        }
    """
    result = {'code': 400}
    data = get_post_data()
    if userName not in UserInfo:
        result['massage'] = ["用户不存在！"]
        return result
    if data.get("passWord", "") == UserInfo[userName]:
        result['massage'] = ["密码错误！"]
        return result
    path = '/'
    if userName in allUserCommandsPath:
        path = allUserCommandsPath[userName]
    allUserCommandsPath[userName] = data.get("path", path)
    command = 'cd ' + path + " && " + data.get("command", "") + " ; pwd"
    result['code'], b = commands.getstatusoutput(command)
    allUserCommandsPath[userName] = b.splitlines()[-1]
    result['massage'] = b.splitlines()[0:-1]
    return result


'''运行ip地址及端口'''
if __name__ == '__main__':
    app.run(
        host='0.0.0.0',
        port=19099,
        debug=True
    )
