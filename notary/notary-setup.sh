#!/bin/bash -e
echo "notary setup start"

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
CPB_ALIAS="Notary cpb cert"

NOTARY_CPI_FILE="Notary-1.0.0.0-SNAPSHOT.cpi"

KEY_CERT="notary-cpi-cert.pem"
NOTARY_CPB_FILE="notary-plugin-non-validating-server-5.2.2.0-package.cpb"

RUNTIME_OS_PATH="/home/shiielu/corda5-2-local/corda-runtime-os"
CERTIFICATE_REQUEST_PATH="request.csr"
CERTIFICATE_PATH="/tmp/ca/request/certificate.pem"
NOTARY_CPB_CERT="notary-ca-root.pem"
GROUP_POLICY="GroupPolicy.json"
MGM_VNODE_X500_NAME="CN=MGM, O=Local, L=London, C=GB"
NOTARY_KEY_X500_NAME="CN=Notary CPI Signing Key, O=R3, L=London, C=GB"
NOTARY_VNODE_X500_NAME="CN=Notary, O=Local, L=London, C=GB"
NOTARY_SERVICE_X500_NAME="CN=NotaryService, O=Local, L=London, C=GB"


# グループポリシー作成
if [[ -e "$WORK_DIR/$GROUP_POLICY" ]]; then
    rm  "$WORK_DIR/$GROUP_POLICY"
    echo "group policy regenerate"
fi
# MGM仮想ノードのIDを取得

RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/virtualnode)
echo "$RESPONSE" | jq .
MGM_HOLDING_ID=$(echo "$RESPONSE" | jq -r --arg xname "$MGM_VNODE_X500_NAME"  '.virtualNodes[] | select(.holdingIdentity.x500Name == $xname) | .holdingIdentity.shortHash')
echo $MGM_HOLDING_ID


# グループポリシーファイルをMGMからエクスポート
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/mgm/$MGM_HOLDING_ID/info | jq . > "$WORK_DIR/$GROUP_POLICY"


if [[ -e "$WORK_DIR/$KEY_STORE" ]]; then
    rm  "$WORK_DIR/$KEY_STORE"
    echo "key store regenerate"
fi
#Notary CPI署名鍵作成
keytool -genkeypair -alias "$KEY_ALIAS" -keystore "$KEY_STORE" -storepass "$STORE_PASS" -dname "$NOTARY_KEY_X500_NAME" -keyalg RSA -storetype pkcs12 -validity 4000


# CPB証明書をインポート
keytool -importcert -keystore "$KEY_STORE" -storepass "$STORE_PASS" -noprompt -alias "$CPB_ALIAS" -file "$NOTARY_CPB_CERT"

# Notary CPI作成
if [[ -e "$WORK_DIR/$NOTARY_CPI_FILE" ]]; then
    rm "$WORK_DIR/$NOTARY_CPI_FILE"
    echo "cpi file regenerate"
fi
corda-cli.sh package create-cpi \
--group-policy "$WORK_DIR/GroupPolicy.json" \
--cpb "$WORK_DIR/$NOTARY_CPB_FILE" \
--cpi-name "Notary" \
--cpi-version "1.0.0.0-SNAPSHOT" \
--file "$WORK_DIR/$NOTARY_CPI_FILE" \
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

curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="notary-cpi-key" -F certificate=@"$WORK_DIR/$NOTARY_CPB_CERT" $REST_API_URL/certificate/cluster/code-signer
sleep 1
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="notary-ca-root-key" -F certificate=@"$WORK_DIR/$KEY_CERT" $REST_API_URL/certificate/cluster/code-signer
echo "CPI cert uploaded to corda"

# CPIをCordaへアップロード

RESPONSE=$(curl -k -u "$REST_API_USER:$REST_API_PASSWORD" -F upload=@$WORK_DIR/$NOTARY_CPI_FILE $REST_API_URL/cpi/)
echo "$RESPONSE" | jq .
echo "CPI uploaded to corda"
CPI_ID=$(echo "$RESPONSE" | jq -r '.id')

# CPIチェックサム取得
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/cpi/status/$CPI_ID)
echo "$RESPONSE" | jq .
CPI_CHECKSUM=$(echo "$RESPONSE" | jq -r '.cpiFileChecksum')

# Notary仮想ノード作成

RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "{\"request\": {\"cpiFileChecksum\": \"$CPI_CHECKSUM\", \"x500Name\": \"$NOTARY_VNODE_X500_NAME\"}}" $REST_API_URL/virtualnode)
echo "$RESPONSE" | jq .
echo "Notary VNode created"


REQUEST_ID=$(echo "$RESPONSE" | jq -r '.requestId')
echo "request ID: $REQUEST_ID"

sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/virtualnode/status/$REQUEST_ID)
echo "$RESPONSE" | jq .
NOTARY_HOLDING_ID=$(echo "$RESPONSE" | jq -r '.resourceId')
echo "Notary holding ID: $NOTARY_HOLDING_ID"

# セッション開始キー(MGMとのTLS通信用)の作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$NOTARY_HOLDING_ID/SESSION_INIT

RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$NOTARY_HOLDING_ID/alias/$NOTARY_HOLDING_ID-session/category/SESSION_INIT/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
SESSION_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and session key created"
echo "sessison key: $SESSION_KEY_ID"

# Notary keyの作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$NOTARY_HOLDING_ID/NOTARY

RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$NOTARY_HOLDING_ID/alias/$NOTARY_HOLDING_ID-notary/category/NOTARY/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
NOTARY_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and notary key created"
echo "notary key: $SESSION_KEY_ID"

# notaryの通信プロパティ編集

curl -i -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -d '{"p2pTlsCertificateChainAlias": "p2p-tls-cert", "useClusterLevelTlsCertificateAndKey": true, "sessionKeysAndCertificates": [{"sessionKeyId": "'$SESSION_KEY_ID'", "preferred": true}]}' $REST_API_URL/network/setup/$NOTARY_HOLDING_ID
echo " notary communication property configured"

# ビルド登録コンテキスト(ネットワークへのnotary登録用)の作成


REGISTRATION_CONTEXT='{
  "corda.session.keys.0.id": "'$SESSION_KEY_ID'",
  "corda.session.keys.0.signature.spec": "SHA256withECDSA",
  "corda.notary.keys.0.id": "'$NOTARY_KEY_ID'",
  "corda.notary.keys.0.signature.spec": "SHA256withECDSA",
  "corda.endpoints.0.connectionURL": "https://'$P2P_GATEWAY_HOST':'$P2P_GATEWAY_PORT'",
  "corda.endpoints.0.protocolVersion": "1",
  "corda.roles.0": "notary",
  "corda.notary.service.name": "'$NOTARY_SERVICE_X500_NAME'",
  "corda.notary.service.flow.protocol.name": "com.r3.corda.notary.plugin.nonvalidating",
  "corda.notary.service.flow.protocol.version.0": "1"
}'

# notaryのネットワークへの登録
REGISTRATION_REQUEST='{"memberRegistrationRequest":{"context": '$REGISTRATION_CONTEXT'}}'

RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "$REGISTRATION_REQUEST" $REST_API_URL/membership/$NOTARY_HOLDING_ID)
echo "$RESPONSE" | jq .


# ネットワーク登録状況確認
REGISTRATION_ID=$(echo "$RESPONSE" | jq -r '.registrationId')
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/membership/$NOTARY_HOLDING_ID/$REGISTRATION_ID)
echo "$RESPONSE" | jq .
echo "notary setup finished"

