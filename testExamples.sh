#!/bin/bash
set -e # Fail on error
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT # Kill subprocesses on exit

highlight() { grep --color -E "\S|$" "${@:1}" ; }
echo "Comments and Results => Black"
highlightGreen () { export GREP_COLORS='ms=0;32'; highlight ; }
echo "Server => Green" | highlightGreen
highlightBlue () { export GREP_COLORS='ms=0;34'; highlight ; }
echo "Client => Blue" | highlightBlue
highlightYellow () { export GREP_COLORS='ms=0;33'; highlight ; }
echo "Tool 1 => Yellow" | highlightYellow
highlightCyan () { export GREP_COLORS='ms=0;36'; highlight ; }
echo "Tool 2 => Cyan" | highlightCyan
lastStartedPid () { jobs -p  | tail -n 1; }

./gradlew clean --console=plain |& highlightYellow
./gradlew build --console=plain |& highlightCyan
sleep 2s

## Local
localTest() {
	echo "Starting Local test"

	# Run environment
	./gradlew :example:local-grpc-server:bootRun -x jar -x classes --console=plain |& highlightGreen &
	LOCAL_SERVER=`lastStartedPid`
	sleep 10s # Wait for the server to start
	./gradlew :example:local-grpc-client:bootRun -x jar -x classes --console=plain |& highlightBlue &
	LOCAL_CLIENT=`lastStartedPid`
	sleep 30s # Wait for the client to start and the server to be ready

	# Test
	RESPONSE=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE"
	EXPECTED=$(echo -e "Hello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Shutdown
	echo "Triggering shutdown"
	kill -s TERM $LOCAL_SERVER
	kill -s TERM $LOCAL_CLIENT
	sleep 1s # Wait for the shutdown logs to pass 

	# Verify
	if [ "$RESPONSE" = "$EXPECTED" ]; then
		echo "#----------------------#"
		echo "| Local example works! |"
		echo "#----------------------#"
	else
		echo "#-----------------------#"
		echo "| Local example failed! |"
		echo "#-----------------------#"
		exit 1
	fi
}

## Cloud-Eureka
cloudEurekaTest() {
	echo "Starting Cloud Eureka test"

	# Run environment
	./gradlew :example:cloud-eureka-server:bootRun -x jar -x classes --console=plain |& highlightYellow &
	EUREKA=`lastStartedPid`
	sleep 10s # Wait for the server to start

	mkdir -p zipkin
	cd zipkin
	echo "*" > .gitignore
	if [ ! -f zipkin.jar ]; then
		curl -sSL https://zipkin.io/quickstart.sh | bash -s
	fi
	java -jar zipkin.jar |& highlightCyan &
	ZIPKIN=`lastStartedPid`
	sleep 10s # Wait for the server to start
	cd ..

	./gradlew :example:cloud-grpc-server:bootRun -x jar -x classes --console=plain |& highlightGreen &
	CLOUD_SERVER=`lastStartedPid`
	sleep 10s # Wait for the server to start

	./gradlew :example:cloud-grpc-client:bootRun -x jar -x classes --console=plain |& highlightBlue &
	CLOUD_CLIENT=`lastStartedPid`
	sleep 30s # Wait for the client to start and the server to be ready
	sleep 60s # Wait for the discovery service to refresh

	# Test
	RESPONSE=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE"
	EXPECTED=$(echo -e "Hello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Crash server
	kill -s TERM $CLOUD_SERVER
	echo "The server crashed (expected)"
	sleep 1s # Wait for the shutdown logs to pass

	# and restart server
	./gradlew :example:cloud-grpc-server:bootRun -x jar -x classes --console=plain |& highlightGreen &
	CLOUD_SERVER=`lastStartedPid`
	sleep 30s # Wait for the server to start
	sleep 60s # Wait for the discovery service to refresh
	
	# Test again
	RESPONSE2=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE2"
	EXPECTED=$(echo -e "Hello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Shutdown
	echo "Triggering shutdown"
	kill -s TERM $EUREKA
	kill -s TERM $ZIPKIN
	kill -s TERM $CLOUD_SERVER
	kill -s TERM $CLOUD_CLIENT
	sleep 1s # Wait for the shutdown logs to pass

	# Verify part 1
	if [ "$RESPONSE" = "$EXPECTED" ]; then
		echo "#------------------------------------#"
		echo "| Cloud Eureka example part 1 works! |"
		echo "#------------------------------------#"
	else
		echo "#-------------------------------------#"
		echo "| Cloud Eureka example part 1 failed! |"
		echo "#-------------------------------------#"
		exit 1
	fi

	# Verify part 2
	if [ "$RESPONSE2" = "$EXPECTED" ]; then
		echo "#------------------------------------#"
		echo "| Cloud Eureka example part 2 works! |"
		echo "#------------------------------------#"
	else
		echo "#-------------------------------------#"
		echo "| Cloud Eureka example part 2 failed! |"
		echo "#-------------------------------------#"
		exit 1
	fi
}

## Cloud-Nacos
cloudNacosTest() {
	echo "Starting Cloud Nacos test"

	# Run environment
	docker pull nacos/nacos-server
	NACOS=`docker run --env MODE=standalone --name nacos -d -p 8848:8848 nacos/nacos-server`
	sleep 10s # Wait for the nacos server to start

	./gradlew :example:cloud-grpc-server-nacos:bootRun -x jar -x classes --console=plain |& highlightGreen &
	CLOUD_SERVER=`lastStartedPid`
	sleep 10s # Wait for the server to start

	./gradlew :example:cloud-grpc-client-nacos:bootRun -x jar -x classes --console=plain |& highlightBlue &
	CLOUD_CLIENT=`lastStartedPid`
	sleep 30s # Wait for the client to start and the server to be ready
	sleep 60s # Wait for the discovery service to refresh

	# Test
	RESPONSE=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE"
	EXPECTED=$(echo -e "Hello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Crash server
	kill -s TERM $CLOUD_SERVER
	echo "The server crashed (expected)"
	sleep 1s # Wait for the shutdown logs to pass

	# and restart server
	./gradlew :example:cloud-grpc-server-nacos:bootRun -x jar -x classes --console=plain |& highlightGreen &
	CLOUD_SERVER=`lastStartedPid`
	sleep 30s # Wait for the server to start
	sleep 60s # Wait for the discovery service to refresh
	
	# Test again
	RESPONSE2=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE2"
	EXPECTED=$(echo -e "Hello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Shutdown
	echo "Triggering shutdown"
	docker stop $NACOS
	docker rm -f $NACOS
	kill -s TERM $CLOUD_SERVER
	kill -s TERM $CLOUD_CLIENT
	sleep 1s # Wait for the shutdown logs to pass

	# Verify part 1
	if [ "$RESPONSE" = "$EXPECTED" ]; then
		echo "#-----------------------------------#"
		echo "| Cloud Nacos example part 1 works! |"
		echo "#-----------------------------------#"
	else
		echo "#------------------------------------#"
		echo "| Cloud Nacos example part 1 failed! |"
		echo "#------------------------------------#"
		exit 1
	fi

	# Verify part 2
	if [ "$RESPONSE2" = "$EXPECTED" ]; then
		echo "#-----------------------------------#"
		echo "| Cloud Nacos example part 2 works! |"
		echo "#-----------------------------------#"
	else
		echo "#------------------------------------#"
		echo "| Cloud Nacos example part 2 failed! |"
		echo "#------------------------------------#"
		exit 1
	fi
}

## Security Basic Auth
securityBasicAuthTest() {
	echo "Starting Security Basic Auth test"

	# Run environment
	./gradlew :example:security-grpc-server:bootRun -x jar -x classes --console=plain |& highlightGreen &
	LOCAL_SERVER=`lastStartedPid`
	sleep 10s # Wait for the server to start
	./gradlew :example:security-grpc-client:bootRun -x jar -x classes --console=plain |& highlightBlue &
	LOCAL_CLIENT=`lastStartedPid`
	sleep 30s # Wait for the client to start and the server to be ready

	# Test
	RESPONSE=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE"
	EXPECTED=$(echo -e "Input:\n- name: Michael (Changeable via URL param ?name=X)\nRequest-Context:\n- auth user: user (Configure via application.yml)\nResponse:\nHello ==> Michael")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Shutdown
	echo "Triggering shutdown"
	kill -s TERM $LOCAL_SERVER
	kill -s TERM $LOCAL_CLIENT
	sleep 1s # Wait for the shutdown logs to pass

	# Verify
	if [ "$RESPONSE" = "$EXPECTED" ]; then
		echo "#------------------------------------#"
		echo "| Security Basic Auth example works! |"
		echo "#------------------------------------#"
	else
		echo "#-------------------------------------#"
		echo "| Security Basic Auth example failed! |"
		echo "#-------------------------------------#"
		exit 1
	fi
}

## Security Bearer Auth
securityBearerAuthTest() {
	echo "Starting Security Bearer Auth test"

	# Run environment
	./gradlew :example:security-grpc-bearerAuth-server:bootRun -x jar -x classes --console=plain |& highlightGreen &
	LOCAL_SERVER=`lastStartedPid`
	sleep 10s # Wait for the server to start
	./gradlew :example:security-grpc-bearerAuth-client:bootRun -x jar -x classes --console=plain |& highlightBlue &
	LOCAL_CLIENT=`lastStartedPid`
	sleep 30s # Wait for the client to start and the server to be ready

	# Test
	RESPONSE=$(curl -s localhost:8080/)
	echo "Response:"
	echo "$RESPONSE"
	EXPECTED=$(echo -e "Input:\nMessage: test, Bearer Token is configured in SecurityConfiguration Class\nResponse:\nHello ==> test")
	echo "Expected:"
	echo "$EXPECTED"
	sleep 1s # Give the user a chance to look at the result

	# Shutdown
	echo "Triggering shutdown"
	kill -s TERM $LOCAL_SERVER
	kill -s TERM $LOCAL_CLIENT
	sleep 1s # Wait for the shutdown logs to pass

	# Verify
	if [ "$RESPONSE" = "$EXPECTED" ]; then
		echo "#-------------------------------------#"
		echo "| Security Bearer Auth example works! |"
		echo "#-------------------------------------#"
	else
		echo "#--------------------------------------#"
		echo "| Security Bearer Auth example failed! |"
		echo "#--------------------------------------#"
		exit 1
	fi
}

## Tests
localTest
cloudEurekaTest
cloudNacosTest
securityBasicAuthTest
#securityBearerAuthTest
