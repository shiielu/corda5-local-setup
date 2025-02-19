#!/bin/bash -e
echo "MGM setup start"

RPC_HOST=localhost
RPC_PORT=8888
P2P_GATEWAY_HOST=corda-p2p-gateway-worker.corda
P2P_GATEWAY_PORT=8080

REST_API_URL="https://$RPC_HOST:$RPC_PORT/api/v5_2"

REST_API_USER="admin"
REST_API_PASSWORD="admin"

WORK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

KEY_STORE="signingkeys.pfx"
STORE_PASS="keystore password"
KEY_ALIAS="signing key 1"

MGM_FILE="MGM-1.0.0.0-SNAPSHOT.cpi"

KEY_CERT="mgm-cpi-cert.pem"


RUNTIME_OS_PATH="/home/shiielu/corda5-local-setup/corda-runtime-os"
CERTIFICATE_REQUEST_PATH="request.csr"
CERTIFICATE_PATH="/tmp/ca/request/certificate.pem"

MGM_KEY_X500NAME="CN=MGM CPI Signing Key, O=R3, L=London, C=GB"
MGM_VNODE_X500_NAME="CN=MGM, O=Local, L=London, C=GB"

#MGM CPI署名鍵作成


if [[ -e "$WORK_DIR/$KEY_STORE" ]]; then
    rm  "$WORK_DIR/$KEY_STORE"
    echo "key store regenerate"
fi
keytool -genkeypair -alias "$KEY_ALIAS" -keystore "$KEY_STORE" -storepass "$STORE_PASS" -dname "$MGM_KEY_X500NAME" -keyalg RSA -storetype pkcs12 -validity 4000
sleep 1

# MGM CPI作成
if [[ -e "$WORK_DIR/$MGM_FILE" ]]; then
    rm "$WORK_DIR/$MGM_FILE"
    echo "cpi file regenerate"
fi
corda-cli.sh package create-cpi \
--group-policy "$WORK_DIR/GroupPolicy.json" \
--cpi-name "MGM" \
--cpi-version "1.0.0.0-SNAPSHOT" \
--file "$WORK_DIR/$MGM_FILE" \
--keystore "$WORK_DIR/$KEY_STORE" \
--storepass "$STORE_PASS" \
--key "$KEY_ALIAS"
echo "cpi created"
sleep 1
# 署名検証用の証明書作成
if [[ -e "$WORK_DIR/$KEY_CERT" ]]; then
    rm  "$WORK_DIR/$KEY_CERT"
    echo "cpi singed cert regenerate"
fi
keytool -exportcert -rfc -alias "$KEY_ALIAS" -keystore "$KEY_STORE" -storepass "$STORE_PASS" -file "$KEY_CERT"
echo "CPI cert created"





# 証明書をCordaへアップロード
sleep 5
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="mgm-cpi-key-cert" -F certificate=@"$WORK_DIR/$KEY_CERT" $REST_API_URL/certificate/cluster/code-signer
echo "CPI cert uploaded to corda"

# CPIをCordaへアップロード
sleep 5
RESPONSE=$(curl -k -u "$REST_API_USER:$REST_API_PASSWORD" -F upload=@$WORK_DIR/$MGM_FILE $REST_API_URL/cpi/)
echo "$RESPONSE" | jq .
echo "CPI uploaded to corda"
CPI_ID=$(echo "$RESPONSE" | jq -r '.id')


# CPIチェックサム取得
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/cpi/status/$CPI_ID)
echo "$RESPONSE" | jq .
CPI_CHECKSUM=$(echo "$RESPONSE" | jq -r '.cpiFileChecksum')

# MGM仮想ノード作成
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "{\"request\": {\"cpiFileChecksum\": \"$CPI_CHECKSUM\", \"x500Name\": \"$MGM_VNODE_X500_NAME\"}}" $REST_API_URL/virtualnode)
echo "$RESPONSE" | jq .
echo "MGM VNode created"


REQUEST_ID=$(echo "$RESPONSE" | jq -r '.requestId')
echo "request ID: $REQUEST_ID"

sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/virtualnode/status/$REQUEST_ID)
echo "$RESPONSE" | jq .
MGM_HOLDING_ID=$(echo "$RESPONSE" | jq -r '.resourceId')
echo "MGM holding ID: $MGM_HOLDING_ID"

# セッション開始キー(MGMとのTLS通信用)の作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$MGM_HOLDING_ID/SESSION_INIT
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$MGM_HOLDING_ID/alias/$MGM_HOLDING_ID-session/category/SESSION_INIT/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
SESSION_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and session key created"
echo "sessison key: $SESSION_KEY_ID"

# ECDHキー(ネットワークメンバー認証用)の作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$MGM_HOLDING_ID/PRE_AUTH
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$MGM_HOLDING_ID/alias/$MGM_HOLDING_ID-auth/category/PRE_AUTH/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
ECDH_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and ecdh key created"
echo "ecdh key: $ECDH_KEY_ID"

