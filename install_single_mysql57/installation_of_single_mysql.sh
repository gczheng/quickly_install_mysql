#!/bin/bash
# line:           V1.9
# mail:           gczheng@139.com
# data:           2018-11-19
# script_name:    installation_of_single_mysql.sh
# function:       Install mysql5.7
. ./install_single.conf
#=======================================================================
#配置信息
#=======================================================================
#MYSQL_DATADIR=/data/mysqldata
#MYSQL_UNDODIR=/data/undolog 
MYCNF=install-my.cnf
#MYSQL_SOURCE_PACKAGES=/software/mysql-5.7.18-linux-glibc2.5-x86_64.tar.gz
MYSQL_SOURCE_PACKAGES_NAMES=`echo $MYSQL_SOURCE_PACKAGES |awk -F '/' '{print $NF}' |awk -F ".tar.gz" '{printf $1}'`
#MYSQL_DOWNLOAD_LINK='https://downloads.mysql.com/archives/get/file/mysql-5.7.18-linux-glibc2.5-x86_64.tar.gz'
MYSQL=/usr/local/mysql/bin/mysql
#MSYQL_PACKAGES_MD5=ebc8cbdaa9c356255ef82bd989b07cfb
MEM_SIZE=`dmidecode -t memory | sed 's/^[ \t]*//g'|grep -i '^size'|egrep -iv "NOT|NO|Installed|Enabled"|awk -F : '{print $2}'|awk '{sum += $1};END {print sum/1024}'`
BUFFER_POOL_SIZE=`expr ${MEM_SIZE} / 2`
SERVER_ID=`ip route | awk '/src/ && !/docker/{for(i=1;i<=NF;++i)if($i == "src"){print $(i+1)}}' |head -n 1 |awk -F '.' '{print $3$4}'`
CPU_CORE_NUMS=`cat /proc/cpuinfo |grep 'processor'|wc -l`
#=======================================================================
# echo添加颜色
#=======================================================================
echo_color(){
    color=${1} && shift
    case ${color} in
        black)
            echo -e "\e[0;30m${@}\e[0m"
            ;;
        red)
            echo -e "\e[0;31m${@}\e[0m"
            ;;
        green)
            echo -e "\e[0;32m${@}\e[0m"
            ;;
        yellow)
            echo -e "\e[0;33m${@}\e[0m"
            ;;
        blue)
            echo -e "\e[0;34m${@}\e[0m"
            ;;
        purple)
            echo -e "\e[0;35m${@}\e[0m"
            ;;
        cyan)
            echo -e "\e[0;36m${@}\e[0m"
            ;;
        *)
            echo -e "\e[0;37m${@}\e[0m"
            ;;
    esac    # --- end of case ---
}

#=======================================================================
#检查安装包、脚本、my.cnf是否齐全
#=======================================================================

function chk_install_resource()
{
	#判断 install-my.cnf 是否存在
	if [ ! -f "$MYCNF" ];then
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') $MYCNF file is not exits!$(echo_warning)"
		exit 1
	fi
	#判断 MySQL Community Server 5.7 tar包是否存在
	if [ ! -f "$MYSQL_SOURCE_PACKAGES" ];then
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') $MYSQL_SOURCE_PACKAGES is not exits, Make a copy to the directory or please download it from $MYSQL_DOWNLOAD_LINK "
        read -p "Download the package from mysql(y/n):" dn
        case $dn in
            y|Y)
                wget -O  $MYSQL_SOURCE_PACKAGES  $MYSQL_DOWNLOAD_LINK
                ;;
            n|N)
                exit 1
                ;;
            *)
                echo_color red "$(date +'%Y-%m-%d %H:%M:%S') Input ERROR."
                exit 1
        esac
        echo_color green "$(date +'%Y-%m-%d %H:%M:%S') $MYSQL_SOURCE_PACKAGES is  exits ."
    fi
    # 判断md5值是否正确
    md5=`md5sum $MYSQL_SOURCE_PACKAGES | awk '{print $1}'`
    if [ "$MSYQL_PACKAGES_MD5" == "$md5" ];then
        echo_color green "$(date +'%Y-%m-%d %H:%M:%S') $MYSQL_SOURCE_PACKAGES md5 ok"
    else 
        echo_color red "$(date +'%Y-%m-%d %H:%M:%S') $MYSQL_SOURCE_PACKAGES md5 error"
        exit 1
    fi
}
#=======================================================================
# 添加帐号和目录
#=======================================================================
function create_sys_user()
{
	#添加mysql用户信息
	if id mysql &> /dev/null;then
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') MySQL user is exits."
	else
		useradd -r -s /bin/false mysql && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') The system user is added to success .."
	fi

	if [ ! -d "${MYSQL_DATADIR}" ];then
		mkdir -p ${MYSQL_DATADIR} && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL data directory is created .."
		chown -R mysql:mysql ${MYSQL_DATADIR}
		chmod 750 ${MYSQL_DATADIR}
	elif [ "$(ls -A ${MYSQL_DATADIR})" = "" ];then
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL data directory is exits."
	else
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') MySQL data directory is not empty. Please check it."
		exit 1
	fi

    if [ ! -d "${MYSQL_UNDODIR}" ];then
        mkdir -p ${MYSQL_UNDODIR} && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL undo directory is created .."
        chown -R mysql:mysql ${MYSQL_UNDODIR}
        chmod 750 ${MYSQL_UNDODIR}
    elif [ "$(ls -A ${MYSQL_UNDODIR})" = "" ];then
        echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL undo directory is exits."
    else
        echo_color red "$(date +'%Y-%m-%d %H:%M:%S') MySQL undo directory is not empty. Please check it."
        exit 1
    fi
}
#=======================================================================
#检查是否有旧的mysql/mariadb版本存在
#=======================================================================

