FROM centos:7

RUN yum install -y java-1.8.0-openjdk-devel make gcc-c++ wget
ENV JAVA_HOME /usr/lib/jvm/java-1.8.0-openjdk

ARG ACCUMULO_VERSION=1.9.2
ARG HADOOP_VERSION=2.8.5
ARG ZOOKEEPER_VERSION=3.4.13
ARG HADOOP_USER_NAME=accumulo
ARG ACCUMULO_FILE=
ARG HADOOP_FILE=
ARG ZOOKEEPER_FILE=

ENV HADOOP_USER_NAME $HADOOP_USER_NAME

ENV APACHE_DIST_URLS \
  https://www.apache.org/dyn/closer.cgi?action=download&filename= \
# if the version is outdated (or we're grabbing the .asc file), we might have to pull from the dist/archive :/
  https://www-us.apache.org/dist/ \
  https://www.apache.org/dist/ \
  https://archive.apache.org/dist/


RUN set -eux; \
  download() { \
    local f="$1"; shift; \
    local distFile="$1"; shift; \
    local success=; \
    local distUrl=; \
    for distUrl in $APACHE_DIST_URLS; do \
      if wget -nv -O "$f" "$distUrl$distFile"; then \
        success=1; \
        break; \
      fi; \
    done; \
    [ -n "$success" ]; \
  }; \
  \
  if [ -z "$HADOOP_FILE" ]; then \
    download "hadoop.tar.gz" "hadoop/core/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"; \
  else \
    cp "/tmp/$HADOOP_FILE" "hadoop.tar.gz"; \
  fi; \
  if [ -z "$ZOOKEEPER_FILE" ]; then \
    download "zookeeper.tar.gz" "zookeeper/zookeeper-$ZOOKEEPER_VERSION/zookeeper-$ZOOKEEPER_VERSION.tar.gz"; \
  else \
    cp "/tmp/$ZOOKEEPER_FILE" "zookeeper.tar.gz"; \
  fi; \
  if [ -z "$ACCUMULO_FILE" ]; then \
    download "accumulo.tar.gz" "accumulo/$ACCUMULO_VERSION/accumulo-$ACCUMULO_VERSION-bin.tar.gz"; \
  else \
    cp "/tmp/$ACCUMULO_FILE" "accumulo.tar.gz"; \
  fi;

RUN tar xzf accumulo.tar.gz -C /tmp/
RUN tar xzf hadoop.tar.gz -C /tmp/
RUN tar xzf zookeeper.tar.gz -C /tmp/

RUN cp -r /tmp/hadoop-$HADOOP_VERSION/. /opt/hadoop
RUN cp -r /tmp/zookeeper-$ZOOKEEPER_VERSION/. /opt/zookeeper
RUN cp -r /tmp/accumulo-$ACCUMULO_VERSION/. /opt/accumulo

RUN cp /opt/accumulo/conf/examples/2GB/native-standalone/* /opt/accumulo/conf/
RUN /opt/accumulo/bin/build_native_library.sh

ADD ./accumulo-site.xml /opt/accumulo/conf
ADD ./generic_logger.xml /opt/accumulo/conf
ADD ./monitor_logger.xml /opt/accumulo/conf

ENV HADOOP_HOME /opt/hadoop
ENV ZOOKEEPER_HOME /opt/zookeeper
ENV ACCUMULO_HOME /opt/accumulo
ENV PATH "$PATH:$ACCUMULO_HOME/bin"

######################GeoMesa Installation
#Download GeoMesa/Accumulo binary distribution on geomesa.org

WORKDIR   /tmp/
RUN wget https://repo.locationtech.org/content/repositories/geomesa-releases/org/locationtech/geomesa/geomesa-accumulo-dist_2.11/1.3.2/geomesa-accumulo-dist_2.11-1.3.2-bin.tar.gz
RUN tar xzf geomesa-accumulo-dist_2.11-1.3.2-bin.tar.gz -C /tmp/
RUN rm geomesa-accumulo-dist_2.11-1.3.2-bin.tar.gz
RUN cp -r geomesa-accumulo_2.11-1.3.2/. /opt/geomesa

ENV GEOMESA_HOME=/opt/geomesa
ENV PATH=$PATH:$GEOMESA_HOME/bin/

#Copy the JARs to accumulo

WORKDIR   /opt/geomesa/dist/accumulo
RUN cp geomesa-accumulo-distributed-runtime_2.11-1.3.2.jar /opt/accumulo/lib/ext/
RUN cp geomesa-accumulo-raster-distributed-runtime_2.11-1.3.2.jar /opt/accumulo/lib/ext/



#Configure namespace:
WORKDIR   /opt/geomesa/

RUN bin/install-jai.sh
RUN bin/install-jline.sh

RUN chmod -R u+x /opt/geomesa && \
    chgrp -R 0 /opt/geomesa && \
    chmod -R u+x /opt/accumulo && \
    chgrp -R 0 /opt/accumulo && \
    chmod -R u+x /opt/hadoop && \
    chgrp -R 0 /opt/hadoop && \
    chmod -R u+x /opt/zookeeper && \
    chgrp -R 0 /opt/zookeeper && \
    chmod -R g=u /opt /etc/passwd

COPY bin/ ${GEOMESA_HOME}/bin/
RUN chmod -R u+x ${GEOMESA_HOME}/bin/run && \
    chgrp -R 0 ${GEOMESA_HOME}/bin/run 
RUN chmod -R u+x ${GEOMESA_HOME}/bin/uid_entrypoint && \
    chgrp -R 0 ${GEOMESA_HOME}/bin/uid_entrypoint 

RUN yum install which -y 



COPY core-site.xml /opt/hadoop/etc/hadoop

RUN chmod -R u+x /usr/sbin && \
    chgrp -R 0 /usr/sbin

RUN yum update -y && yum install -y openssh-server
RUN mkdir /var/run/sshd
RUN echo 'root:THEPASSWORDYOUCREATED' | chpasswd
RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config



ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
RUN yum install openssh-clients -y
RUN yum install ssh* -y


EXPOSE 9000 8020 22
### Containers should NOT run as root as a good practice
WORKDIR ${GEOMESA_HOME}

### user name recognition at runtime w/ an arbitrary uid - for OpenShift deployments
ENTRYPOINT ["sh", "bin/uid_entrypoint"]

VOLUME ${GEOMESA_HOME}/logs ${GEOMESA_HOME}/data
CMD run
