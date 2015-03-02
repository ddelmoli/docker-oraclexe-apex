FROM centos:7.0.1406
MAINTAINER ddelmoli <ddelmoli@gmail.com>
# 
# Based on the shell scripts by Martin Giffy D'Souza martindsouza 
# https://github.com/OraOpenSource/oraclexe-apex
#

#
# Update and install packages
#
USER root
RUN yum update -y && yum install -y \
   bc \
   firewalld \
   git \
   java-1.7.0-openjdk-src.x86-64 \
   java \
   libaio \
   net-tools \
   openssh-server \
   passwd \
   unzip \
   which

#
# Install nodejs from package
#
RUN curl -sL https://rpm.nodesource.com/setup | bash - && yum install -y \
   nodejs

#
# Add oracle-xe rpm and apex 4.2.6 zip
#
ADD oracle-xe-11.2.0-1.0.x86_64.rpm /tmp/
ADD apex_4.2.6_en.zip /tmp/

#
# Install oracle-xe; fake out swap checks
#
RUN sha1sum /tmp/oracle-xe-11.2.0-1.0.x86_64.rpm | grep -q "49e850d18d33d25b9146daa5e8050c71c30390b7" \
   && mv /usr/bin/free /usr/bin/free.bak \
   && mv /sbin/sysctl /sbin/sysctl.bak \
   && printf '#!/bin/sh\necho Swap - - 2048' > /usr/bin/free \
   && printf '#!/bin/sh' > /sbin/sysctl \
   && chmod +x /usr/bin/free \
   && chmod +x /sbin/sysctl \
   && rpm --install /tmp/oracle-xe-11.2.0-1.0.x86_64.rpm \
   && rm /usr/bin/free \
   && rm /sbin/sysctl \
   && mv /usr/bin/free.bak /usr/bin/free \
   && mv /sbin/sysctl.bak /sbin/sysctl \
   && rm /tmp/oracle-xe-11.2.0-1.0.x86_64.rpm

#
# Configure Oracle
# 
RUN printf '\
ORACLE_HTTP_PORT=8080 \n\
ORACLE_LISTENER_PORT=1521 \n\
ORACLE_PASSWORD=oracle \n\
ORACLE_CONFIRM_PASSWORD=oracle \n\
ORACLE_DBENABLE=y \n\
' > /tmp/xe.rsp \
    && sed -i -e 's/^\(memory_target=.*\)/#\1/' /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora \
    && sed -i -e 's/^\(memory_target=.*\)/#\1/' /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora \
    && mkdir /var/lock/subsys \
    && /etc/init.d/oracle-xe configure responseFile=/tmp/xe.rsp \
    && rm /tmp/xe.rsp

#
# Upgrade APEX
#
RUN printf '\
@apexins SYSAUX SYSAUX TEMP /i/ \n\
' > /tmp/run_apexins.sql \
   && printf '\
@apxxepwd Oracle1! \n\
exit \n\
' > /tmp/run_apxxepwd.sql \
   && unzip -q /tmp/apex_4.2.6_en.zip -d /tmp \
   && sed -i -E "s/HOST = [^)]+/HOST = $HOSTNAME/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora \
   && /etc/init.d/oracle-xe start \
   && cd /tmp/apex \
   && export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe \
   && export PATH=$ORACLE_HOME/bin:$PATH \
   && export ORACLE_SID=XE \
   && sqlplus sys/oracle as sysdba @../run_apexins.sql \
   && sqlplus sys/oracle as sysdba @../run_apxxepwd.sql \
   && /etc/init.d/oracle-xe stop

# Configure OpenSSH & set a password for oracle user.
# You can change this password with:
# docker exec -ti oracle_app passwd oracle
RUN ssh-keygen -h -A \
    && echo "oracle" | passwd --stdin oracle \
    && printf '\
export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe \n\
export PATH=$ORACLE_HOME/bin:$PATH \n\
export ORACLE_SID=XE \n\
' >> /etc/bash.bashrc
    
EXPOSE 22 1521 8080

CMD sed -i -E "s/HOST = [^)]+/HOST = $HOSTNAME/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora; \
    /etc/init.d/oracle-xe start; \
    /usr/sbin/sshd -D