function chk_old_mysql_version()
{
	mysqlNum=$(rpm -qa | grep -Ei '^mysql|^mariadb' |wc -l)
	if [ "${mysqlNum}" -gt "0" ];then
        rpm -qa | grep -Ei '^mysql|^mariadb'
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') The system has MySQL other version. There may be a conflict in the version！If it continues, the original database will be uninstall."
		read -p "Do you continue to install it(y/n):" cn
		case $cn in
			y|Y)
				rpm -qa | grep -Ei '^mysql|^mariadb' | xargs rpm -e --nodeps 
				source /etc/profile
				tar_install
				;;
			n|N)
				exit 1
				;;
			*)
				echo_color red "$(date +'%Y-%m-%d %H:%M:%S') Input ERROR."
		esac
	else
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') No old version was found."
		source /etc/profile
		tar_install
	fi
}

#=======================================================================
# 解压安装
#=======================================================================
function installPackage()
{
count=0
package=(gcc gcc-c++ bzip2 bzip2-devel bzip2-libs python-devel libaio libaio-devel ncurses ncurses-devel cmake numactl-libs)
nums01=${#package[@]}
for((i=0;i<nums01;i++));
do
        char=${package[$i]}
        rpm -qa | grep "^$char"
        if [ $? != 0 ] ; then
                error[$count]=${package[$i]}
                count=$(($count+1))
                echo_color red "$(date +'%Y-%m-%d %H:%M:%S') The ${package[$i]} is not installed.Please check it.."

        fi
done
if [ $count -gt "0" ];then
        echo "You have $count patchs are not installed." 
        echo "the not installed patch is:" 
        nums02=${#error[@]}
        for((ii=0;ii<nums02;ii++));
        do
                echo "${error[$ii]}^" 
        done
        echo -e  "Are you sure to install the patch[yes or no]:\c" 
        read select 
        if [ $select == "yes" ]; then
                for((is=0;is<nums02;is++));
                do
                        var=${error[$is]}
                        echo $var
                        yum install -y $var
                done
        fi
else
        echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Check pass!.."
fi
count=0
rpm -q gcc gcc-c++ bzip2 bzip2-devel bzip2-libs python-devel libaio libaio-devel ncurses ncurses-devel cmake numactl-libs | grep "not installed"
}

function tar_install()
{
	installPackage
	echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Starting unzip $MYSQL_SOURCE_PACKAGES .."
	tar zxvf $MYSQL_SOURCE_PACKAGES -C /usr/local/ 
	echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Unzip $MYSQL_SOURCE_PACKAGES SUCCESS .."
	if [ ! -d "/usr/local/mysql" ];then
		ln -s /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}  /usr/local/mysql
		chown -R mysql:mysql /usr/local/mysql
		chown -R mysql:mysql /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}
		chmod 750 /usr/local/mysql
		chmod 750 /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL package has been placed in the right position .."
		cp -f $MYCNF /etc/my.cnf
        sed -i 's:${MYSQL_UNDODIR}:'"${MYSQL_UNDODIR}:g"'' /etc/my.cnf
        sed -i 's:${MYSQL_DATADIR}:'"${MYSQL_DATADIR}:g"'' /etc/my.cnf
        sed -i 's:${BUFFER_POOL_SIZE}:'"${BUFFER_POOL_SIZE}:g"''  /etc/my.cnf
        sed -i 's:${SERVER_ID}:'"${SERVER_ID}:g"'' /etc/my.cnf
        sed -i 's/${CPU_CORE_NUMS}/'"${CPU_CORE_NUMS}/g"'' /etc/my.cnf
        /data/mysqldata/error.log
	else
		read -p "/usr/local/mysql install directory already exists, delete it, and continue(y/n):" dn
		case $dn in
			y|Y)
				rm -rf /usr/local/mysql
				ln -s /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}  /usr/local/mysql
				chown -R mysql:mysql /usr/local/mysql
				chown -R mysql:mysql /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}
				chmod 750 /usr/local/mysql
				chmod 750 /usr/local/${MYSQL_SOURCE_PACKAGES_NAMES}
				echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') MySQL package has been placed in the right position .."
				cp -f $MYCNF /etc/my.cnf
                sed -i 's:${MYSQL_UNDODIR}:'"${MYSQL_UNDODIR}:g"'' /etc/my.cnf
                sed -i 's:${MYSQL_DATADIR}:'"${MYSQL_DATADIR}:g"'' /etc/my.cnf
                sed -i 's:${BUFFER_POOL_SIZE}:'"${BUFFER_POOL_SIZE}:g"''  /etc/my.cnf
                sed -i 's:${SERVER_ID}:'"${SERVER_ID}:g"'' /etc/my.cnf
                sed -i 's/${CPU_CORE_NUMS}/'"${CPU_CORE_NUMS}/g"'' /etc/my.cnf
				;;
			n|N)
				exit 1
				;;
			*)
			echo_color red "$(date +'%Y-%m-%d %H:%M:%S') /usr/local/mysql is exits.Please check it."
		esac
	fi

	echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Starting initialization .."
	/usr/local/mysql/bin/mysqld --initialize --user=mysql  &> /dev/null && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Initialization ......SUCCESS"
}

