#!/bin/bash

installUtils () {
	echo "*********************************Installing WGET..."
	yum install -y wget
	
	echo "*********************************Installing Maven..."
	wget http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O 	/etc/yum.repos.d/epel-apache-maven.repo
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
	fi
	yum install -y apache-maven
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		alternatives --install /usr/bin/java java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java 20000
		alternatives --install /usr/bin/javac javac /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/javac 20000
		alternatives --install /usr/bin/jar jar /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/jar 20000
		alternatives --auto java
		alternatives --auto javac
		alternatives --auto jar
		ln -s /usr/lib/jvm/java-1.8.0 /usr/lib/jvm/java
	fi
	
	echo "*********************************Installing GIT..."
	yum install -y git
	
	echo "*********************************Installing Docker..."
	echo " 				  *****************Installing Docker via Yum..."
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		yum install -y docker
	else
		echo " 				  *****************Adding Docker Yum Repo..."
		tee /etc/yum.repos.d/docker.repo <<-'EOF'
		[dockerrepo]
		name=Docker Repository
		baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
		enabled=1
		gpgcheck=1
		gpgkey=https://yum.dockerproject.org/gpg
		EOF
		rpm -iUvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
		yum install -y docker-io
	fi
	
	echo " 				  *****************Configuring Docker Permissions..."
	groupadd docker
	gpasswd -a yarn docker
	echo " 				  *****************Registering Docker to Start on Boot..."
	service docker start
	chkconfig --add docker
	chkconfig docker on
}

waitForAmbari () {
       	# Wait for Ambari
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
        TASKSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep -Po 'OK')
        if [ "$TASKSTATUS" == OK ]; then
                LOOPESCAPE="true"
                TASKSTATUS="READY"
        else
               	AUTHSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep HTTP | grep -Po '( [0-9]+)'| grep -Po '([0-9]+)')
               	if [ "$AUTHSTATUS" == 403 ]; then
               	echo "THE AMBARI PASSWORD IS NOT SET TO: admin"
               	echo "RUN COMMAND: ambari-admin-password-reset, SET PASSWORD: admin"
               	exit 403
               	else
                TASKSTATUS="PENDING"
               	fi
       	fi
       	echo "Waiting for Ambari..."
        echo "Ambari Status... " $TASKSTATUS
        sleep 2
       	done
}

serviceExists () {
       	SERVICE=$1
        echo "*********************************Getting Service Status"
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"status" : ' | grep -Po '([0-9]+)')
        echo "*********************************$SERVICE STATUS IS $SERVICE_STATUS"
       	if [ "$SERVICE_STATUS" == 404 ]; then
          echo "$SERVICE NOT FOUND -- 404 ERROR"
       		echo 0
       	else
          Echo "$SERVICE FOUND"
       		echo 1
       	fi
}

getServiceStatus () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')

       	echo $SERVICE_STATUS
}

waitForService () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
        until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
                LOOPESCAPE="true"
            fi
            #echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

waitForServiceToStart () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED ]]; then
          echo "*********************************$SERVICE is not started -- starting loop"
        	until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED ]]; then
                echo "*********************************$SERVICE started -- exiting loop"
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

stopService () {
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Stopping Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == STARTED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Stop $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"INSTALLED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Stop $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [ "$TASKSTATUS" == COMPLETED ]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Stop $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
        echo "*********************************$SERVICE Service Stopped..."
       	elif [ "$SERVICE_STATUS" == INSTALLED ]; then
       	echo "*********************************$SERVICE Service Stopped..."
       	fi
}