# クラスタレベルのP2P TLS通信キー作成(クラスタ単位で一度だけ実行)
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST -H "Content-Type: application/json" $REST_API_URL/key/p2p/alias/p2p-TLS/category/TLS/scheme/CORDA.RSA)
echo "$RESPONSE" | jq .
CLUSTER_TLS_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and cluster tls key created"
echo "cluster tls key: $CLUSTER_TLS_KEY_ID"

# プライベートCA作成 /tmp/ca/ca/root-certificate.pemが作成される


if [ -e "/tmp/ca" ]; then
    rm -r /tmp/ca
    echo "private ca regenerate"
fi
cd "$RUNTIME_OS_PATH"
./gradlew :applications:tools:p2p-test:fake-ca:clean :applications:tools:p2p-test:fake-ca:appJar
java -jar ./applications/tools/p2p-test/fake-ca/build/bin/corda-fake-ca-*.jar -m /tmp/ca -a RSA -s 3072 ca
echo "private CA created"
cd "$WORK_DIR"
sleep 1
# キーの証明書リクエスト(CSR)を作成
if [[ -e "$WORK_DIR/$CERTIFICATE_REQUEST_PATH" ]]; then
    rm "$WORK_DIR/$CERTIFICATE_REQUEST_PATH"
    echo "cluster tls csr regenerate"
fi
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD  -X POST -H "Content-Type: application/json"  -i -d '{"x500Name": "CN=CordaOperator, C=GB, L=London, O=Org", "subjectAlternativeNames": ["'$P2P_GATEWAY_HOST'"]}' $REST_API_URL"/certificate/p2p/"$CLUSTER_TLS_KEY_ID > "$WORK_DIR"/"$CERTIFICATE_REQUEST_PATH")
echo "$RESPONSE" | jq .
echo "csr created"

# プライベートCAで証明書作成 /tmp/ca/request1/certificate.pemに作成される
sleep 1
if [[ -e "$WORK_DIR/$CERTIFICATE_PATH" ]]; then
    rm $WORK_DIR/$CERTIFICATE_PATH
    echo "key cluster tls certificate regenerate"
fi

cd "$RUNTIME_OS_PATH"
java -jar applications/tools/p2p-test/fake-ca/build/bin/corda-fake-ca-*.jar -m /tmp/ca csr "$WORK_DIR"/"$CERTIFICATE_REQUEST_PATH"
echo "certificate created by private CA"
cd "$WORK_DIR"

# 証明書をCordaへアップロード
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -i -F certificate=@"$CERTIFICATE_PATH" -F alias=p2p-tls-cert $REST_API_URL/certificate/cluster/p2p-tls)
echo "cluster tls certificate uploaded to corda"

# ビルド登録コンテキスト(ネットワークへのMGM登録用)の作成


TLS_CA_CERT=$(cat /tmp/ca/ca/root-certificate.pem | awk '{printf "%s\\n", $0}')
REGISTRATION_CONTEXT='{
  "corda.session.keys.0.id": "'$SESSION_KEY_ID'",
  "corda.ecdh.key.id": "'$ECDH_KEY_ID'",
  "corda.group.protocol.registration": "net.corda.membership.impl.registration.dynamic.member.DynamicMemberRegistrationService",
  "corda.group.protocol.synchronisation": "net.corda.membership.impl.synchronisation.MemberSynchronisationServiceImpl",
  "corda.group.protocol.p2p.mode": "Authenticated_Encryption",
  "corda.group.key.session.policy": "Distinct",
  "corda.group.pki.session": "NoPKI",
  "corda.group.pki.tls": "Standard",
  "corda.group.tls.type": "OneWay",
  "corda.group.tls.version": "1.3",
  "corda.endpoints.0.connectionURL": "https://'$P2P_GATEWAY_HOST':'$P2P_GATEWAY_PORT'",
  "corda.endpoints.0.protocolVersion": "1",
  "corda.group.trustroot.tls.0" : "'$TLS_CA_CERT'"
}'

# MGMのネットワークへの登録
REGISTRATION_REQUEST='{"memberRegistrationRequest":{"context": '$REGISTRATION_CONTEXT'}}'
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "$REGISTRATION_REQUEST" $REST_API_URL/membership/$MGM_HOLDING_ID)
echo "$RESPONSE" | jq .

# ネットワーク登録状況確認
REGISTRATION_ID=$(echo "$RESPONSE" | jq -r '.registrationId')
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/membership/$MGM_HOLDING_ID/$REGISTRATION_ID)
echo "$RESPONSE" | jq .

# MGMの通信プロパティ編集
sleep 5
curl -i -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -d '{"p2pTlsCertificateChainAlias": "p2p-tls-cert", "useClusterLevelTlsCertificateAndKey": true, "sessionKeysAndCertificates": [{"sessionKeyId": "'$SESSION_KEY_ID'", "preferred": true}]}' $REST_API_URL/network/setup/$MGM_HOLDING_ID
echo "MGM setup finished"