#=======================================================================
# 修改环境变量
#=======================================================================
function add_system_profile()
{
cat >> /etc/profile <<EOF
export PATH=\$PATH:/usr/local/mysql/bin/
EOF
source /etc/profile
}


function add_mysql_ldconfig()
{
cat > /etc/ld.so.conf.d/mysql.conf <<EOF
/usr/local/mysql/lib
EOF
ldconfig
}

function add_libmysqlclient()
{
if [ -f /etc/ld.so.conf.d/mysql.conf ];then
	LDNUMS=`grep -i "/usr/local/mysql/lib" /etc/ld.so.conf.d/mysql.conf |wc -l`
	if [ $LDNUMS -eq 0 ];then
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') The configuration file is empty!"
		add_mysql_ldconfig
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Flush ldconfig done .."
	else
		LDEXISTS=`grep -i  "/usr/local/mysql/lib" /etc/ld.so.conf.d/mysql.conf |grep -e "^#" |wc -l`
		if [ $LDEXISTS -gt 0 ];then
			add_mysql_ldconfig
			echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Has been configured!"
		fi
	fi
else
	echo_color red "$(date +'%Y-%m-%d %H:%M:%S') /etc/ld.so.conf.d/mysql.conf is not exits!"
	add_mysql_ldconfig
	echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Flush ldconfig done .."
fi
}


function modify_system_env()
{
#egrep "/usr/local/mysql/bin/" /etc/profile  &> /dev/null
PROFILES=`grep -i  "/usr/local/mysql/bin/" /etc/profile |wc -l`
if [ $PROFILES -eq 0 ];then
	add_system_profile
	echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Flush profile done .."
else
	EXISTS=`grep -i  "/usr/local/mysql/bin/" /etc/profile |grep -e "^#" |wc -l`
	if [ $EXISTS -gt 0 ];then
		add_system_profile
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Flush profile done .."
	fi
fi
}

#=======================================================================
#创建MySQL服务
#=======================================================================

function el7_create_mysql_service()
{
	cat > /usr/lib/systemd/system/mysql.service <<EOF
[Unit]
Description=mysql
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
ExecStart=/usr/local/mysql/support-files/mysql.server start
ExecReload=/usr/local/mysql/support-files/mysql.server restart
ExecStop=/usr/local/mysql/support-files/mysql.server stop
LimitNOFILE = 65535
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Reload systemd services .."
	systemctl enable mysql.service && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Enable MySQL systemd service .."
	systemctl start mysql.service && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Starting MySQL......SUCCESS!" || echo_color red "$(date +'%Y-%m-%d %H:%M:%S') Starting MySQL......FAILED!."
}