startService (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Start $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"STARTED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [[ "$TASKSTATUS" == COMPLETED || "$TASKSTATUS" == FAILED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}

startServiceAndComplete (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"INSTALL COMPLETE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"STARTED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [[ "$TASKSTATUS" == COMPLETED || "$TASKSTATUS" == FAILED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}

installSchemaRegistryService () {
       	
       	echo "*********************************Creating REGISTRY service..."
       	# Create Schema Registry service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY

       	sleep 2
       	echo "*********************************Adding REGISTRY SERVER component..."
       	# Add REGISTRY SERVER component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY/components/REGISTRY_SERVER

       	sleep 2
       	echo "*********************************Creating REGISTRY configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME registry-common $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/registry-config/registry-common.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME registry-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/registry-config/registry-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME registry-log4j $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/registry-config/registry-log4j.json
		
       	echo "*********************************Adding REGISTRY SERVER role to Host..."
       	# Add REGISTRY_SERVER role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/REGISTRY_SERVER

       	sleep 30
       	echo "*********************************Installing REGISTRY Service"
       	# Install REGISTRY Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Schema Registry"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Schema Registry"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

installStreamlineService () {
       	
       	echo "*********************************Creating STREAMLINE service..."
       	# Create Streamline service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE

       	sleep 2
       	echo "*********************************Adding STREAMLINE SERVER component..."
       	# Add STREAMLINE SERVER component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE/components/STREAMLINE_SERVER

       	sleep 2
       	echo "*********************************Creating STREAMLINE configuration..."

       	# Create and apply configuration
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME streamline-common $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME streamline-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-env.json

	      /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME streamline-log4j $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-log4j.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME streamline_jaas_conf $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline_jaas_conf.json
		
       	echo "*********************************Adding STREAMLINE SERVER role to Host..."
       	# Add STREAMLINE SERVER role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/STREAMLINE_SERVER

       	sleep 30
       	echo "*********************************Installing STREAMLINE Service"
       	# Install STREAMLINE Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install SAM"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE | grep "id" | grep -Po '([0-9]+)')
		
		    sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install SAM"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
       	
	      rm -f /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar
	      rm -f /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
	      ln -s /usr/hdp/current/atlas-client/hook/storm/atlas-plugin-classloader-0.8.0.2.6.2.0-205.jar /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
	      ln -s /usr/hdp/current/atlas-client/hook/storm/storm-bridge-shim-0.8.0.2.6.2.0-205.jar /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar
}

installNifiService () {
       	echo "*********************************Creating NIFI service..."
       	# Create NIFI service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI

       	sleep 2
       	echo "*********************************Adding NIFI MASTER component..."
       	# Add NIFI Master component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER
		    curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_CA
		
       	sleep 2
       	echo "*********************************Creating NIFI configuration..."

       	# Create and apply configuration
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-config $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-config.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-ssl-config $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-ssl-config.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-authorizers-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-authorizers-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-notification-services-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-notification-services-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-flow-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-flow-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-login-identity-providers-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-login-identity-providers-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-node-logback-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-node-logback-env.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-properties $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-properties.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-state-management-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-state-management-env.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-jaas-conf $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-jaas-conf.json
				
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-logsearch-conf $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/nifi-config/nifi-logsearch-conf.json
		
       	echo "*********************************Adding NIFI MASTER role to Host..."
       	# Add NIFI Master role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_MASTER

       	echo "*********************************Adding NIFI CA role to Host..."
		    # Add NIFI CA role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_CA

       	sleep 30
       	echo "*********************************Installing NIFI Service"
       	# Install NIFI Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
		
		    sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

waitForNifiServlet () {
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
       		TASKSTATUS=$(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller | grep -Po 'OK')
       		if [ "$TASKSTATUS" == OK ]; then
               		LOOPESCAPE="true"
       		else
               		TASKSTATUS="PENDING"
       		fi
       		echo "*********************************Waiting for NIFI Servlet..."
       		echo "*********************************NIFI Servlet Status... " $TASKSTATUS
       		sleep 2
       	done
}

installDruidService () {
       	
       	echo "*********************************Creating DRUID service..."
       	# Create Druid service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID

       	sleep 2
       	echo "*********************************Adding DRUID components..."
       	# Add DRUID BROKER component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_BROKER
		    sleep 2
		    # Add DRUID COORDINATOR component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_COORDINATOR
       	# Add DRUID HISTORICAL component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_HISTORICAL
       	# Add DRUID MIDDLEMANAGER component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_MIDDLEMANAGER
		    # Add DRUID OVERLORD component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_OVERLORD
       	# Add DRUID ROUTER component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_ROUTER
       	# Add DRUID SUPERSET component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_SUPERSET
		
       	sleep 2
       	echo "*********************************Creating DRUID configuration..."

       	# Create and apply configuration
       	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-broker $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-broker.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-common $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-common.json

		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-coordinator $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-coordinator.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-env.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-historical $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-historical.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-log4j $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-log4j.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-logrotate $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-logrotate.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-middlemanager $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-middlemanager.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-overlord $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-overlord.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-router $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-router.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-superset-env $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-superset-env.json
		
		    /var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME druid-superset $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-superset.json
		
		    export HOST1=$(getHostByPosition 1)
		    export HOST2=$(getHostByPosition 2)
		    export HOST3=$(getHostByPosition 3)			
		
       	echo "*********************************Adding DRUID BROKER role to Host..."
       	# Add DRUID BROKER role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_BROKER
       	export DRUID_BROKER=$HOST1
       	
       	echo "*********************************Adding DRUID SUPERSET role to Host..."
       	# Add DRUID SUPERSET role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_SUPERSET
       	
       	echo "*********************************Adding DRUID ROUTER role to Host..."
       	# Add DRUID BROKER role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_ROUTER
       	
       	echo "*********************************Adding DRUID OVERLORD role to Host..."
       	# Add DRUID OVERLORD role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_OVERLORD
       	
       	echo "*********************************Adding DRUID COORDINATOR role to Host..."
       	# Add DRUID COORDINATOR role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_COORDINATOR
       	
       	echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_HISTORICAL
		
		    echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_HISTORICAL
       	
       	echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST3/host_components/DRUID_HISTORICAL
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_MIDDLEMANAGER
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_MIDDLEMANAGER
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST3/host_components/DRUID_MIDDLEMANAGER

       	sleep 30
       	echo "*********************************Installing DRUID Service"
       	# Install DRUID Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Druid"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID | grep "id" | grep -Po '([0-9]+)')
		
		    sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Druid"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

instalHDFManagementPack () {
  echo "*********************************WGET MPACK from Hortonworks public-repo-1"
	wget http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.1.1/tars/hdf_ambari_mp/hdf-ambari-mpack-3.0.1.1-5.tar.gz
  echo "*********************************Install HDF 3.0.1.1 MPACK"
  ambari-server install-mpack --mpack=hdf-ambari-mpack-3.0.1.1-5.tar.gz --verbose

	sleep 2
  echo "*********************************Restart AMBARI Server"
	ambari-server restart
	waitForAmbari
	sleep 2
}

getHostByPosition (){
	HOST_POSITION=$1
	HOST_NAME=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts|grep -Po '"host_name" : "[a-zA-Z0-9_\W]+'|grep -Po ' : "([^"]+)'|grep -Po '[^: "]+'|tail -n +$HOST_POSITION|head -1)
	
	echo $HOST_NAME
}

configureAmbariRepos (){
	tee /etc/yum.repos.d/docker.repo <<-'EOF'
	[HDF-3.0]
	name=HDF-3.0
	baseurl=http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.0.0
	path=/
	enabled=1
	gpgcheck=0
	EOF
	
	curl -u admin:admin -d @$ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/api-payload/repo_update.json -H "X-Requested-By: ambari" -X PUT http://$AMBARI_HOST:8080/api/v1/stacks/HDP/versions/2.6/repository_versions/1
}

installMySQL (){
  echo "*********************************Remove existing MySQL editions"
	yum remove -y mysql57-community*
	yum remove -y mysql56-server*
	yum remove -y mysql-community*
	rm -Rvf /var/lib/mysql

  echo "*********************************Install epel-release libffi-devel"
	yum install -y epel-release
	yum install -y libffi-devel.x86_64
	ln -s /usr/lib64/libffi.so.6 /usr/lib64/libffi.so.5

  echo "*********************************Install mysql-connector-java"
	yum install -y mysql-connector-java*
  echo "*********************************Set Ambari-Server jdbc-db=mysql"
	ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

  echo "*********************************If system release is Amazon, then install mysql56-server"
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then       	
		yum install -y mysql56-server
		service mysqld start
		chkconfig --levels 3 mysqld on
	else
    echo "*********************************Service is not Amazon, installing mysql-community-release-el7-5"
		yum localinstall -y https://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm
		yum install -y mysql-community-server
		#yum localinstall -y https://dev.mysql.com/get/mysql57-community-release-el7-8.noarch.rpm
    #yum install -y mysql-community-server
    echo "*********************************Starting MYSQL.service"
		systemctl start mysqld.service
		systemctl enable mysqld.service
	fi
}

setupHDFDataStores (){
  echo "*********************************Creating MySQL Databases, Users, and setting privileges -- Registry, SAM, Druid, Superset"
	mysql --execute="CREATE DATABASE registry"
	mysql --execute="CREATE DATABASE streamline"
	mysql --execute="CREATE DATABASE druid DEFAULT CHARACTER SET utf8"
	mysql --execute="CREATE DATABASE superset DEFAULT CHARACTER SET utf8"
	mysql --execute="CREATE USER 'registry'@'%' IDENTIFIED BY 'registry'"
	mysql --execute="CREATE USER 'streamline'@'%' IDENTIFIED BY 'streamline'"
	mysql --execute="CREATE USER 'druid'@'%' IDENTIFIED BY 'druid'"
	mysql --execute="CREATE USER 'superset'@'%' IDENTIFIED BY 'superset'"
	mysql --execute="GRANT ALL PRIVILEGES ON registry.* TO 'registry'@'%' WITH GRANT OPTION"
	mysql --execute="GRANT ALL PRIVILEGES ON streamline.* TO 'streamline'@'%' WITH GRANT OPTION"
	mysql --execute="GRANT ALL PRIVILEGES ON druid.* TO 'druid'@'%' WITH GRANT OPTION"
	mysql --execute="GRANT ALL PRIVILEGES ON superset.* TO 'superset'@'%' WITH GRANT OPTION"
	mysql --execute="FLUSH PRIVILEGES"
	mysql --execute="COMMIT"
}

enablePhoenix () {
	echo "*********************************Installing Phoenix Binaries..."
	yum install -y phoenix
	echo "*********************************Enabling Phoenix..."
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site phoenix.functions.allowUserDefinedFunctions true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.defaults.for.version.skip true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.regionserver.wal.codec org.apache.hadoop.hbase.regionserver.wal.IndexedWALEditCodec
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.region.server.rpc.scheduler.factory.class org.apache.hadoop.hbase.ipc.PhoenixRpcSchedulerFactory
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.rpc.controllerfactory.class org.apache.hadoop.hbase.ipc.controller.ServerRpcControllerFactory
}

export ROOT_PATH=~
echo "*********************************ROOT PATH IS: $ROOT_PATH"

export AMBARI_HOST=$(hostname -f)
echo "*********************************AMABRI HOST IS: $AMBARI_HOST"

export CLUSTER_NAME=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters |grep cluster_name|grep -Po ': "(.+)'|grep -Po '[a-zA-Z0-9\-_!?.]+')

if [[ -z $CLUSTER_NAME ]]; then
        echo "Could not connect to Ambari Server. Please run the install script on the same host where Ambari Server is installed."
        exit 1
else
       	echo "*********************************CLUSTER NAME IS: $CLUSTER_NAME"
fi

export HADOOP_USER_NAME=hdfs
echo "*********************************HADOOP_USER_NAME set to HDFS"

echo "*********************************Waiting for cluster install to complete..."
echo "*********************************Starting YARN"
waitForServiceToStart YARN
echo "*********************************Starting HDFS"
waitForServiceToStart HDFS
echo "*********************************Starting HIVE"
waitForServiceToStart HIVE
echo "*********************************Starting Zookeeper"
waitForServiceToStart ZOOKEEPER

sleep 10

export VERSION=`hdp-select status hadoop-client | sed 's/hadoop-client - \([0-9]\.[0-9]\).*/\1/'`
export INTVERSION=$(echo $VERSION*10 | bc | grep -Po '([0-9][0-9])')
echo "*********************************HDP VERSION IS: $VERSION"
echo "*********************************INTVERSION IS: $INTVERSION"

echo "*********************************REPLACING HOST NAMES WITH AMBARI HOST VALUES"
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/registry-config/registry-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{registry_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{superset_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/druid-config/druid-superset.json

echo "*********************************Stopping Prometheous..."
kill -9 $(netstat -nlp|grep 9090|grep -Po '[0-9]+/[a-zA-Z]+'|grep -Po '[0-9]+')

echo "*********************************Install ALARM_FATIGUE_DEMO_CONTROL service..."
cp -Rf $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/recipes/ALARM_FATIGUE_DEMO_CONTROL /var/lib/ambari-server/resources/stacks/HDP/$VERSION/services/

echo "*********************************Install HDF Management Pack..."
instalHDFManagementPack 
sleep 2

#echo "*********************************Configure Ambari Repos"
#configureAmbariRepos
#sleep 2

echo "*********************************Install Utilities..."
installUtils
sleep 2

echo "*********************************Install MySQL..."
installMySQL
sleep 2

echo "*********************************Setup DBs for HDF Services..."
setupHDFDataStores
sleep 2

#echo "********************************* Enabling Phoenix"
#enablePhoenix
#echo "********************************* Restarting Hbase"
#stopService HBASE
#sleep 2
#startService HBASE
#sleep 2
echo "*********************************Installing Druid"
installDruidService

sleep 2
echo "*********************************Checking Druid Status"
DRUID_STATUS=$(getServiceStatus DRUID)

if ! [[ $DRUID_STATUS == STARTED || $DRUID_STATUS == INSTALLED ]]; then
       	echo "*********************************DRUID is in a transitional state, waiting..."
       	waitForService DRUID
       	echo "*********************************DRUID has entered a ready state..."
fi

sleep 2

echo "*********************************Starting Druid"
echo "Druid Status is $DRUID_STATUS"
if [[ $DRUID_STATUS == INSTALLED ]]; then
        echo "*********************************Druid is installed -- Starting Druid"
       	startService DRUID
else
       	echo "*********************************DRUID Service Started..."
fi

sleep 2
echo "*********************************Installing Schema Registry"
installSchemaRegistryService

sleep 2
echo "*********************************Checking Schema Registry Status"
REGISTRY_STATUS=$(getServiceStatus REGISTRY)
if ! [[ $REGISTRY_STATUS == STARTED || $REGISTRY_STATUS == INSTALLED ]]; then
       	echo "*********************************REGISTRY is in a transitional state, waiting..."
       	waitForService REGISTRY
       	echo "*********************************REGISTRY has entered a ready state..."
fi

sleep 2
echo "*********************************Checking if Registry is Installed"
echo "Registry Status is $REGISTRY_STATUS"
if [[ $REGISTRY_STATUS == INSTALLED ]]; then
        echo "*********************************Registry is Installed -- Starting"
       	startService REGISTRY
else
       	echo "*********************************REGISTRY Service Started..."
fi

sleep 2
echo "*********************************Install SAM"
installStreamlineService

sleep 2
echo "*********************************Checking STREAMLINE status..."
STREAMLINE_STATUS=$(getServiceStatus STREAMLINE)
if ! [[ $STREAMLINE_STATUS == STARTED || $STREAMLINE_STATUS == INSTALLED ]]; then
       	echo "*********************************STREAMLINE is in a transitional state, waiting..."
       	waitForService STREAMLINE
       	echo "*********************************STREAMLINE has entered a ready state..."
fi

sleep 2
echo "********************************Checking if SAM is Installed"
echo "Streamline Status is $STREAMLINE_STATUS"
if [[ $STREAMLINE_STATUS == INSTALLED ]]; then
        echo "********************************SAM is Installed -- Starting"
       	startService STREAMLINE
else
       	echo "*********************************STREAMLINE Service Started..."
fi

sleep 2
echo "********************************Installing NiFi"
installNifiService

sleep 2
echo "*********************************Checking NIFI status..."
NIFI_STATUS=$(getServiceStatus NIFI)
if ! [[ $NIFI_STATUS == STARTED || $NIFI_STATUS == INSTALLED ]]; then
       	echo "*********************************NIFI is in a transitional state, waiting..."
       	waitForService NIFI
       	echo "*********************************NIFI has entered a ready state..."
fi

sleep 2
echo "NiFi Status is $NIFI_STATUS"
echo "*********************************Checking if NiFi is Installed"
if [[ $NIFI_STATUS == INSTALLED ]]; then
        echo "*********************************NiFi is Installed -- Starting"
       	startServiceAndComplete NIFI
else
       	echo "*********************************NIFI Service Started..."
fi

sleep 25
echo "*********************************Passing Parameters into Ambari Server configs.sh"
/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME control-config $ROOT_PATH/northcentral_hackathon/CloudBreakArtifacts/hdf-config/alarmfatigue-config/control-config.json

echo "*********************************Curl POST command to ALARM_FATIGUE_DEMO_CONTROL Ambari Service"
curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/ALARM_FATIGUE_DEMO_CONTROL
sleep 2

#Add role to service

curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/ALARM_FATIGUE_DEMO_CONTROL/components/ALARM_FATIGUE_DEMO_CONTROL
sleep 2

curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/ALARM_FATIGUE_DEMO_CONTROL

sleep 2
#Install Alarm Fatigue Service
TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Alarm Fatigue Controller"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/ALARM_FATIGUE_DEMO_CONTROL| grep "id" | grep -Po '([0-9]+)')

sleep 2
if [ -z $TASKID ]; then
  until ! [ -z $TASKID ]; do
    TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Alaram Fatigue Controller"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/ALARM_FATIGUE_DEMO_CONTROL | grep "id" | grep -Po '([0-9]+)')
    echo "*********************************AMBARI TaskID " $TASKID
  done
fi


sleep 2
ALARM_FATIGUE_STATUS=$(getServiceStatus ALARM_FATIGUE_DEMO_CONTROL)
echo "*********************************Checking ALARM_FATIGUE_STATUS status..."
if ! [[ $ALARM_FATIGUE_STATUS == STARTED || $ALARM_FATIGUE_STATUS == INSTALLED ]]; then
       	echo "*********************************ALARM_FATIGUE_STATUS is still being installed, waiting..."
       	waitForService ALARM_FATIGUE_DEMO_CONTROL
       	echo "*********************************ALARM_FATIGUE_STATUS has entered a ready state..."
fi

sleep 20

echo "*********************************Starting ALARM_FATIGUE_DEMO_CONTROL -- This will call alarmfatigue-demo-sam-install.sh -- Logs are in /root/demo-install.log"
startServiceAndComplete ALARM_FATIGUE_DEMO_CONTROL
echo "*********************************ALARM_FATIGUE_STATUS Service Started..."

echo "********************************* Adding Symbolic Links to Atlas Client..."
#Add symbolic links to Atlas Hooks
rm -rf /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
ln -s /usr/hdp/current/atlas-client/hook/storm/atlas-plugin-classloader-0.8.0.2.6.2.0-205.jar /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
rm -rf /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar
ln -s /usr/hdp/current/atlas-client/hook/storm/storm-bridge-shim-0.8.0.2.6.2.0-205.jar /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar

echo "Installation Complete"