function el6_create_mysql_service()
{
	cd /usr/local/mysql/support-files/
	cp mysql.server /etc/init.d/mysql  
	chmod +x /etc/init.d/mysql
	chkconfig --add mysql   && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Add MySQL service for management .."
	chkconfig --list mysql  && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') List MySQL service .."
	/etc/init.d/mysql start && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Starting MySQL......SUCCESS!" || echo_color red "$(date +'%Y-%m-%d %H:%M:%S') Starting MySQL......FAILED!."
}

#=======================================================================
# 添加帐号
#=======================================================================

function modify_mysql_account()
{
	password=`awk '/A temporary password/ {print $NF}' ${MYSQL_DATADIR}/error.log`
	#echo_color cyan "mysql temp password is ${password}"
	if [ "${password}" != "" ];then
	${MYSQL} -uroot -p"${password}"  --connect-expired-password  -e "alter user root@localhost identified by 'iforgot';flush privileges;" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 系统随机密码修改成功."
	p1=$?
	else
		echo_color red  "$(date +'%Y-%m-%d %H:%M:%S') MySQL密码获取失败，请排查/清除数据目录重新安装."
		exit 1
	fi
	${MYSQL} -uroot -piforgot -e "grant all privileges on *.* to root@'%' identified by 'iforgot';" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 授予root用户通过任意主机操作所有数据库的所有权限成功."
	p2=$?
	${MYSQL} -uroot -piforgot -e "grant RELOAD,REPLICATION SLAVE, REPLICATION CLIENT on *.* to repl@'%' identified by 'repl';" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 授予repl用户通过任意主机对所有数据库进行主从复制的权限成功."
	p3=$?
	${MYSQL} -uroot -piforgot -e "grant SELECT, PROCESS, REPLICATION CLIENT, SHOW DATABASES on *.* to monitor@'%' identified by 'monitor';" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 授予monitor用户通过任意主机对所有数据库的读取权限成功."
	p4=$?
	${MYSQL} -uroot -piforgot -e "grant SELECT,RELOAD,LOCK TABLES,REPLICATION CLIENT,PROCESS,SUPER,CREATE,SHOW DATABASES,SHOW VIEW, EVENT, TRIGGER, create tablespace on *.* to dbbackup@'localhost' identified by  'dbbackup';" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 授予dbbackup用户通过localhost主机对所有数据库进行备份的权限成功."
	p5=$?
	${MYSQL} -uroot -piforgot -e "grant insert,update,delete,select,create,drop,index,trigger,alter on *.* to producer@'%'  identified by 'iforgot';" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 授予producer用户通过任意主机对所有数据库进行常规操作的权限成功."
	p6=$?
	${MYSQL} -uroot -piforgot -e "grant insert,update,delete,select,create,drop,index,trigger,alter on *.* to producer@'localhost' identified by 'iforgot';" &> /dev/null && echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') 授予producer用户通过localhost主机对所有数据库进行常规操作的权限成功."
	p7=$?
	${MYSQL} -uroot -piforgot -e "flush privileges" &> /dev/null && echo_color cyan  "$(date +'%Y-%m-%d %H:%M:%S') 权限刷新成功."
	p8=$?
	if [[ "${p1}" == "0" && "${p2}" == "0" && "${p3}" == "0" && "${p4}" == "0" && "${p5}" == "0" && "${p6}" == "0" && "${p7}" == "0" && "${p8}" == "0" ]];then
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') 现在可以登录mysql数据库，root和producer用户的默认密码是\033[41;37m iforgot\033[0m."
		${MYSQL} -uroot -piforgot -e "select user,host,authentication_string from mysql.user;"
	else
		echo_color red "$(date +'%Y-%m-%d %H:%M:%S') 授权失败,请手动执行授权操作."
	fi
}

#=======================================================================
# 开始安装mysql
#=======================================================================
function mysql_install()
{
	version=$(uname -r |awk -F '.' '{ print $(NF-1) }')
	if [ "${version}" != "el7" ];then
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Start install mysql for el6."
		chk_install_resource
		create_sys_user
		chk_old_mysql_version
		modify_system_env
		add_libmysqlclient
		el6_create_mysql_service
		sleep 5
		modify_mysql_account
	else 
		echo_color cyan "$(date +'%Y-%m-%d %H:%M:%S') Start install mysql for el7."
		chk_install_resource
		create_sys_user
		chk_old_mysql_version
		modify_system_env
		add_libmysqlclient
		el7_create_mysql_service
		sleep 5
		modify_mysql_account
	fi
}

mysql_install
echo_color blue "$(date +'%Y-%m-%d %H:%M:%S') \033[42;37m installation_of_single_mysql.sh执行完成 \033[0m"
